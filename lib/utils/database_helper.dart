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

  Future<int> insertRecording(Map<String, dynamic> recording) async {
    final db = await database;
    return await db.insert('recordings', recording);
  }

  Future<Map<String, dynamic>?> getRecording(int id) async {
    final db = await database;
    final results = await db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllRecordings() async {
    final db = await database;
    return await db.query('recordings', orderBy: 'createdAt DESC');
  }

  Future<int> deleteRecording(int id) async {
    final db = await database;
    await db.delete('messages', where: 'recordingId = ?', whereArgs: [id]);
    return await db.delete('recordings', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertMessage(Map<String, dynamic> message) async {
    final db = await database;
    return await db.insert('messages', message);
  }

  Future<List<Map<String, dynamic>>> getMessages(int recordingId) async {
    final db = await database;
    return await db.query(
      'messages',
      where: 'recordingId = ?',
      whereArgs: [recordingId],
      orderBy: 'timestamp ASC',
    );
  }
}
