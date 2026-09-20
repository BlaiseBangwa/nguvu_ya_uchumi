import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    final db = _database;
    if (db != null) return db;
    _database = await _initDB('tontine_local.db');
    return _database ?? (throw Exception("Database could not be initialized"));
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2, // Inscription de la mise à jour de version pour ajouter la devise
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    // Table Profiles
    await db.execute('''
      CREATE TABLE profiles (
        id TEXT PRIMARY KEY,
        member_code TEXT UNIQUE,
        full_name TEXT NOT NULL,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT,
        address TEXT,
        phone TEXT,
        birth_date TEXT,
        civil_status TEXT,
        job TEXT,
        photo_url TEXT,
        is_approved INTEGER DEFAULT 1,
        synced INTEGER DEFAULT 1
      )
    ''');

    // Table Contributions / Transactions avec prise en charge bidevise
    await db.execute('''
      CREATE TABLE contributions (
        id TEXT PRIMARY KEY,
        member_id TEXT,
        collector_id TEXT,
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'USD',
        type TEXT NOT NULL DEFAULT 'INCOME',
        status TEXT NOT NULL DEFAULT 'APPROVED',
        note TEXT,
        collected_at TEXT NOT NULL,
        synced INTEGER DEFAULT 0
      )
    ''');

    // Table Notifications
    await db.execute('''
      CREATE TABLE notifications (
        id TEXT PRIMARY KEY,
        title TEXT,
        message TEXT,
        type TEXT,
        created_at TEXT,
        synced INTEGER DEFAULT 0
      )
    ''');

    await _insertDefaultAdmin(db);
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE contributions ADD COLUMN currency TEXT NOT NULL DEFAULT 'USD'");
      await db.execute("ALTER TABLE contributions ADD COLUMN type TEXT NOT NULL DEFAULT 'INCOME'");
    }
  }

  static Future<void> _insertDefaultAdmin(Database db) async {
    await db.insert(
      'profiles',
      {
        'id': '00000000-0000-0000-0000-000000000001',
        'member_code': 'ADM-001',
        'full_name': 'Administrateur Principal',
        'username': 'admin',
        'password_hash': 'admin123',
        'role': 'admin',
        'address': 'Bureau Comité Islamique',
        'phone': '+243000000000',
        'civil_status': 'Marié(e)',
        'job': 'Administrateur',
        'is_approved': 1,
        'synced': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Méthodes CRUD & Synchronisation ---

  /// Récupère les cotisations non synchronisées (synced = 0)
  Future<List<Map<String, dynamic>>> getUnsyncedContributions() async {
    final db = await instance.database;
    return await db.query(
      'contributions',
      where: 'synced = ?',
      whereArgs: [0],
    );
  }

  /// Marque une cotisation comme synchronisée
  Future<int> markContributionAsSynced(String id) async {
    final db = await instance.database;
    return await db.update(
      'contributions',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Insère ou met à jour une cotisation
  Future<int> insertContribution(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert(
      'contributions',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Récupère toutes les cotisations locales
  Future<List<Map<String, dynamic>>> getAllContributions() async {
    final db = await instance.database;
    return await db.query('contributions', orderBy: 'collected_at DESC');
  }
}