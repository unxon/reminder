import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'domain.dart';
import 'crypto_vault.dart';

class AppDatabase {
  static const version = 2;
  static Future<Database> open() async {
    if (!kIsWeb &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final root = await getDatabasesPath();
    return openDatabase(p.join(root, 'mawed_secure_local.db'), version: version,
        onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys = ON');
    }, onCreate: (db, _) async {
      await db.execute('''CREATE TABLE reminders (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, note TEXT, scheduled_at INTEGER NOT NULL,
        repeat TEXT NOT NULL, priority TEXT NOT NULL, category TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1, private_notification INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER
      )''');
      await db.execute(
          'CREATE INDEX idx_reminders_next ON reminders(enabled, scheduled_at)');
      await db.execute(
          'CREATE INDEX idx_reminders_updated ON reminders(updated_at)');
      await _createOccurrences(db);
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) await _createOccurrences(db);
    });
  }

  static Future<void> _createOccurrences(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS occurrences (
      id TEXT PRIMARY KEY, reminder_id TEXT NOT NULL, occurrence_at INTEGER NOT NULL,
      status TEXT NOT NULL, notification_id INTEGER NOT NULL, schedule_version TEXT NOT NULL,
      fired_at INTEGER, completed_at INTEGER, snoozed_until INTEGER,
      FOREIGN KEY(reminder_id) REFERENCES reminders(id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_occurrences_due ON occurrences(status, occurrence_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_occurrences_reminder ON occurrences(reminder_id, occurrence_at)');
  }
}

class SqliteReminderRepository implements ReminderRepository {
  final Database db;
  final CryptoVault vault;
  SqliteReminderRepository(this.db, this.vault);

  @override
  Future<List<Reminder>> all() async {
    final rows = await db.query('reminders',
        where: 'deleted_at IS NULL', orderBy: 'scheduled_at ASC');
    return Future.wait(rows.map(_fromRow));
  }

  @override
  Future<void> save(Reminder r) async {
    final row = await _toRow(r);
    await db.transaction((txn) async => txn.insert('reminders', row,
        conflictAlgorithm: ConflictAlgorithm.replace));
  }

  @override
  Future<void> saveAll(List<Reminder> reminders) async {
    final rows = await Future.wait(reminders.map(_toRow));
    await db.transaction((txn) async {
      for (final row in rows) {
        await txn.insert('reminders', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('reminders', {'deleted_at': now, 'updated_at': now},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<Reminder> _fromRow(Map<String, Object?> row) async => Reminder(
        id: row['id']! as String,
        title: (await vault.decrypt(row['title']! as String)) ?? '',
        note: await vault.decrypt(row['note'] as String?),
        scheduledAt:
            DateTime.fromMillisecondsSinceEpoch(row['scheduled_at']! as int),
        repeat: ReminderRepeat.values.byName(row['repeat']! as String),
        priority: ReminderPriority.values.byName(row['priority']! as String),
        category: ReminderCategory.values.byName(row['category']! as String),
        enabled: (row['enabled']! as int) == 1,
        privateNotification: (row['private_notification']! as int) == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
      );

  Future<Map<String, Object?>> _toRow(Reminder r) async => {
        'id': r.id,
        'title': await vault.encrypt(r.title),
        'note': r.note == null ? null : await vault.encrypt(r.note!),
        'scheduled_at': r.scheduledAt.millisecondsSinceEpoch,
        'repeat': r.repeat.name,
        'priority': r.priority.name,
        'category': r.category.name,
        'enabled': r.enabled ? 1 : 0,
        'private_notification': r.privateNotification ? 1 : 0,
        'created_at': r.createdAt.millisecondsSinceEpoch,
        'updated_at': r.updatedAt.millisecondsSinceEpoch,
        'deleted_at': null,
      };
}
