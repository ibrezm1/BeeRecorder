import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import '../utils/database_helper.dart';
import 'chat_screen.dart';

class RecordingsListScreen extends StatefulWidget {
  const RecordingsListScreen({super.key});

  @override
  State<RecordingsListScreen> createState() => _RecordingsListScreenState();
}

class _RecordingsListScreenState extends State<RecordingsListScreen> {
  List<Map<String, dynamic>> _recordings = [];
  List<Map<String, dynamic>> _filteredRecordings = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  int? _playingId;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRecordings();
    _searchController.addListener(_filterRecordings);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecordings() async {
    final recordings = await DatabaseHelper.instance.getAllRecordings();
    setState(() {
      _recordings = recordings;
      _filteredRecordings = recordings;
    });
  }

  void _filterRecordings() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredRecordings = _recordings.where((recording) {
        final name = recording['name'].toString().toLowerCase();
        return name.contains(query);
      }).toList();
    });
  }

  Future<void> _playRecording(int id, String path) async {
    if (_playingId == id) {
      await _audioPlayer.stop();
      setState(() {
        _playingId = null;
      });
    } else {
      await _audioPlayer.play(DeviceFileSource(path));
      setState(() {
        _playingId = id;
      });
    }
  }

  Future<void> _deleteRecording(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recording'),
        content: const Text('Are you sure you want to delete this recording?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteRecording(id);
      _loadRecordings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recordings'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            ),
          ),
          Expanded(
            child: _filteredRecordings.isEmpty
                ? const Center(
              child: Text('No recordings yet'),
            )
                : ListView.builder(
              itemCount: _filteredRecordings.length,
              itemBuilder: (context, index) {
                final recording = _filteredRecordings[index];
                final id = recording['id'] as int;
                final date = DateTime.parse(recording['createdAt']);

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: IconButton(
                      icon: Icon(
                        _playingId == id ? Icons.stop : Icons.play_arrow,
                      ),
                      onPressed: () => _playRecording(id, recording['audioPath']),
                    ),
                    title: Text(recording['name']),
                    subtitle: Text(DateFormat.yMMMd().add_jm().format(date)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _deleteRecording(id),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(recordingId: id),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}