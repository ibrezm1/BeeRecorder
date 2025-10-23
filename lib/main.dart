

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:typed_data';

void main() {
  runApp(const VoiceTranscribeApp());
}

// Settings Helper
class SettingsHelper {
  static const String _apiKeyKey = 'gemini_api_key';
  static const String _modelKey = 'gemini_model'; // NEW

  static Future<void> saveApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, apiKey);
  }

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey);
  }

  static Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyKey);
  }

  static Future<void> saveModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modelKey, model);
  }

  static Future<String?> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_modelKey);
  }

  static Future<void> clearModel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_modelKey);
  }

}

class VoiceTranscribeApp extends StatelessWidget {
  const VoiceTranscribeApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Transcribe & Chat',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// Database Helper
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('recordings.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = '$dbPath/$filePath';

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE recordings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        filePath TEXT NOT NULL,
        transcription TEXT,
        dateCreated TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recordingId INTEGER NOT NULL,
        message TEXT NOT NULL,
        isUser INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (recordingId) REFERENCES recordings (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<int> insertRecording(Map<String, dynamic> recording) async {
    final db = await database;
    return await db.insert('recordings', recording);
  }

  Future<List<Map<String, dynamic>>> getAllRecordings() async {
    final db = await database;
    return await db.query('recordings', orderBy: 'dateCreated DESC');
  }

  Future<int> updateRecording(int id, Map<String, dynamic> recording) async {
    final db = await database;
    return await db.update(
      'recordings',
      recording,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteRecording(int id) async {
    final db = await database;
    await db.delete('chat_messages', where: 'recordingId = ?', whereArgs: [id]);
    return await db.delete('recordings', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertChatMessage(Map<String, dynamic> message) async {
    final db = await database;
    return await db.insert('chat_messages', message);
  }

  Future<List<Map<String, dynamic>>> getChatMessages(int recordingId) async {
    final db = await database;
    return await db.query(
      'chat_messages',
      where: 'recordingId = ?',
      whereArgs: [recordingId],
      orderBy: 'timestamp ASC',
    );
  }
}

// Models
class Recording {
  final int? id;
  final String title;
  final String filePath;
  final String? transcription;
  final DateTime dateCreated;

  Recording({
    this.id,
    required this.title,
    required this.filePath,
    this.transcription,
    required this.dateCreated,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'filePath': filePath,
      'transcription': transcription,
      'dateCreated': dateCreated.toIso8601String(),
    };
  }

  factory Recording.fromMap(Map<String, dynamic> map) {
    return Recording(
      id: map['id'],
      title: map['title'],
      filePath: map['filePath'],
      transcription: map['transcription'],
      dateCreated: DateTime.parse(map['dateCreated']),
    );
  }
}

class ChatMessage {
  final int? id;
  final int recordingId;
  final String message;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    this.id,
    required this.recordingId,
    required this.message,
    required this.isUser,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recordingId': recordingId,
      'message': message,
      'isUser': isUser ? 1 : 0,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'],
      recordingId: map['recordingId'],
      message: map['message'],
      isUser: map['isUser'] == 1,
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}

// Home Page
class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Recording> _recordings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    setState(() => _isLoading = true);
    final recordings = await DatabaseHelper.instance.getAllRecordings();
    setState(() {
      _recordings = recordings.map((r) => Recording.fromMap(r)).toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Recordings'),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _recordings.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic_none, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No recordings yet',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to start recording',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _recordings.length,
        itemBuilder: (context, index) {
          final recording = _recordings[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.deepPurple[100],
                child: Icon(
                  recording.transcription != null
                      ? Icons.check_circle
                      : Icons.mic,
                  color: Colors.deepPurple,
                ),
              ),
              title: Text(recording.title),
              subtitle: Text(
                DateFormat('MMM dd, yyyy - hh:mm a')
                    .format(recording.dateCreated),
              ),
              trailing: PopupMenuButton(
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20),
                        SizedBox(width: 8),
                        Text('Delete'),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) async {
                  if (value == 'delete') {
                    await DatabaseHelper.instance
                        .deleteRecording(recording.id!);
                    _loadRecordings();
                  }
                },
              ),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        RecordingDetailPage(recording: recording),
                  ),
                );
                _loadRecordings();
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RecordPage()),
          );
          _loadRecordings();
        },
        icon: const Icon(Icons.mic),
        label: const Text('Record'),
      ),
    );
  }
}

