import 'dart:convert';
import 'package:uuid/uuid.dart';

enum ReminderPriority { low, normal, high }

enum ReminderRepeat { once, daily, weekdays, weekly, monthly }

enum ReminderCategory { personal, religious, work, health }

class Reminder {
  final String id;
  final String title;
  final String? note;
  final DateTime scheduledAt;
  final ReminderRepeat repeat;
  final ReminderPriority priority;
  final ReminderCategory category;
  final bool enabled;
  final bool privateNotification;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Reminder(
      {required this.id,
      required this.title,
      this.note,
      required this.scheduledAt,
      required this.repeat,
      required this.priority,
      required this.category,
      required this.enabled,
      required this.privateNotification,
      required this.createdAt,
      required this.updatedAt});

  Reminder copyWith(
          {String? title,
          String? note,
          DateTime? scheduledAt,
          ReminderRepeat? repeat,
          ReminderPriority? priority,
          ReminderCategory? category,
          bool? enabled,
          bool? privateNotification}) =>
      Reminder(
          id: id,
          title: title ?? this.title,
          note: note ?? this.note,
          scheduledAt: scheduledAt ?? this.scheduledAt,
          repeat: repeat ?? this.repeat,
          priority: priority ?? this.priority,
          category: category ?? this.category,
          enabled: enabled ?? this.enabled,
          privateNotification: privateNotification ?? this.privateNotification,
          createdAt: createdAt,
          updatedAt: DateTime.now());

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'scheduledAt': scheduledAt.toIso8601String(),
        'repeat': repeat.name,
        'priority': priority.name,
        'category': category.name,
        'enabled': enabled,
        'privateNotification': privateNotification,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String()
      };
  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
      id: j['id'],
      title: j['title'],
      note: j['note'],
      scheduledAt: DateTime.parse(j['scheduledAt']),
      repeat: ReminderRepeat.values.byName(j['repeat']),
      priority: ReminderPriority.values.byName(j['priority']),
      category: ReminderCategory.values.byName(j['category']),
      enabled: j['enabled'] ?? true,
      privateNotification: j['privateNotification'] ?? false,
      createdAt: DateTime.parse(j['createdAt']),
      updatedAt: DateTime.parse(j['updatedAt']));
}

abstract class ReminderRepository {
  Future<List<Reminder>> all();
  Future<void> save(Reminder reminder);
  Future<void> saveAll(List<Reminder> reminders);
  Future<void> delete(String id);
}

class LocalReminderRepository implements ReminderRepository {
  static const _key = 'reminders.v1';
  final dynamic preferences;
  LocalReminderRepository(this.preferences);
  @override
  Future<List<Reminder>> all() async {
    final raw = preferences.getString(_key);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(Reminder.fromJson).toList();
  }

  @override
  Future<void> save(Reminder reminder) async {
    final items = await all();
    final i = items.indexWhere((e) => e.id == reminder.id);
    if (i >= 0) {
      items[i] = reminder;
    } else {
      items.add(reminder);
    }
    await preferences.setString(
        _key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  @override
  Future<void> saveAll(List<Reminder> reminders) async {
    final items = await all();
    for (final reminder in reminders) {
      final index = items.indexWhere((item) => item.id == reminder.id);
      if (index >= 0) {
        items[index] = reminder;
      } else {
        items.add(reminder);
      }
    }
    await preferences.setString(
        _key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  @override
  Future<void> delete(String id) async {
    final items = await all();
    items.removeWhere((e) => e.id == id);
    await preferences.setString(
        _key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }
}

class ReminderFactory {
  static Reminder create(
      {required String title,
      String? note,
      required DateTime at,
      ReminderRepeat repeat = ReminderRepeat.once,
      ReminderPriority priority = ReminderPriority.normal,
      ReminderCategory category = ReminderCategory.personal,
      bool privateNotification = false}) {
    final now = DateTime.now();
    return Reminder(
        id: const Uuid().v4(),
        title: title.trim(),
        note: note?.trim().isEmpty == true ? null : note?.trim(),
        scheduledAt: at,
        repeat: repeat,
        priority: priority,
        category: category,
        enabled: true,
        privateNotification: privateNotification,
        createdAt: now,
        updatedAt: now);
  }
}

DateTime _addMonthClamped(DateTime value) {
  final year = value.month == 12 ? value.year + 1 : value.year;
  final month = value.month == 12 ? 1 : value.month + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = value.day > lastDay ? lastDay : value.day;
  return DateTime(year, month, day, value.hour, value.minute, value.second,
      value.millisecond, value.microsecond);
}

DateTime nextOccurrence(Reminder reminder, DateTime now) {
  var next = reminder.scheduledAt;
  if (reminder.repeat == ReminderRepeat.once) return next;
  while (!next.isAfter(now)) {
    switch (reminder.repeat) {
      case ReminderRepeat.daily:
        next = next.add(const Duration(days: 1));
        break;
      case ReminderRepeat.weekdays:
        next = next.add(const Duration(days: 1));
        while (next.weekday > DateTime.friday) {
          next = next.add(const Duration(days: 1));
        }
        break;
      case ReminderRepeat.weekly:
        next = next.add(const Duration(days: 7));
        break;
      case ReminderRepeat.monthly:
        next = _addMonthClamped(next);
        break;
      case ReminderRepeat.once:
        break;
    }
  }
  return next;
}

List<DateTime> missedOccurrences(
    Reminder reminder, DateTime since, DateTime now,
    {int limit = 100}) {
  if (!reminder.enabled || !now.isAfter(since) || limit < 1) return [];
  final result = <DateTime>[];
  var cursor = reminder.scheduledAt;
  while (result.length < limit && !cursor.isAfter(now)) {
    if (cursor.isAfter(since)) result.add(cursor);
    if (reminder.repeat == ReminderRepeat.once) break;
    final next = nextOccurrence(reminder, cursor);
    if (!next.isAfter(cursor)) break;
    cursor = next;
  }
  return result;
}
