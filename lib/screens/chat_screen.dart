import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for clipboard services
import 'package:flutter_markdown/flutter_markdown.dart';
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
  bool _showTranscription = false; // State to toggle transcription view

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

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_recordingName ?? 'Chat'),
        actions: [
          IconButton(
            icon: Icon(
              _showTranscription ? Icons.visibility_off : Icons.visibility,
            ),
            onPressed: () {
              setState(() {
                _showTranscription = !_showTranscription;
              });
            },
            tooltip: 'Show Transcription',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showTranscription)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(16),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4, // Adjusted height for button
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Original Transcription',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _showTranscription = false;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(_transcription ?? 'No transcription available.'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // MODIFICATION: Added a copy button below the transcription text
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                      onPressed: _transcription != null && _transcription!.isNotEmpty
                          ? () => _copyToClipboard(_transcription!)
                          : null, // Disable button if there's no transcription
                    ),
                  ),
                ],
              ),
            ),
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
                final messageContent = message['content'] as String;

                final textStyle = TextStyle(
                  color: isUser
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSecondaryContainer,
                );

                final Widget messageWidget;
                if (isUser) {
                  messageWidget = SelectableText(messageContent, style: textStyle);
                } else {
                  messageWidget = MarkdownBody(
                    data: messageContent,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(p: textStyle),
                  );
                }

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        messageWidget,
                        Align(
                          alignment: Alignment.bottomRight,
                          child: IconButton(
                            icon: const Icon(Icons.copy),
                            iconSize: 18,
                            color: textStyle.color?.withOpacity(0.7),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.only(top: 8),
                            onPressed: () => _copyToClipboard(messageContent),
                          ),
                        ),
                      ],
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