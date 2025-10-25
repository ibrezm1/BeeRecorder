// utils/database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('voice_recordings.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE recordings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        audioPath TEXT NOT NULL,
        transcription TEXT,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recordingId INTEGER NOT NULL,
        content TEXT NOT NULL,
        isUser INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (recordingId) REFERENCES recordings (id) ON DELETE CASCADE
      )
    ''');
  }

  // ============================================================================
  // RECORDING OPERATIONS
  // ============================================================================

  /// Insert a new recording into the database
  Future<int> insertRecording(Map<String, dynamic> recording) async {
    final db = await database;
    return await db.insert('recordings', recording);
  }

  /// Get a single recording by ID
  Future<Map<String, dynamic>?> getRecording(int id) async {
    final db = await database;
    final results = await db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get all recordings ordered by creation date (newest first)
  Future<List<Map<String, dynamic>>> getAllRecordings() async {
    final db = await database;
    return await db.query('recordings', orderBy: 'createdAt DESC');
  }

  /// Update an existing recording
  Future<int> updateRecording(int id, Map<String, dynamic> recording) async {
    final db = await database;
    return await db.update(
      'recordings',
      recording,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Update only the transcription field of a recording
  Future<int> updateTranscription(int id, String transcription) async {
    final db = await database;
    return await db.update(
      'recordings',
      {'transcription': transcription},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Update only the name field of a recording
  Future<int> updateRecordingName(int id, String name) async {
    final db = await database;
    return await db.update(
      'recordings',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete a recording and all associated messages
  Future<int> deleteRecording(int id) async {
    final db = await database;
    // Delete associated messages first
    await db.delete('messages', where: 'recordingId = ?', whereArgs: [id]);
    // Delete the recording
    return await db.delete('recordings', where: 'id = ?', whereArgs: [id]);
  }

  /// Search recordings by name or transcription
  Future<List<Map<String, dynamic>>> searchRecordings(String query) async {
    final db = await database;
    return await db.query(
      'recordings',
      where: 'name LIKE ? OR transcription LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'createdAt DESC',
    );
  }

  /// Get recordings within a date range
  Future<List<Map<String, dynamic>>> getRecordingsByDateRange(
      String startDate,
      String endDate,
      ) async {
    final db = await database;
    return await db.query(
      'recordings',
      where: 'createdAt BETWEEN ? AND ?',
      whereArgs: [startDate, endDate],
      orderBy: 'createdAt DESC',
    );
  }

  /// Count total recordings
  Future<int> getRecordingsCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM recordings');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ============================================================================
  // MESSAGE OPERATIONS
  // ============================================================================

  /// Insert a new message
  Future<int> insertMessage(Map<String, dynamic> message) async {
    final db = await database;
    return await db.insert('messages', message);
  }

  /// Get all messages for a specific recording
  Future<List<Map<String, dynamic>>> getMessages(int recordingId) async {
    final db = await database;
    return await db.query(
      'messages',
      where: 'recordingId = ?',
      whereArgs: [recordingId],
      orderBy: 'timestamp ASC',
    );
  }

  /// Update a message
  Future<int> updateMessage(int id, Map<String, dynamic> message) async {
    final db = await database;
    return await db.update(
      'messages',
      message,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete a specific message
  Future<int> deleteMessage(int id) async {
    final db = await database;
    return await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  /// Delete all messages for a specific recording
  Future<int> deleteMessagesForRecording(int recordingId) async {
    final db = await database;
    return await db.delete(
      'messages',
      where: 'recordingId = ?',
      whereArgs: [recordingId],
    );
  }

  /// Count messages for a specific recording
  Future<int> getMessagesCount(int recordingId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE recordingId = ?',
      [recordingId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get the last message for a recording
  Future<Map<String, dynamic>?> getLastMessage(int recordingId) async {
    final db = await database;
    final results = await db.query(
      'messages',
      where: 'recordingId = ?',
      whereArgs: [recordingId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  // ============================================================================
  // BATCH OPERATIONS
  // ============================================================================

  /// Insert multiple messages in a batch
  Future<void> insertMessagesBatch(List<Map<String, dynamic>> messages) async {
    final db = await database;
    final batch = db.batch();
    for (var message in messages) {
      batch.insert('messages', message);
    }
    await batch.commit(noResult: true);
  }

  /// Delete multiple recordings in a batch
  Future<void> deleteRecordingsBatch(List<int> ids) async {
    final db = await database;
    final batch = db.batch();
    for (var id in ids) {
      // Delete messages first
      batch.delete('messages', where: 'recordingId = ?', whereArgs: [id]);
      // Delete recording
      batch.delete('recordings', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  // ============================================================================
  // UTILITY OPERATIONS
  // ============================================================================

  /// Clear all data from both tables (use with caution!)
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('recordings');
  }

  /// Export all data as a map (for backup purposes)
  Future<Map<String, dynamic>> exportData() async {
    final recordings = await getAllRecordings();
    final messages = <Map<String, dynamic>>[];

    for (var recording in recordings) {
      final recordingMessages = await getMessages(recording['id'] as int);
      messages.addAll(recordingMessages);
    }

    return {
      'recordings': recordings,
      'messages': messages,
      'exportDate': DateTime.now().toIso8601String(),
    };
  }

  /// Close the database connection
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  /// Reset database (delete and recreate)
  Future<void> resetDatabase() async {
    await close();
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'voice_recordings.db');
    await deleteDatabase(path);
    _database = null;
  }

  /// Check if database is accessible and working
  Future<bool> isDatabaseAccessible() async {
    try {
      final db = await database;
      await db.rawQuery('SELECT 1');
      return true;
    } catch (e) {
      return false;
    }
  }
}