// Auto Stop Dialog
class AutoStopDialog extends StatefulWidget {
  const AutoStopDialog({Key? key}) : super(key: key);

  @override
  State<AutoStopDialog> createState() => _AutoStopDialogState();
}

class _AutoStopDialogState extends State<AutoStopDialog> {
  bool _autoStopEnabled = false;
  int _hours = 0;
  int _minutes = 5;
  int _seconds = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Auto-Stop Timer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            title: const Text('Enable Auto-Stop'),
            subtitle: const Text('Automatically stop recording after set time'),
            value: _autoStopEnabled,
            onChanged: (value) {
              setState(() => _autoStopEnabled = value);
            },
          ),
          if (_autoStopEnabled) ...[
            const SizedBox(height: 16),
            const Text(
              'Set Duration',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTimePicker(
                  label: 'Hours',
                  value: _hours,
                  max: 23,
                  onChanged: (value) => setState(() => _hours = value),
                ),
                _buildTimePicker(
                  label: 'Minutes',
                  value: _minutes,
                  max: 59,
                  onChanged: (value) => setState(() => _minutes = value),
                ),
                _buildTimePicker(
                  label: 'Seconds',
                  value: _seconds,
                  max: 59,
                  onChanged: (value) => setState(() => _seconds = value),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_hours == 0 && _minutes == 0 && _seconds == 0)
              const Text(
                'Please set a duration',
                style: TextStyle(color: Colors.red, fontSize: 12),
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
          onPressed: () {
            if (_autoStopEnabled &&
                _hours == 0 &&
                _minutes == 0 &&
                _seconds == 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please set a valid duration'),
                  duration: Duration(seconds: 2),
                ),
              );
              return;
            }

            final duration = _autoStopEnabled
                ? Duration(
              hours: _hours,
              minutes: _minutes,
              seconds: _seconds,
            )
                : null;

            Navigator.pop(context, {
              'enabled': _autoStopEnabled,
              'duration': duration,
            });
          },
          child: const Text('Start Recording'),
        ),
      ],
    );
  }

  Widget _buildTimePicker({
    required String label,
    required int value,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                onPressed: () {
                  if (value < max) onChanged(value + 1);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 30,
                ),
              ),
              Container(
                width: 40,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  value.toString().padLeft(2, '0'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                onPressed: () {
                  if (value > 0) onChanged(value - 1);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 30,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Record Page
class RecordPage extends StatefulWidget {
  const RecordPage({Key? key}) : super(key: key);

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isPaused = false;
  String? _recordingPath;
  Duration _duration = Duration.zero;
  Duration? _autoStopDuration;
  bool _autoStopEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required')),
      );
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        // Show auto-stop dialog first
        final shouldStart = await _showAutoStopDialog();
        if (!shouldStart) return;

        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _recorder.start(const RecordConfig(), path: path);

        setState(() {
          _isRecording = true;
          _recordingPath = path;
          _duration = Duration.zero;
        });

        // Update duration
        _updateDuration();
      }
    } catch (e) {
      print('Error starting recording: $e');
    }
  }

  Future<bool> _showAutoStopDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const AutoStopDialog(),
    );

    if (result == null) return false;

    setState(() {
      _autoStopEnabled = result['enabled'] as bool;
      _autoStopDuration = result['duration'] as Duration?;
    });

    return true;
  }

  void _updateDuration() {
    if (_isRecording && !_isPaused) {
      Future.delayed(const Duration(seconds: 1), () {
        if (_isRecording) {
          setState(() => _duration += const Duration(seconds: 1));

          // Check if auto-stop duration is reached
          if (_autoStopEnabled &&
              _autoStopDuration != null &&
              _duration >= _autoStopDuration!) {
            _stopRecording();
            return;
          }

          _updateDuration();
        }
      });
    }
  }

  Future<void> _pauseRecording() async {
    await _recorder.pause();
    setState(() => _isPaused = true);
  }

  Future<void> _resumeRecording() async {
    await _recorder.resume();
    setState(() => _isPaused = false);
    _updateDuration();
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    setState(() => _isRecording = false);

    if (path != null) {
      _showSaveDialog(path);
    }
  }

  void _showSaveDialog(String path) {
    final controller = TextEditingController(
      text: 'Recording ${DateFormat('MMM dd, hh:mm a').format(DateTime.now())}',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Recording'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Recording Title',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              File(path).deleteSync();
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Discard'),
          ),
          ElevatedButton(
            onPressed: () async {
              final recording = Recording(
                title: controller.text,
                filePath: path,
                dateCreated: DateTime.now(),
              );

              final id = await DatabaseHelper.instance.insertRecording(recording.toMap());
              Navigator.pop(context);

              // Navigate to transcription page
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => TranscriptionPage(
                    recording: recording.copyWith(id: id),
                  ),
                ),
              );
            },
            child: const Text('Save & Transcribe'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours != '00' ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Audio'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording
                    ? Colors.red.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.1),
              ),
              child: Center(
                child: Icon(
                  _isRecording ? Icons.mic : Icons.mic_none,
                  size: 80,
                  color: _isRecording ? Colors.red : Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              _formatDuration(_duration),
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
            ),
            if (_autoStopEnabled && _autoStopDuration != null && _isRecording)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Auto-stop in ${_formatDuration(_autoStopDuration! - _duration)}',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.orange[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const SizedBox(height: 48),
            if (!_isRecording)
              ElevatedButton.icon(
                onPressed: _startRecording,
                icon: const Icon(Icons.fiber_manual_record),
                label: const Text('Start Recording'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isPaused ? _resumeRecording : _pauseRecording,
                    icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(_isPaused ? 'Resume' : 'Pause'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _stopRecording,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// Transcription Page
class TranscriptionPage extends StatefulWidget {
  final Recording recording;

  const TranscriptionPage({Key? key, required this.recording}) : super(key: key);

  @override
  State<TranscriptionPage> createState() => _TranscriptionPageState();
}

class _TranscriptionPageState extends State<TranscriptionPage> {
  bool _isTranscribing = true;
  String? _transcription;
  String? _error;

  @override
  void initState() {
    super.initState();
    _transcribeAudio();
  }

  Future<void> _transcribeAudio() async {
    try {
      // Get API key from settings
      final apiKey = await SettingsHelper.getApiKey();

      if (apiKey == null || apiKey.isEmpty) {
        setState(() {
          _error = 'Please add your Gemini API key in Settings';
          _isTranscribing = false;
        });
        return;
      }

      final model = GenerativeModel(
        model: 'gemini-2.5-flash-lite',
        apiKey: apiKey,
      );

      // Read audio file
      final file = File(widget.recording.filePath);
      final audioBytes = await file.readAsBytes();

      // Create prompt for transcription
      final prompt = TextPart(
        'Please transcribe the following audio file accurately. '
            'Provide only the transcription without any additional commentary.',
      );

      final audioPart = DataPart('audio/m4a', audioBytes);

      final response = await model.generateContent([
        Content.multi([prompt, audioPart])
      ]);

      final transcription = response.text ?? 'No transcription available';

      // Update database
      await DatabaseHelper.instance.updateRecording(
        widget.recording.id!,
        {'transcription': transcription},
      );

      setState(() {
        _transcription = transcription;
        _isTranscribing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Transcription failed: $e';
        _isTranscribing = false;
      });
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
            SizedBox(height: 16),
            Text('Transcribing audio...'),
          ],
        ),
      )
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Transcription Complete!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_transcription ?? ''),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RecordingDetailPage(
                        recording: widget.recording.copyWith(
                          transcription: _transcription,
                        ),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.chat),
                label: const Text('Start Chatting'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Recording Detail Page with Chat
class RecordingDetailPage extends StatefulWidget {
  final Recording recording;

  const RecordingDetailPage({Key? key, required this.recording}) : super(key: key);

  @override
  State<RecordingDetailPage> createState() => _RecordingDetailPageState();
}

class _RecordingDetailPageState extends State<RecordingDetailPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() => _isPlaying = state == PlayerState.playing);
    });
  }

  Future<void> _loadChatHistory() async {
    final messages = await DatabaseHelper.instance.getChatMessages(widget.recording.id!);
    setState(() {
      _messages = messages.map((m) => ChatMessage.fromMap(m)).toList();
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    final userMessage = ChatMessage(
      recordingId: widget.recording.id!,
      message: message,
      isUser: true,
      timestamp: DateTime.now(),
    );

    await DatabaseHelper.instance.insertChatMessage(userMessage.toMap());
    _messageController.clear();
    setState(() => _messages.add(userMessage));
    _scrollToBottom();

    // Get AI response
    await _getAIResponse(message);
  }

  Future<void> _getAIResponse(String userMessage) async {
    setState(() => _isLoading = true);

    try {
      final apiKey = await SettingsHelper.getApiKey();

      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Please add your Gemini API key in Settings');
      }

      final model = GenerativeModel(
        model: 'gemini-2.5-flash-lite',
        apiKey: apiKey,
      );

      final context = '''
You are a helpful assistant discussing a transcribed audio recording.

Transcription:
${widget.recording.transcription}

Please answer the user's question based on this transcription. If the question cannot be answered from the transcription, politely explain that.
''';

      final response = await model.generateContent([
        Content.text('$context\n\nUser question: $userMessage')
      ]);

      final aiMessage = ChatMessage(
        recordingId: widget.recording.id!,
        message: response.text ?? 'I couldn\'t generate a response.',
        isUser: false,
        timestamp: DateTime.now(),
      );

      await DatabaseHelper.instance.insertChatMessage(aiMessage.toMap());
      setState(() {
        _messages.add(aiMessage);
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _playAudio() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(DeviceFileSource(widget.recording.filePath));
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recording.title),
        actions: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: _playAudio,
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.recording.transcription != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.grey[100],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.text_snippet, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Transcription',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Full Transcription'),
                              content: SingleChildScrollView(
                                child: Text(widget.recording.transcription!),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('View Full'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.recording.transcription!.length > 150
                        ? '${widget.recording.transcription!.substring(0, 150)}...'
                        : widget.recording.transcription!,
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Start a conversation',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ask questions about the recording',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message.isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.7,
                    ),
                    decoration: BoxDecoration(
                      color: message.isUser
                          ? Colors.deepPurple
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      message.message,
                      style: TextStyle(
                        color: message.isUser ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Ask about the recording...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send),
                  color: Colors.deepPurple,
                  iconSize: 28,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Extension to copy Recording with new values
extension RecordingCopyWith on Recording {
  Recording copyWith({
    int? id,
    String? title,
    String? filePath,
    String? transcription,
    DateTime? dateCreated,
  }) {
    return Recording(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      transcription: transcription ?? this.transcription,
      dateCreated: dateCreated ?? this.dateCreated,
    );
  }
}

// Settings Page
class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  bool _isLoading = true;
  bool _obscureText = true;
  bool _hasApiKey = false;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    setState(() => _isLoading = true);
    final apiKey = await SettingsHelper.getApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      _apiKeyController.text = apiKey;
      _hasApiKey = true;
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveApiKey() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an API key')),
      );
      return;
    }

    await SettingsHelper.saveApiKey(apiKey);
    setState(() => _hasApiKey = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('API key saved successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _clearApiKey() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear API Key'),
        content: const Text('Are you sure you want to clear the API key?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SettingsHelper.clearApiKey();
      _apiKeyController.clear();
      setState(() => _hasApiKey = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API key cleared')),
        );
      }
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gemini API Configuration',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your Google Gemini API key to enable transcription and chat features.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureText,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: 'Enter your Gemini API key',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureText ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() => _obscureText = !_obscureText);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saveApiKey,
                    icon: const Icon(Icons.save),
                    label: const Text('Save API Key'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                if (_hasApiKey) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _clearApiKey,
                    icon: const Icon(Icons.delete),
                    label: const Text('Clear'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'How to get an API key',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('1. Visit https://makersuite.google.com/app/apikey'),
                    const SizedBox(height: 4),
                    const Text('2. Sign in with your Google account'),
                    const SizedBox(height: 4),
                    const Text('3. Click "Create API Key"'),
                    const SizedBox(height: 4),
                    const Text('4. Copy and paste the key above'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.security, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Security Note',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your API key is stored securely on your device and is never shared. '
                          'Keep your API key private and do not share it with others.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}