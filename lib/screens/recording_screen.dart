// screens/recording_screen.dart
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
  Timer? _autoStopTimer;
  int _autoStopMinutes = 5;
  bool _showTimeExtension = false;

  @override
  void dispose() {
    _recorder.dispose();
    _timer?.cancel();
    _autoStopTimer?.cancel();
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

    final minutes = await _showAutoStopDialog();
    if (minutes == null) return;

    setState(() {
      _autoStopMinutes = minutes;
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordingPath = '${dir.path}/recording_$timestamp.m4a';

      await _recorder.start(const RecordConfig(), path: _recordingPath!);

      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
        _showTimeExtension = false;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingDuration++;
        });
      });

      _autoStopTimer = Timer(Duration(minutes: _autoStopMinutes), () {
        setState(() {
          _showTimeExtension = true;
        });
        Future.delayed(const Duration(seconds: 10), () {
          if (_isRecording && !_showTimeExtension) {
            _stopRecording();
          }
        });
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting recording: $e')),
        );
      }
    }
  }

  Future<int?> _showAutoStopDialog() async {
    return showDialog<int>(
      context: context,
      builder: (context) => _AutoStopDialog(),
    );
  }

  void _extendRecording() {
    setState(() {
      _showTimeExtension = false;
      _autoStopMinutes += 5;
    });

    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(Duration(minutes: 5), () {
      setState(() {
        _showTimeExtension = true;
      });
    });
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recorder.stop();
      _timer?.cancel();
      _autoStopTimer?.cancel();

      setState(() {
        _isRecording = false;
        _showTimeExtension = false;
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
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
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
              Text(
                'Auto-stop in ${_autoStopMinutes} minutes',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 40),
              if (_showTimeExtension)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: ElevatedButton.icon(
                    onPressed: _extendRecording,
                    icon: const Icon(Icons.add_alarm),
                    label: const Text('Extend 5 minutes'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 15,
                      ),
                    ),
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
            const SizedBox(height: 40),
            if (!_isRecording)
              ElevatedButton.icon(
                onPressed: _importRecording,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import Recording'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 15,
                  ),
                ),
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Auto-stop recording after'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
            onChanged: (value) {
              setState(() {
                _selectedMinutes = value;
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selectedMinutes.toInt()),
          child: const Text('Start Recording'),
        ),
      ],
    );
  }
}
