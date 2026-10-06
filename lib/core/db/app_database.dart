import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// SQLite schema owner. Opened by the UI isolate *and* by the WorkManager
/// background isolate; sqflite shares the native connection per path, and
/// SQLite's own locking serialises writers, so both can use it safely.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _name = 'darkroom.db';
  static const _version = 2;

  static const filmTable = 'film_prints';
  static const sdTable = 'sd_card';

  static Future<AppDatabase> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, _name),
      version: _version,
      onConfigure: (db) async {
        // WAL lets the UI read while the background worker writes.
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.execute('PRAGMA foreign_keys=ON');
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        for (final table in [filmTable, sdTable]) {
          batch.execute('''
            CREATE TABLE $table(
              id TEXT PRIMARY KEY,
              camera_id TEXT NOT NULL,
              kind TEXT NOT NULL,
              status TEXT NOT NULL,
              raw_path TEXT,
              output_path TEXT,
              thumb_path TEXT,
              file_name TEXT NOT NULL,
              width INTEGER,
              height INTEGER,
              bytes INTEGER,
              duration_ms INTEGER,
              captured_at INTEGER NOT NULL,
              ready_at INTEGER NOT NULL,
              notified INTEGER NOT NULL DEFAULT 0,
              seen INTEGER NOT NULL DEFAULT 0,
              job TEXT,
              attempts INTEGER NOT NULL DEFAULT 0,
              error TEXT,
              location TEXT NOT NULL DEFAULT 'sd',
              saved_at INTEGER
            )''');
          batch.execute('CREATE INDEX idx_${table}_status ON $table(status, ready_at)');
        }
        batch.execute('''
          CREATE TABLE camera_settings(
            camera_id TEXT PRIMARY KEY,
            aspect TEXT,
            timestamp INTEGER,
            grain TEXT
          )''');
        batch.execute('''
          CREATE TABLE app_settings(
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )''');
        await batch.commit(noResult: true);
      },
      onUpgrade: (db, from, to) async {
        if (from < 2) {
          // v2: SD files can live on the card or on "C:" (moved off it), film
          // prints remember when they were saved, stocks have a grain setting.
          for (final table in [filmTable, sdTable]) {
            await db.execute("ALTER TABLE $table ADD COLUMN location TEXT NOT NULL DEFAULT 'sd'");
            await db.execute('ALTER TABLE $table ADD COLUMN saved_at INTEGER');
          }
          await db.execute('ALTER TABLE camera_settings ADD COLUMN grain TEXT');
        }
      },
    );
    return AppDatabase._(db);
  }

  // ---- key/value helpers (app_settings) -----------------------------------

  Future<String?> getValue(String key) async {
    final rows = await db.query('app_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setValue(String key, String value) =>
      db.insert('app_settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Atomically increments a named counter and returns the new value
  /// (used for DSC00001-style file numbering).
  Future<int> nextCounter(String key) => db.transaction((txn) async {
    final rows = await txn.query('app_settings', where: 'key = ?', whereArgs: ['counter.$key']);
    final next = rows.isEmpty ? 1 : int.parse(rows.first['value']! as String) + 1;
    await txn.insert('app_settings', {
      'key': 'counter.$key',
      'value': '$next',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return next;
  });
}
