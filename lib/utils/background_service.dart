import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

// Initialize the notification plugin
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

// Entry point for the background service
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // CRITICAL: Ensure plugin registrant is initialized
  DartPluginRegistrant.ensureInitialized();

  final AudioRecorder recorder = AudioRecorder();
  Timer? recordingTimer;

  // --- State Variables for the Service ---
  int duration = 0;
  bool isAutoStopEnabled = true;
  DateTime? autoStopTargetTime;
  bool isRecording = false;
  // ---

  // --- HELPER FUNCTION ---
  Future<void> stopRecordingAndService(ServiceInstance service) async {
    if (!isRecording) return;

    isRecording = false;
    recordingTimer?.cancel();
    recordingTimer = null;

    try {
      final path = await recorder.stop();
      duration = 0;

      if (path != null) {
        // Send the final file path back to the UI
        service.invoke('recordingStopped', {'path': path});
      }
    } catch (e) {
      print('Error stopping recording: $e');
      service.invoke('recordingError', {'error': e.toString()});
    }

    // Stop the foreground service
    service.stopSelf();
  }
  // --- END HELPER FUNCTION ---

  // Main timer that runs every second while recording
  void startMainTimer() {
    recordingTimer?.cancel();
    recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      duration++;

      // --- Auto-Stop Logic ---
      int? remainingSeconds;
      if (isAutoStopEnabled && autoStopTargetTime != null) {
        final remaining = autoStopTargetTime!.difference(DateTime.now());
        remainingSeconds = remaining.inSeconds;

        if (remaining.inSeconds <= 0) {
          // Time is up, stop the recording and service
          await stopRecordingAndService(service);
          return;
        }
      }
      // --- End Auto-Stop Logic ---

      // Update the persistent notification with the current status
      updateNotification(duration, remainingSeconds);

      // Send a comprehensive 'update' message to the UI with all current state
      service.invoke('update', {
        'duration': duration,
        'isAutoStopEnabled': isAutoStopEnabled,
        'remainingSeconds': remainingSeconds,
      });
    });
  }

  // --- SERVICE LISTENERS ---

  // Handles the 'startRecording' command from the UI
  service.on('startRecording').listen((event) async {
    if (isRecording) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final recordingPath = '${dir.path}/recording_$timestamp.m4a';

      // Reset duration
      duration = 0;

      if (event != null) {
        isAutoStopEnabled = event['isAutoStopEnabled'] as bool? ?? true;
        if (isAutoStopEnabled) {
          final minutes = event['minutes'] as int? ?? 5;
          autoStopTargetTime = DateTime.now().add(Duration(minutes: minutes));
        } else {
          autoStopTargetTime = null;
        }
      }

      await recorder.start(const RecordConfig(), path: recordingPath);
      isRecording = true;
      startMainTimer();

      // Notify UI that recording started
      service.invoke('recordingStarted', {'path': recordingPath});
    } catch (e) {
      print('Error starting recording: $e');
      service.invoke('recordingError', {'error': e.toString()});
    }
  });

  // Handles the 'stopRecording' command from the UI
  service.on('stopRecording').listen((event) async {
    await stopRecordingAndService(service);
  });

  // Handles the 'toggleAutoStop' command from the UI's switch
  service.on('toggleAutoStop').listen((event) {
    if (event == null) return;
    isAutoStopEnabled = event['enabled'] as bool? ?? false;
    if (isAutoStopEnabled) {
      final minutes = event['minutes'] as int? ?? 5;
      autoStopTargetTime = DateTime.now().add(Duration(minutes: minutes));
    } else {
      autoStopTargetTime = null;
    }
  });

  // Handles the 'extendRecording' command from the UI's "Extend" button
  service.on('extendRecording').listen((event) {
    if (autoStopTargetTime != null) {
      final extensionMinutes = event?['minutes'] as int? ?? 5;
      autoStopTargetTime = autoStopTargetTime!.add(Duration(minutes: extensionMinutes));
    }
  });

  // Handle service stop request
  service.on('stop').listen((event) async {
    await stopRecordingAndService(service);
  });
}

// Helper function to format and display the ongoing notification
void updateNotification(int duration, int? remainingSeconds) {
  final durationString =
      '${(duration ~/ 60).toString().padLeft(2, '0')}:${(duration % 60).toString().padLeft(2, '0')}';
  String content = 'Duration: $durationString';

  if (remainingSeconds != null && remainingSeconds > 0) {
    final remainingString =
        '${(remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(remainingSeconds % 60).toString().padLeft(2, '0')}';
    content += ' | Stops in: $remainingString';
  }

  flutterLocalNotificationsPlugin.show(
    1, // Notification ID
    'Recording in Progress',
    content,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'recording_channel',
        'Recording Channel',
        importance: Importance.low,
        icon: '@mipmap/ic_launcher',
        ongoing: true,
        playSound: false,
        enableVibration: false,
      ),
    ),
  );
}

// Initialization function called from main.dart
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  // Initialize notifications
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
  InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Create notification channel
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'recording_channel',
    'Recording Channel',
    description: 'This channel is used for recording notifications.',
    importance: Importance.low,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: false,
      notificationChannelId: 'recording_channel',
      initialNotificationTitle: 'Voice Recorder',
      initialNotificationContent: 'Ready to record',
      foregroundServiceNotificationId: 1,
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      autoStart: false,
    ),
  );
}