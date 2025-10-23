import 'package:flutter/material.dart';
import 'dart:io';
import '../utils/gemini_service.dart';
import '../utils/database_helper.dart';
import 'chat_screen.dart';

class TranscriptionScreen extends StatefulWidget {
  final String audioPath;

  const TranscriptionScreen({super.key, required this.audioPath});

  @override
  State<TranscriptionScreen> createState() => _TranscriptionScreenState();
}

class _TranscriptionScreenState extends State<TranscriptionScreen> {
  bool _isTranscribing = false;
  String? _transcription;
  String? _error;
  final _nameController = TextEditingController();
  bool _isGeneratingTitle = false;

  @override
  void initState() {
    super.initState();
    _transcribe();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _transcribe() async {
    setState(() {
      _isTranscribing = true;
      _error = null;
    });

    try {
      final gemini = GeminiService();
      final transcription = await gemini.transcribeAudio(widget.audioPath);

      setState(() {
        _transcription = transcription;
        _isTranscribing = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isTranscribing = false;
      });
    }
  }

  Future<void> _generateTitle() async {
    if (_transcription == null) return;

    setState(() {
      _isGeneratingTitle = true;
    });

    try {
      final gemini = GeminiService();
      final title = await gemini.generateTitle(_transcription!);

      setState(() {
        _nameController.text = title;
        _isGeneratingTitle = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating title: $e')),
        );
      }
      setState(() {
        _isGeneratingTitle = false;
      });
    }
  }

  Future<void> _saveRecording() async {
    final name = _nameController.text.trim().isEmpty
        ? 'Recording ${DateTime.now().toString().split('.')[0]}'
        : _nameController.text.trim();

    try {
      final id = await DatabaseHelper.instance.insertRecording({
        'name': name,
        'audioPath': widget.audioPath,
        'transcription': _transcription ?? '',
        'createdAt': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(recordingId: id),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving recording: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcription'),
      ),
      body: _isTranscribing
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Transcribing audio...'),
          ],
        ),
      )
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 60, color: Colors.red),
              const SizedBox(height: 20),
              Text(
                'Error: $_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _transcribe,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transcription',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(_transcription ?? 'No transcription available'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Recording Name',
                hintText: 'Leave empty for default name',
                border: const OutlineInputBorder(),
                suffixIcon: _isGeneratingTitle
                    ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                    : IconButton(
                  icon: const Icon(Icons.auto_awesome),
                  onPressed: _generateTitle,
                  tooltip: 'Generate title with AI',
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveRecording,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: const Text('Save & Start Chatting'),
            ),
          ],
        ),
      ),
    );
  }
}
