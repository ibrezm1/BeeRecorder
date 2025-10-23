// screens/chat_screen.dart
import 'package:flutter/material.dart';
import '../utils/database_helper.dart';
import '../utils/gemini_service.dart';

class ChatScreen extends StatefulWidget {
  final int recordingId;

  const ChatScreen({super.key, required this.recordingId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  String? _transcription;
  String? _recordingName;
  bool _isLoading = false;
  bool _showChips = true;

  final List<String> _defaultPrompts = [
    'Create a MOM',
    'Summarize key points',
    'List action items',
    'Extract dates and deadlines',
  ];

  @override
  void initState() {
    super.initState();
    _loadRecording();
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadRecording() async {
    final recording = await DatabaseHelper.instance.getRecording(widget.recordingId);
    if (recording != null) {
      setState(() {
        _transcription = recording['transcription'];
        _recordingName = recording['name'];
      });
    }
  }

  Future<void> _loadMessages() async {
    final messages = await DatabaseHelper.instance.getMessages(widget.recordingId);
    setState(() {
      _messages = messages;
      _showChips = messages.isEmpty;
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _transcription == null) return;

    setState(() {
      _showChips = false;
    });

    final userMessage = {
      'recordingId': widget.recordingId,
      'content': text,
      'isUser': 1,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await DatabaseHelper.instance.insertMessage(userMessage);
    await _loadMessages();
    _messageController.clear();

    setState(() {
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      final gemini = GeminiService();
      final response = await gemini.chatWithTranscription(
        _transcription!,
        text,
        _messages.where((m) => m['isUser'] == 0).map((m) => m['content'] as String).toList(),
      );

      final aiMessage = {
        'recordingId': widget.recordingId,
        'content': response,
        'isUser': 0,
        'timestamp': DateTime.now().toIso8601String(),
      };

      await DatabaseHelper.instance.insertMessage(aiMessage);
      await _loadMessages();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_recordingName ?? 'Chat'),
      ),
      body: Column(
        children: [
          if (_showChips && _messages.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _defaultPrompts.map((prompt) {
                  return ActionChip(
                    label: Text(prompt),
                    onPressed: () => _sendMessage(prompt),
                  );
                }).toList(),
              ),
            ),
          Expanded(
            child: _messages.isEmpty && !_showChips
                ? const Center(child: Text('Start chatting about your recording'))
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message['isUser'] == 1;

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.7,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      message['content'],
                      style: TextStyle(
                        color: isUser
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
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
                    decoration: const InputDecoration(
                      hintText: 'Ask about the recording...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: _sendMessage,
                    enabled: !_isLoading,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isLoading ? null : () => _sendMessage(_messageController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}