import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'transcription_screen.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final service = FlutterBackgroundService();

  // --- UI State Variables ---
  bool _isRecording = false;
  int _recordingDuration = 0;
  bool _isAutoStopEnabled = true;
  int? _remainingSeconds;
  bool _shouldShowExtensionButton = false;

  StreamSubscription? _updateSubscription;
  StreamSubscription? _stoppedSubscription;
  StreamSubscription? _startedSubscription;
  StreamSubscription? _errorSubscription;
  // ---

  @override
  void initState() {
    super.initState();
    _initializeListeners();
  }

  Future<void> _initializeListeners() async {
    // Check if the service is already running when the screen is opened
    final isRunning = await service.isRunning();
    if (mounted) {
      setState(() => _isRecording = isRunning);
    }

    // Listen for state updates from the service
    _updateSubscription = service.on('update').listen((event) {
      if (mounted && event != null) {
        setState(() {
          _recordingDuration = event['duration'] as int? ?? 0;
          _isAutoStopEnabled = event['isAutoStopEnabled'] as bool? ?? false;
          _remainingSeconds = event['remainingSeconds'] as int?;
          // Show the extend button in the last 10 seconds
          _shouldShowExtensionButton =
              _remainingSeconds != null && _remainingSeconds! <= 10 && _remainingSeconds! > 0;
        });
      }
    });

    // Listen for recording started confirmation
    _startedSubscription = service.on('recordingStarted').listen((event) {
      if (mounted) {
        setState(() => _isRecording = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording started'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });

    // Listen for the final recording path
    _stoppedSubscription = service.on('recordingStopped').listen((event) {
      if (mounted) {
        // Reset UI state first
        setState(() {
          _isRecording = false;
          _recordingDuration = 0;
          _remainingSeconds = null;
          _shouldShowExtensionButton = false;
        });

        if (event != null && event['path'] != null) {
          final path = event['path'] as String;
          // Navigate to transcription screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TranscriptionScreen(audioPath: path),
            ),
          );
        }
      }
    });

    // Listen for errors
    _errorSubscription = service.on('recordingError').listen((event) {
      if (mounted) {
        setState(() => _isRecording = false);
        final error = event?['error'] ?? 'Unknown error occurred';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recording error: $error'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _updateSubscription?.cancel();
    _stoppedSubscription?.cancel();
    _startedSubscription?.cancel();
    _errorSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startRecording() async {
    // Request microphone permission
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is required to record'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Request notification permission (Android 13+)
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // Get settings from the user first
    final settings = await _showAutoStopDialog();
    if (settings == null) return; // User cancelled

    try {
      // Start the service if it's not already running
      final isRunning = await service.isRunning();
      if (!isRunning) {
        final started = await service.startService();
        if (!started) {
          throw Exception('Failed to start background service');
        }
        // Give the service a moment to initialize
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Send command to the service with the settings
      service.invoke('startRecording', {
        'isAutoStopEnabled': settings['enabled'] as bool,
        'minutes': settings['minutes'] as int,
      });

      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
        _isAutoStopEnabled = settings['enabled'] as bool;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting recording: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Recording?'),
        content: const Text('Are you sure you want to stop the recording?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Stop'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      service.invoke('stopRecording');
      // The 'recordingStopped' listener will handle the state change and navigation
    }
  }

  Future<void> _importRecording() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TranscriptionScreen(audioPath: path),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 0) seconds = 0;
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _getAutoStopRemainingTime() {
    if (!_isAutoStopEnabled || _remainingSeconds == null || !_isRecording) {
      return '';
    }
    return 'Stops in: ${_formatDuration(_remainingSeconds!)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Recorder'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isRecording) ...[
                  // Recording duration display
                  Text(
                    _formatDuration(_recordingDuration),
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Auto-stop toggle
                  Card(
                    child: SwitchListTile(
                      title: const Text('Auto-stop recording'),
                      subtitle: _isAutoStopEnabled
                          ? Text(_getAutoStopRemainingTime())
                          : null,
                      value: _isAutoStopEnabled,
                      onChanged: (bool value) async {
                        if (value) {
                          final duration = await _showSetDurationDialog();
                          if (duration != null) {
                            service.invoke('toggleAutoStop', {
                              'enabled': true,
                              'minutes': duration,
                            });
                            setState(() => _isAutoStopEnabled = true);
                          }
                        } else {
                          service.invoke('toggleAutoStop', {'enabled': false});
                          setState(() => _isAutoStopEnabled = false);
                        }
                      },
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Extension button (shows in last 10 seconds)
                  if (_shouldShowExtensionButton)
                    ElevatedButton.icon(
                      onPressed: () {
                        service.invoke('extendRecording');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Extended by 5 minutes'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_alarm),
                      label: const Text('Extend 5 minutes'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),

                  const SizedBox(height: 40),
                ],

                // Main recording button
                GestureDetector(
                  onTap: _isRecording ? _stopRecording : _startRecording,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording ? Colors.red : Colors.deepPurple,
                      boxShadow: [
                        BoxShadow(
                          color: (_isRecording ? Colors.red : Colors.deepPurple)
                              .withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  _isRecording ? 'Tap to stop' : 'Tap to start recording',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 40),

                // Import button (only when not recording)
                if (!_isRecording)
                  ElevatedButton.icon(
                    onPressed: _importRecording,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import Recording'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // DIALOGS

  Future<Map<String, dynamic>?> _showAutoStopDialog() {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AutoStopDialog(),
    );
  }

  Future<int?> _showSetDurationDialog() {
    return showDialog<int>(
      context: context,
      builder: (context) {
        double selectedMinutes = 10;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Auto-stop in...'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${selectedMinutes.toInt()} minutes',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 20),
                  Slider(
                    value: selectedMinutes,
                    min: 5,
                    max: 60,
                    divisions: 11,
                    label: '${selectedMinutes.toInt()} min',
                    onChanged: (value) => setState(() => selectedMinutes = value),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, selectedMinutes.toInt()),
                  child: const Text('Set'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// Auto-stop dialog widget
class _AutoStopDialog extends StatefulWidget {
  @override
  State<_AutoStopDialog> createState() => _AutoStopDialogState();
}

class _AutoStopDialogState extends State<_AutoStopDialog> {
  double _selectedMinutes = 10;
  bool _isAutoStopEnabled = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recording settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            title: const Text('Enable auto-stop'),
            value: _isAutoStopEnabled,
            onChanged: (bool value) => setState(() => _isAutoStopEnabled = value),
          ),
          if (_isAutoStopEnabled) ...[
            const SizedBox(height: 20),
            Text(
              '${_selectedMinutes.toInt()} minutes',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Slider(
              value: _selectedMinutes,
              min: 5,
              max: 60,
              divisions: 11,
              label: '${_selectedMinutes.toInt()} min',
              onChanged: (value) => setState(() => _selectedMinutes = value),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, {
            'minutes': _selectedMinutes.toInt(),
            'enabled': _isAutoStopEnabled,
          }),
          child: const Text('Start Recording'),
        ),
      ],
    );
  }
}