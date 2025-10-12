import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/sent_pqc_email.dart';

/// Local SQLite database helper for storing sent PQC emails
/// PQC private keys never leave the device, so we need local storage for sent messages
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  /// Get database instance (singleton pattern)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'qumail_local.db');

    print('[DatabaseHelper] Initializing database at: $path');

    return await openDatabase(
      path,
      version: 2, // Bumped to 2 to add attachments column
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    print('[DatabaseHelper] Creating database tables (version $version)');

    // Sent PQC emails table
    await db.execute('''
      CREATE TABLE sent_pqc_emails (
        id TEXT PRIMARY KEY,
        subject TEXT NOT NULL,
        body TEXT NOT NULL,
        recipientEmail TEXT NOT NULL,
        senderEmail TEXT NOT NULL,
        sentAt TEXT NOT NULL,
        attachments TEXT
      )
    ''');

    // Index for faster queries by sender
    await db.execute('''
      CREATE INDEX idx_sender_email ON sent_pqc_emails(senderEmail)
    ''');

    // Index for faster queries by date
    await db.execute('''
      CREATE INDEX idx_sent_at ON sent_pqc_emails(sentAt DESC)
    ''');

    print('[DatabaseHelper] Database tables created successfully');
  }

  /// Handle database upgrades (for future schema changes)
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('[DatabaseHelper] Upgrading database from version $oldVersion to $newVersion');

    // Add attachments column for version 2
    if (oldVersion < 2) {
      print('[DatabaseHelper] Adding attachments column to sent_pqc_emails table');
      await db.execute('ALTER TABLE sent_pqc_emails ADD COLUMN attachments TEXT');
    }
  }

  /// Insert a sent PQC email
  Future<int> insertSentPqcEmail(SentPqcEmail email) async {
    try {
      print('[DatabaseHelper] ===== INSERTING PQC EMAIL TO DATABASE =====');
      print('[DatabaseHelper] Email ID: ${email.id}');
      print('[DatabaseHelper] Subject: ${email.subject}');
      print('[DatabaseHelper] Attachments: ${email.attachments.length}');

      if (email.attachments.isNotEmpty) {
        for (int i = 0; i < email.attachments.length; i++) {
          print('[DatabaseHelper] Attachment $i: ${email.attachments[i].fileName}, size: ${email.attachments[i].contentBase64.length} bytes');
        }
      }

      final emailMap = email.toMap();
      print('[DatabaseHelper] Converted to map, keys: ${emailMap.keys.toList()}');
      print('[DatabaseHelper] Attachments JSON length: ${emailMap['attachments']?.toString().length ?? 0}');

      final db = await database;
      final result = await db.insert(
        'sent_pqc_emails',
        emailMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('[DatabaseHelper] ✅ Inserted sent PQC email: ${email.id}, result: $result');
      return result;
    } catch (e, stackTrace) {
      print('[DatabaseHelper] ❌ Error inserting sent PQC email: $e');
      print('[DatabaseHelper] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Get a sent PQC email by ID
  Future<SentPqcEmail?> getSentPqcEmail(String id) async {
    try {
      print('[DatabaseHelper] ===== QUERYING LOCAL DATABASE =====');
      print('[DatabaseHelper] Looking for email ID: $id');
      final db = await database;

      // First, let's see what's in the database
      final allEmails = await db.query('sent_pqc_emails');
      print('[DatabaseHelper] Total emails in database: ${allEmails.length}');
      for (int i = 0; i < allEmails.length; i++) {
        print('[DatabaseHelper] Email $i: ID=${allEmails[i]['id']}, Subject=${allEmails[i]['subject']}, Attachments JSON: ${allEmails[i]['attachments']}');
      }

      final List<Map<String, dynamic>> maps = await db.query(
        'sent_pqc_emails',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        print('[DatabaseHelper] ❌ Sent PQC email NOT FOUND: $id');
        print('[DatabaseHelper] The email with this ID does not exist in local database');
        return null;
      }

      print('[DatabaseHelper] ✅ Found email in database!');
      print('[DatabaseHelper] Subject: ${maps.first['subject']}');
      print('[DatabaseHelper] Body: ${maps.first['body']}');
      print('[DatabaseHelper] Attachments raw: ${maps.first['attachments']}');

      final email = SentPqcEmail.fromMap(maps.first);
      print('[DatabaseHelper] Parsed email with ${email.attachments.length} attachments');
      if (email.attachments.isNotEmpty) {
        for (int i = 0; i < email.attachments.length; i++) {
          print('[DatabaseHelper] Loaded attachment $i: ${email.attachments[i].fileName}');
        }
      }
      return email;
    } catch (e, stackTrace) {
      print('[DatabaseHelper] ❌ Error getting sent PQC email: $e');
      print('[DatabaseHelper] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Get all sent PQC emails for a user
  Future<List<SentPqcEmail>> getSentPqcEmails(String senderEmail) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'sent_pqc_emails',
        where: 'senderEmail = ?',
        whereArgs: [senderEmail],
        orderBy: 'sentAt DESC',
      );

      return maps.map((map) => SentPqcEmail.fromMap(map)).toList();
    } catch (e) {
      print('[DatabaseHelper] Error getting sent PQC emails: $e');
      return [];
    }
  }

  /// Get all sent PQC emails (no filter)
  Future<List<SentPqcEmail>> getAllSentPqcEmails() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'sent_pqc_emails',
        orderBy: 'sentAt DESC',
      );

      return maps.map((map) => SentPqcEmail.fromMap(map)).toList();
    } catch (e) {
      print('[DatabaseHelper] Error getting all sent PQC emails: $e');
      return [];
    }
  }

  /// Delete a sent PQC email
  Future<int> deleteSentPqcEmail(String id) async {
    try {
      final db = await database;
      final result = await db.delete(
        'sent_pqc_emails',
        where: 'id = ?',
        whereArgs: [id],
      );
      print('[DatabaseHelper] Deleted sent PQC email: $id');
      return result;
    } catch (e) {
      print('[DatabaseHelper] Error deleting sent PQC email: $e');
      return 0;
    }
  }

  /// Delete all sent PQC emails for a user
  Future<int> deleteAllSentPqcEmails(String senderEmail) async {
    try {
      final db = await database;
      final result = await db.delete(
        'sent_pqc_emails',
        where: 'senderEmail = ?',
        whereArgs: [senderEmail],
      );
      print('[DatabaseHelper] Deleted all sent PQC emails for: $senderEmail');
      return result;
    } catch (e) {
      print('[DatabaseHelper] Error deleting all sent PQC emails: $e');
      return 0;
    }
  }

  /// Update a sent PQC email
  Future<int> updateSentPqcEmail(SentPqcEmail email) async {
    try {
      final db = await database;
      final result = await db.update(
        'sent_pqc_emails',
        email.toMap(),
        where: 'id = ?',
        whereArgs: [email.id],
      );
      print('[DatabaseHelper] Updated sent PQC email: ${email.id}');
      return result;
    } catch (e) {
      print('[DatabaseHelper] Error updating sent PQC email: $e');
      return 0;
    }
  }

  /// Get count of sent PQC emails
  Future<int> getSentPqcEmailCount(String? senderEmail) async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        senderEmail != null
            ? 'SELECT COUNT(*) as count FROM sent_pqc_emails WHERE senderEmail = ?'
            : 'SELECT COUNT(*) as count FROM sent_pqc_emails',
        senderEmail != null ? [senderEmail] : null,
      );

      final count = Sqflite.firstIntValue(result) ?? 0;
      print('[DatabaseHelper] Sent PQC email count: $count');
      return count;
    } catch (e) {
      print('[DatabaseHelper] Error getting sent PQC email count: $e');
      return 0;
    }
  }

  /// Close database connection
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
    print('[DatabaseHelper] Database closed');
  }

  /// Delete entire database (for testing/debugging)
  Future<void> deleteDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'qumail_local.db');
    await databaseFactory.deleteDatabase(path);
    _database = null;
    print('[DatabaseHelper] Database deleted');
  }
}
