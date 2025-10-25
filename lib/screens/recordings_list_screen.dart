import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import '../utils/database_helper.dart';
import 'chat_screen.dart';
import 'dart:async';
import 'dart:io';

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

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isLoading = true;
  String _sortBy = 'date'; // 'date', 'name', 'size'
  bool _sortAscending = false;

  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playerStateSubscription;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
    _searchController.addListener(_filterRecordings);
    _setupAudioPlayerListeners();
  }

  void _setupAudioPlayerListeners() {
    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed) {
        if (mounted) {
          setState(() {
            _playingId = null;
            _position = Duration.zero;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecordings() async {
    setState(() => _isLoading = true);

    try {
      print('Starting to load recordings...');

      // Check database accessibility first
      print('Checking database accessibility...');
      final isAccessible = await DatabaseHelper.instance.isDatabaseAccessible();
      print('Database accessible: $isAccessible');

      if (!isAccessible) {
        throw Exception('Database is not accessible. The database may be corrupted or have permission issues.');
      }

      print('Fetching recordings from database...');
      final recordings = await DatabaseHelper.instance.getAllRecordings();
      print('Found ${recordings.length} recordings in database');

      // Verify files exist and add file info
      final validRecordings = <Map<String, dynamic>>[];
      final invalidRecordingIds = <int>[];

      for (final recording in recordings) {
        final file = File(recording['audioPath']);
        final exists = await file.exists();
        print('Checking file: ${recording['audioPath']} - exists: $exists');

        if (exists) {
          // Add file size info
          final fileSize = await file.length();
          final mutableRecording = Map<String, dynamic>.from(recording);  // ✅ Create mutable copy
          mutableRecording['fileSize'] = fileSize;
          validRecordings.add(mutableRecording);
          validRecordings.add(recording);
        } else {
          // File doesn't exist, mark for cleanup
          print('Recording file not found: ${recording['audioPath']}');
          invalidRecordingIds.add(recording['id'] as int);
        }
      }

      // Clean up invalid recordings from database
      if (invalidRecordingIds.isNotEmpty) {
        print('Cleaning up ${invalidRecordingIds.length} invalid recordings...');
        for (final id in invalidRecordingIds) {
          await DatabaseHelper.instance.deleteRecording(id);
        }
        print('Cleanup complete');
      }

      if (mounted) {
        setState(() {
          _recordings = validRecordings;
          _filteredRecordings = validRecordings;
          _isLoading = false;
        });
        _sortRecordings();
      }

      print('Recordings loaded successfully');
    } catch (e, stackTrace) {
      print('Error loading recordings: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        setState(() => _isLoading = false);

        // Show error with option to reset database
        final shouldReset = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Database Error'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Error loading recordings:'),
                  const SizedBox(height: 8),
                  Text(
                    '$e',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Would you like to reset the database? This will delete all recordings metadata (but not the audio files).',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
                child: const Text('Reset Database'),
              ),
            ],
          ),
        );

        if (shouldReset == true) {
          await _resetDatabase();
        }
      }
    }
  }

  Future<void> _resetDatabase() async {
    try {
      await DatabaseHelper.instance.resetDatabase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Database reset successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadRecordings();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error resetting database: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterRecordings() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredRecordings = List.from(_recordings);
      } else {
        _filteredRecordings = _recordings.where((recording) {
          final name = recording['name'].toString().toLowerCase();
          final transcription = (recording['transcription'] ?? '').toString().toLowerCase();
          return name.contains(query) || transcription.contains(query);
        }).toList();
      }
    });
    _sortRecordings();
  }

  void _sortRecordings() {
    setState(() {
      _filteredRecordings.sort((a, b) {
        int comparison;
        switch (_sortBy) {
          case 'name':
            comparison = a['name'].toString().compareTo(b['name'].toString());
            break;
          case 'size':
            final sizeA = a['fileSize'] as int? ?? 0;
            final sizeB = b['fileSize'] as int? ?? 0;
            comparison = sizeA.compareTo(sizeB);
            break;
          case 'date':
          default:
            final dateA = DateTime.parse(a['createdAt']);
            final dateB = DateTime.parse(b['createdAt']);
            comparison = dateA.compareTo(dateB);
            break;
        }
        return _sortAscending ? comparison : -comparison;
      });
    });
  }

  void _changeSortOrder(String sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = sortBy;
        _sortAscending = false;
      }
    });
    _sortRecordings();
  }

  Future<void> _playRecording(int id, String path) async {
    try {
      if (_playingId == id) {
        // Stop if already playing this recording
        await _audioPlayer.stop();
        _durationSubscription?.cancel();
        _positionSubscription?.cancel();
        setState(() {
          _playingId = null;
          _duration = Duration.zero;
          _position = Duration.zero;
        });
      } else {
        // Stop any current playback
        if (_playingId != null) {
          await _audioPlayer.stop();
          _durationSubscription?.cancel();
          _positionSubscription?.cancel();
        }

        // Check if file exists
        final file = File(path);
        if (!await file.exists()) {
          throw Exception('Audio file not found at: $path');
        }

        // Start playing
        await _audioPlayer.play(DeviceFileSource(path));

        setState(() {
          _playingId = id;
          _duration = Duration.zero;
          _position = Duration.zero;
        });

        // Set up duration listener
        _durationSubscription = _audioPlayer.onDurationChanged.listen((newDuration) {
          if (mounted) {
            setState(() {
              _duration = newDuration;
            });
          }
        });

        // Set up position listener
        _positionSubscription = _audioPlayer.onPositionChanged.listen((newPosition) {
          if (mounted) {
            setState(() {
              _position = newPosition;
            });
          }
        });
      }
    } catch (e) {
      print('Error playing recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing audio: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
          _playingId = null;
        });
      }
    }
  }

  Future<void> _stopPlaying() async {
    await _audioPlayer.stop();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    setState(() {
      _playingId = null;
      _duration = Duration.zero;
      _position = Duration.zero;
    });
  }

  Future<void> _deleteRecording(int id, String audioPath) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recording'),
        content: const Text(
          'Are you sure you want to delete this recording? '
              'This will delete both the database entry and the audio file. '
              'This action cannot be undone.',
        ),
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
      try {
        // Stop playing if this recording is currently playing
        if (_playingId == id) {
          await _stopPlaying();
        }

        // Delete from database
        await DatabaseHelper.instance.deleteRecording(id);

        // Delete audio file
        final file = File(audioPath);
        if (await file.exists()) {
          await file.delete();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording deleted successfully'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }

        _loadRecordings();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting recording: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _renameRecording(int id, String currentName) async {
    final controller = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Recording'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Recording Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          maxLength: 100,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      try {
        await DatabaseHelper.instance.updateRecordingName(id, newName);
        _loadRecordings();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording renamed successfully'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error renaming recording: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    controller.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return [if (duration.inHours > 0) hours, minutes, seconds].join(':');
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recordings'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort by',
            onSelected: _changeSortOrder,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'date',
                child: Row(
                  children: [
                    Icon(
                      _sortBy == 'date'
                          ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                          : Icons.calendar_today,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Date'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'name',
                child: Row(
                  children: [
                    Icon(
                      _sortBy == 'name'
                          ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                          : Icons.sort_by_alpha,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Name'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'size',
                child: Row(
                  children: [
                    Icon(
                      _sortBy == 'size'
                          ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                          : Icons.data_usage,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Size'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecordings,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search recordings',
                hintText: 'Search by name or transcription',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
            ),
          ),

          // Recordings count and info
          if (!_isLoading && _recordings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_filteredRecordings.length} of ${_recordings.length} recording${_recordings.length != 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  if (_sortBy != 'date')
                    Text(
                      'Sorted by ${_sortBy}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            ),

          // Recordings list
          Expanded(
            child: _isLoading
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading recordings...'),
                ],
              ),
            )
                : _filteredRecordings.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _recordings.isEmpty ? Icons.mic_none : Icons.search_off,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _recordings.isEmpty
                        ? 'No recordings yet'
                        : 'No matching recordings',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  if (_recordings.isEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Start recording to see your files here',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: _loadRecordings,
              child: ListView.builder(
                itemCount: _filteredRecordings.length,
                padding: const EdgeInsets.only(bottom: 16),
                itemBuilder: (context, index) {
                  final recording = _filteredRecordings[index];
                  final id = recording['id'] as int;
                  final date = DateTime.parse(recording['createdAt']);
                  final isPlaying = _playingId == id;
                  final hasTranscription = recording['transcription'] != null &&
                      recording['transcription'].toString().isNotEmpty;

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    elevation: 2,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isPlaying ? Colors.red : Colors.deepPurple,
                            child: IconButton(
                              icon: Icon(
                                isPlaying ? Icons.stop : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              onPressed: () => _playRecording(id, recording['audioPath']),
                            ),
                          ),
                          title: Text(
                            recording['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(DateFormat.yMMMd().add_jm().format(date)),
                              if (recording['fileSize'] != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _formatFileSize(recording['fileSize']),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              switch (value) {
                                case 'rename':
                                  _renameRecording(id, recording['name']);
                                  break;
                                case 'delete':
                                  _deleteRecording(id, recording['audioPath']);
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'rename',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 20),
                                    SizedBox(width: 8),
                                    Text('Rename'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, size: 20, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Delete', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          onTap: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatScreen(recordingId: id),
                              ),
                            );
                            // Reload if chat screen returns true (meaning data was updated)
                            if (result == true && mounted) {
                              _loadRecordings();
                            }
                          },
                        ),

                        // Audio player controls
                        if (isPlaying) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _formatDuration(_position),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Expanded(
                                      child: Slider(
                                        min: 0,
                                        max: _duration.inSeconds.toDouble() > 0
                                            ? _duration.inSeconds.toDouble()
                                            : 1,
                                        value: _position.inSeconds.toDouble().clamp(
                                          0.0,
                                          _duration.inSeconds.toDouble() > 0
                                              ? _duration.inSeconds.toDouble()
                                              : 1,
                                        ),
                                        onChanged: (value) async {
                                          final position = Duration(seconds: value.toInt());
                                          await _audioPlayer.seek(position);
                                        },
                                      ),
                                    ),
                                    Text(
                                      _formatDuration(_duration),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Show transcription preview if available
                        if (hasTranscription && !isPlaying)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12.0),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              border: Border(
                                top: BorderSide(color: Colors.grey[300]!),
                              ),
                            ),
                            child: Text(
                              recording['transcription'].toString().length > 100
                                  ? '${recording['transcription'].toString().substring(0, 100)}...'
                                  : recording['transcription'].toString(),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}