import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'domain.dart';

enum OccurrenceStatus {
  scheduled,
  fired,
  completed,
  snoozed,
  missed,
  cancelled
}

class Occurrence {
  final String id;
  final String reminderId;
  final DateTime occurrenceAt;
  final OccurrenceStatus status;
  final int notificationId;
  final String scheduleVersion;
  final DateTime? firedAt;
  final DateTime? completedAt;
  final DateTime? snoozedUntil;

  const Occurrence(
      {required this.id,
      required this.reminderId,
      required this.occurrenceAt,
      required this.status,
      required this.notificationId,
      required this.scheduleVersion,
      this.firedAt,
      this.completedAt,
      this.snoozedUntil});

  static int stableNotificationId(String reminderId, DateTime at) {
    var value = 17;
    for (final code
        in '$reminderId|${at.toUtc().toIso8601String()}'.codeUnits) {
      value = ((value * 31) + code) & 0x7fffffff;
    }
    return value == 0 ? 1 : value;
  }

  static String deterministicId(String reminderId, DateTime at) =>
      '$reminderId:${at.toUtc().toIso8601String()}';

  Map<String, Object?> toRow() => {
        'id': id,
        'reminder_id': reminderId,
        'occurrence_at': occurrenceAt.toUtc().millisecondsSinceEpoch,
        'status': status.name,
        'notification_id': notificationId,
        'schedule_version': scheduleVersion,
        'fired_at': firedAt?.toUtc().millisecondsSinceEpoch,
        'completed_at': completedAt?.toUtc().millisecondsSinceEpoch,
        'snoozed_until': snoozedUntil?.toUtc().millisecondsSinceEpoch,
      };

  factory Occurrence.fromRow(Map<String, Object?> row) => Occurrence(
        id: row['id']! as String,
        reminderId: row['reminder_id']! as String,
        occurrenceAt: DateTime.fromMillisecondsSinceEpoch(
                row['occurrence_at']! as int,
                isUtc: true)
            .toLocal(),
        status: OccurrenceStatus.values.byName(row['status']! as String),
        notificationId: row['notification_id']! as int,
        scheduleVersion: row['schedule_version']! as String,
        firedAt: _date(row['fired_at']),
        completedAt: _date(row['completed_at']),
        snoozedUntil: _date(row['snoozed_until']),
      );

  static DateTime? _date(Object? value) => value == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(value as int, isUtc: true)
          .toLocal();
}

List<DateTime> planOccurrences(Reminder reminder, DateTime now,
    {int horizonDays = 370, int limit = 120}) {
  final result = <DateTime>[];
  var cursor =
      nextOccurrence(reminder, now.subtract(const Duration(seconds: 1)));
  final end = now.add(Duration(days: horizonDays));
  while (result.length < limit && cursor.isBefore(end)) {
    if (cursor.isAfter(now)) result.add(cursor);
    if (reminder.repeat == ReminderRepeat.once) break;
    final next = nextOccurrence(reminder, cursor);
    if (!next.isAfter(cursor)) break;
    cursor = next;
  }
  return result;
}

class OccurrenceStore {
  final Database db;
  OccurrenceStore(this.db);

  Future<void> replaceFuture(String reminderId, Iterable<DateTime> dates,
      String scheduleVersion) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete('occurrences',
          where: 'reminder_id = ? AND occurrence_at >= ? AND status IN (?, ?)',
          whereArgs: [
            reminderId,
            now,
            OccurrenceStatus.scheduled.name,
            OccurrenceStatus.cancelled.name
          ]);
      for (final date in dates) {
        final occurrence = Occurrence(
            id: Occurrence.deterministicId(reminderId, date),
            reminderId: reminderId,
            occurrenceAt: date,
            status: OccurrenceStatus.scheduled,
            notificationId: Occurrence.stableNotificationId(reminderId, date),
            scheduleVersion: scheduleVersion);
        await txn.insert('occurrences', occurrence.toRow(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> cancelFuture(String reminderId) async {
    await db.update('occurrences', {'status': OccurrenceStatus.cancelled.name},
        where: 'reminder_id = ? AND occurrence_at >= ? AND status = ?',
        whereArgs: [
          reminderId,
          DateTime.now().toUtc().millisecondsSinceEpoch,
          OccurrenceStatus.scheduled.name
        ]);
  }

  Future<int> sweepMissed({DateTime? now}) async {
    return db.update('occurrences', {'status': OccurrenceStatus.missed.name},
        where: 'status = ? AND occurrence_at < ?',
        whereArgs: [
          OccurrenceStatus.scheduled.name,
          (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch
        ]);
  }

  Future<void> mark(String id, OccurrenceStatus status, {DateTime? at}) async {
    final now = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final values = <String, Object?>{'status': status.name};
    if (status == OccurrenceStatus.fired) values['fired_at'] = now;
    if (status == OccurrenceStatus.completed) values['completed_at'] = now;
    await db.update('occurrences', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Occurrence>> upcoming({int limit = 200}) async {
    final rows = await db.query('occurrences',
        where: 'status = ? AND occurrence_at >= ?',
        whereArgs: [
          OccurrenceStatus.scheduled.name,
          DateTime.now().toUtc().millisecondsSinceEpoch
        ],
        orderBy: 'occurrence_at ASC',
        limit: limit);
    return rows.map(Occurrence.fromRow).toList();
  }

  Future<List<Occurrence>> missed({int limit = 200}) async {
    final rows = await db.query('occurrences',
        where: 'status = ? OR (status = ? AND occurrence_at < ?)',
        whereArgs: [
          OccurrenceStatus.missed.name,
          OccurrenceStatus.scheduled.name,
          DateTime.now().toUtc().millisecondsSinceEpoch
        ],
        orderBy: 'occurrence_at DESC',
        limit: limit);
    return rows.map(Occurrence.fromRow).toList();
  }
}
