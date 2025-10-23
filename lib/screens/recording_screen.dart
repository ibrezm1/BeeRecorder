import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import '../utils/database_helper.dart';
import '../utils/gemini_service.dart';
import 'transcription_screen.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;
  int _recordingDuration = 0;
  Timer? _timer;

  // New state variables for improved timer logic
  bool _isAutoStopEnabled = true;
  DateTime? _autoStopTargetTime;
  bool _shouldShowExtensionButton = false;

  @override
  void dispose() {
    _recorder.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }

    final settings = await _showAutoStopDialog();
    if (settings == null) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordingPath = '${dir.path}/recording_$timestamp.m4a';

      await _recorder.start(const RecordConfig(), path: _recordingPath!);

      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
        _shouldShowExtensionButton = false;
        _isAutoStopEnabled = settings['enabled'];

        if (_isAutoStopEnabled) {
          final minutes = settings['minutes'] as int;
          _autoStopTargetTime = DateTime.now().add(Duration(minutes: minutes));
        } else {
          _autoStopTargetTime = null;
        }
      });

      _startUniversalTimer();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting recording: $e')),
        );
      }
    }
  }

  void _startUniversalTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }

      setState(() {
        _recordingDuration++;

        if (_isAutoStopEnabled && _autoStopTargetTime != null) {
          final remaining = _autoStopTargetTime!.difference(DateTime.now());

          if (remaining.inSeconds <= 0) {
            _stopRecording();
            return;
          }
          // Show the extend button in the last 10 seconds
          _shouldShowExtensionButton = remaining.inSeconds <= 10;
        } else {
          // Ensure the button is hidden if auto-stop is disabled
          _shouldShowExtensionButton = false;
        }
      });
    });
  }

  Future<Map<String, dynamic>?> _showAutoStopDialog() async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AutoStopDialog(),
    );
  }

  Future<int?> _showSetDurationDialog() async {
    return showDialog<int>(
      context: context,
      builder: (context) {
        double selectedMinutes = 5;
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
                  Slider(
                    value: selectedMinutes,
                    min: 5,
                    max: 20,
                    divisions: 3,
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

  void _extendRecording() {
    if (_autoStopTargetTime == null) return;
    setState(() {
      _autoStopTargetTime = _autoStopTargetTime!.add(const Duration(minutes: 5));
      _shouldShowExtensionButton = false;
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return; // Prevent multiple calls
    try {
      final path = await _recorder.stop();
      _timer?.cancel();

      setState(() {
        _isRecording = false;
        _shouldShowExtensionButton = false;
      });

      if (path != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TranscriptionScreen(audioPath: path),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping recording: $e')),
        );
      }
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
          SnackBar(content: Text('Error importing file: $e')),
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
    if (!_isAutoStopEnabled || _autoStopTargetTime == null || !_isRecording) {
      return '';
    }
    final remaining = _autoStopTargetTime!.difference(DateTime.now());
    return 'Stops in: ${_formatDuration(remaining.inSeconds)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Recorder'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isRecording) ...[
              Text(
                _formatDuration(_recordingDuration),
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                title: const Text('Auto-stop recording'),
                value: _isAutoStopEnabled,
                onChanged: (bool value) async {
                  if (value) {
                    final duration = await _showSetDurationDialog();
                    if (duration != null) {
                      setState(() {
                        _isAutoStopEnabled = true;
                        _autoStopTargetTime = DateTime.now().add(Duration(minutes: duration));
                      });
                    }
                  } else {
                    setState(() {
                      _isAutoStopEnabled = false;
                      _autoStopTargetTime = null;
                      _shouldShowExtensionButton = false;
                    });
                  }
                },
              ),
              if (_isAutoStopEnabled)
                Text(
                  _getAutoStopRemainingTime(),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              const SizedBox(height: 40),
              if (_shouldShowExtensionButton)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: ElevatedButton.icon(
                    onPressed: _extendRecording,
                    icon: const Icon(Icons.add_alarm),
                    label: const Text('Extend 5 minutes'),
                  ),
                ),
            ],
            GestureDetector(
              onTap: _isRecording ? _stopRecording : _startRecording,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording ? Colors.red : Colors.deepPurple,
                  boxShadow: [
                    BoxShadow(
                      color: (_isRecording ? Colors.red : Colors.deepPurple).withOpacity(0.3),
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
            const SizedBox(height: 40),
            if (!_isRecording)
              ElevatedButton.icon(
                onPressed: _importRecording,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import Recording'),
              ),
          ],
        ),
      ),
    );
  }
}


class _AutoStopDialog extends StatefulWidget {
  @override
  State<_AutoStopDialog> createState() => _AutoStopDialogState();
}

class _AutoStopDialogState extends State<_AutoStopDialog> {
  double _selectedMinutes = 5;
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
            Text(
              '${_selectedMinutes.toInt()} minutes',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Slider(
              value: _selectedMinutes,
              min: 5,
              max: 20,
              divisions: 3,
              label: '${_selectedMinutes.toInt()} min',
              onChanged: (value) => setState(() => _selectedMinutes = value),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
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