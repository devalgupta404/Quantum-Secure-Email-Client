import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/sent_pqc_email.dart';
import '../models/cached_inbox_email.dart';

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
      version: 4, // Bumped to 4 to add isCached field
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

    // Cached inbox emails table (NEW)
    await db.execute('''
      CREATE TABLE cached_inbox_emails (
        id TEXT PRIMARY KEY,
        subject TEXT NOT NULL,
        body TEXT NOT NULL,
        senderEmail TEXT NOT NULL,
        recipientEmail TEXT NOT NULL,
        receivedAt TEXT NOT NULL,
        encryptionMethod TEXT NOT NULL,
        attachments TEXT,
        isDecrypted INTEGER DEFAULT 0,
        isCached INTEGER DEFAULT 1,
        cachedAt TEXT NOT NULL,
        lastAccessed TEXT
      )
    ''');

    // Index for faster queries by sender (sent emails)
    await db.execute('''
      CREATE INDEX idx_sender_email ON sent_pqc_emails(senderEmail)
    ''');

    // Index for faster queries by date (sent emails)
    await db.execute('''
      CREATE INDEX idx_sent_at ON sent_pqc_emails(sentAt DESC)
    ''');

    // Index for faster queries by recipient (inbox emails)
    await db.execute('''
      CREATE INDEX idx_inbox_recipient ON cached_inbox_emails(recipientEmail)
    ''');

    // Index for faster queries by date (inbox emails)
    await db.execute('''
      CREATE INDEX idx_inbox_received_at ON cached_inbox_emails(receivedAt DESC)
    ''');

    // Index for decryption status (inbox emails)
    await db.execute('''
      CREATE INDEX idx_inbox_decrypted ON cached_inbox_emails(isDecrypted)
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

    // Add inbox caching table for version 3
    if (oldVersion < 3) {
      print('[DatabaseHelper] Adding cached_inbox_emails table');
      await db.execute('''
        CREATE TABLE cached_inbox_emails (
          id TEXT PRIMARY KEY,
          subject TEXT NOT NULL,
          body TEXT NOT NULL,
          senderEmail TEXT NOT NULL,
          recipientEmail TEXT NOT NULL,
          receivedAt TEXT NOT NULL,
          encryptionMethod TEXT NOT NULL,
          attachments TEXT,
          isDecrypted INTEGER DEFAULT 0,
          cachedAt TEXT NOT NULL,
          lastAccessed TEXT
        )
      ''');

      // Add indexes for inbox emails
      await db.execute('CREATE INDEX idx_inbox_recipient ON cached_inbox_emails(recipientEmail)');
      await db.execute('CREATE INDEX idx_inbox_received_at ON cached_inbox_emails(receivedAt DESC)');
      await db.execute('CREATE INDEX idx_inbox_decrypted ON cached_inbox_emails(isDecrypted)');
    }

    // Add isCached field for version 4
    if (oldVersion < 4) {
      print('[DatabaseHelper] Adding isCached field to cached_inbox_emails table');
      await db.execute('ALTER TABLE cached_inbox_emails ADD COLUMN isCached INTEGER DEFAULT 1');
      
      // Update existing records to be marked as cached
      await db.execute('UPDATE cached_inbox_emails SET isCached = 1 WHERE isCached IS NULL');
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

  // ===== INBOX CACHING FUNCTIONS =====

  /// Cache decrypted inbox email for faster loading
  Future<int> cacheInboxEmail(CachedInboxEmail email) async {
    try {
      // Check if email already exists to avoid unnecessary operations
      final existing = await getCachedInboxEmail(email.id);
      if (existing != null) {
        print('[DatabaseHelper] Email ${email.id} already cached, updating instead');
        // Update existing record instead of inserting
        final db = await database;
        final result = await db.update(
          'cached_inbox_emails',
          email.toMap(),
          where: 'id = ?',
          whereArgs: [email.id],
        );
        print('[DatabaseHelper] ✅ Updated cached inbox email: ${email.id}');
        return result;
      }
      
      print('[DatabaseHelper] Caching inbox email: ${email.id}');
      final db = await database;
      final result = await db.insert(
        'cached_inbox_emails',
        email.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('[DatabaseHelper] ✅ Cached inbox email: ${email.id}');
      return result;
    } catch (e) {
      print('[DatabaseHelper] ❌ Error caching inbox email: $e');
      rethrow;
    }
  }

  /// Get cached inbox email by ID
  Future<CachedInboxEmail?> getCachedInboxEmail(String id) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'cached_inbox_emails',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        print('[DatabaseHelper] Cached inbox email not found: $id');
        return null;
      }

      final email = CachedInboxEmail.fromMap(maps.first);
      
      // Update last accessed time
      await updateLastAccessed(id);
      
      return email;
    } catch (e) {
      print('[DatabaseHelper] Error getting cached inbox email: $e');
      return null;
    }
  }

  /// Get all cached inbox emails for a recipient (including non-cached ones)
  Future<List<CachedInboxEmail>> getAllCachedInboxEmails(String recipientEmail) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'cached_inbox_emails',
        where: 'recipientEmail = ?',
        whereArgs: [recipientEmail],
        orderBy: 'receivedAt DESC',
      );

      final emails = maps.map((map) => CachedInboxEmail.fromMap(map)).toList();
      print('[DatabaseHelper] Found ${emails.length} total cached inbox emails for $recipientEmail');
      return emails;
    } catch (e) {
      print('[DatabaseHelper] Error getting all cached inbox emails: $e');
      return [];
    }
  }

  /// Get only decrypted cached emails for faster loading
  Future<List<CachedInboxEmail>> getDecryptedCachedInboxEmails(String recipientEmail) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'cached_inbox_emails',
        where: 'recipientEmail = ? AND isDecrypted = 1',
        whereArgs: [recipientEmail],
        orderBy: 'receivedAt DESC',
      );

      final emails = maps.map((map) => CachedInboxEmail.fromMap(map)).toList();
      print('[DatabaseHelper] Found ${emails.length} decrypted cached inbox emails for $recipientEmail');
      return emails;
    } catch (e) {
      print('[DatabaseHelper] Error getting decrypted cached inbox emails: $e');
      return [];
    }
  }

  /// Get only cached emails (isCached = 1) for faster loading
  Future<List<CachedInboxEmail>> getCachedInboxEmails(String recipientEmail) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'cached_inbox_emails',
        where: 'recipientEmail = ? AND isCached = 1',
        whereArgs: [recipientEmail],
        orderBy: 'receivedAt DESC',
      );

      final emails = maps.map((map) => CachedInboxEmail.fromMap(map)).toList();
      print('[DatabaseHelper] Found ${emails.length} cached inbox emails for $recipientEmail');
      return emails;
    } catch (e) {
      print('[DatabaseHelper] Error getting cached inbox emails: $e');
      return [];
    }
  }

  /// Update email as decrypted
  Future<int> markEmailAsDecrypted(String id) async {
    try {
      final db = await database;
      final result = await db.update(
        'cached_inbox_emails',
        {
          'isDecrypted': 1,
          'lastAccessed': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      print('[DatabaseHelper] Marked email as decrypted: $id');
      return result;
    } catch (e) {
      print('[DatabaseHelper] Error marking email as decrypted: $e');
      return 0;
    }
  }

  /// Mark email as not cached (isCached = 0)
  Future<int> markEmailAsNotCached(String id) async {
    try {
      final db = await database;
      final result = await db.update(
        'cached_inbox_emails',
        {
          'isCached': 0,
          'lastAccessed': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      print('[DatabaseHelper] Marked email as not cached: $id');
      return result;
    } catch (e) {
      print('[DatabaseHelper] Error marking email as not cached: $e');
      return 0;
    }
  }

  /// Update last accessed time
  Future<int> updateLastAccessed(String id) async {
    try {
      final db = await database;
      final result = await db.update(
        'cached_inbox_emails',
        {'lastAccessed': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      return result;
    } catch (e) {
      print('[DatabaseHelper] Error updating last accessed: $e');
      return 0;
    }
  }

  /// Delete cached inbox email
  Future<int> deleteCachedInboxEmail(String id) async {
    try {
      final db = await database;
      final result = await db.delete(
        'cached_inbox_emails',
        where: 'id = ?',
        whereArgs: [id],
      );
      print('[DatabaseHelper] Deleted cached inbox email: $id');
      return result;
    } catch (e) {
      print('[DatabaseHelper] Error deleting cached inbox email: $e');
      return 0;
    }
  }

  /// Clear all cached inbox emails for a user
  Future<int> clearCachedInboxEmails(String recipientEmail) async {
    try {
      final db = await database;
      final result = await db.delete(
        'cached_inbox_emails',
        where: 'recipientEmail = ?',
        whereArgs: [recipientEmail],
      );
      print('[DatabaseHelper] Cleared all cached inbox emails for: $recipientEmail');
      return result;
    } catch (e) {
      print('[DatabaseHelper] Error clearing cached inbox emails: $e');
      return 0;
    }
  }

  /// Clean old cached emails (older than 30 days)
  Future<int> cleanOldCachedEmails() async {
    try {
      final db = await database;
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final result = await db.delete(
        'cached_inbox_emails',
        where: 'cachedAt < ?',
        whereArgs: [thirtyDaysAgo.toIso8601String()],
      );
      print('[DatabaseHelper] Cleaned $result old cached emails');
      return result;
    } catch (e) {
      print('[DatabaseHelper] Error cleaning old cached emails: $e');
      return 0;
    }
  }

  /// Get count of cached emails
  Future<int> getCachedEmailCount(String? recipientEmail) async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        recipientEmail != null
            ? 'SELECT COUNT(*) as count FROM cached_inbox_emails WHERE recipientEmail = ?'
            : 'SELECT COUNT(*) as count FROM cached_inbox_emails',
        recipientEmail != null ? [recipientEmail] : null,
      );

      final count = Sqflite.firstIntValue(result) ?? 0;
      print('[DatabaseHelper] Cached email count: $count');
      return count;
    } catch (e) {
      print('[DatabaseHelper] Error getting cached email count: $e');
      return 0;
    }
  }
}
