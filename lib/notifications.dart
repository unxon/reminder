import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'domain.dart';
import 'notification_settings.dart';
import 'occurrence_store.dart';

class LocalNotificationService {
  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  final NotificationPreferences preferences;
  final OccurrenceStore? occurrenceStore;
  late final PermissionOrchestrator permissions;
  static const _horizonDays = 370;
  static const _maxScheduled = 120;

  LocalNotificationService(this.preferences, {this.occurrenceStore}) {
    permissions = PermissionOrchestrator(plugin);
  }

  Future<void> initialize() async {
    tz.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(const InitializationSettings(android: android),
        onDidReceiveNotificationResponse: _onResponse);
  }

  Future<void> _onResponse(NotificationResponse response) async {
    final id = response.payload;
    if (id == null || occurrenceStore == null) return;
    await occurrenceStore!.mark(
        id,
        response.actionId == 'complete'
            ? OccurrenceStatus.completed
            : OccurrenceStatus.fired);
  }

  Future<NotificationPermissionStatus> permissionStatus() =>
      permissions.status();
  Future<bool> requestNotificationPermission() =>
      permissions.requestNotifications();
  Future<bool> requestExactAlarmPermission() => permissions.requestExactAlarm();

  Future<void> schedule(Reminder reminder) async {
    await cancel(reminder);
    if (!preferences.enabled || !reminder.enabled) return;
    final status = await permissionStatus();
    if (status.needsNotificationPermission) return;
    final bodyIsPrivate =
        reminder.privateNotification || preferences.privateByDefault;
    final details = NotificationDetails(
        android: AndroidNotificationDetails(
      'reminders',
      'التذكيرات',
      channelDescription: 'تنبيهات التذكيرات المحلية',
      importance: reminder.priority == ReminderPriority.high
          ? Importance.max
          : Importance.high,
      priority: reminder.priority == ReminderPriority.high
          ? Priority.max
          : Priority.high,
      playSound: preferences.sound,
      enableVibration: preferences.vibration,
      visibility: bodyIsPrivate
          ? NotificationVisibility.private
          : NotificationVisibility.public,
      category: AndroidNotificationCategory.reminder,
      actions: const [
        AndroidNotificationAction('complete', 'تم', showsUserInterface: false),
      ],
    ));
    final planned = planOccurrences(reminder, DateTime.now(),
        horizonDays: _horizonDays, limit: _maxScheduled);
    await occurrenceStore?.replaceFuture(
        reminder.id, planned, reminder.updatedAt.toUtc().toIso8601String());
    for (final occurrence in planned) {
      if (preferences.isQuietNow(occurrence)) continue;
      await plugin.zonedSchedule(
        Occurrence.stableNotificationId(reminder.id, occurrence),
        bodyIsPrivate ? 'موعد' : reminder.title,
        bodyIsPrivate ? 'لديك تذكير' : (reminder.note ?? 'حان وقت التذكير'),
        tz.TZDateTime.from(occurrence, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: Occurrence.deterministicId(reminder.id, occurrence),
      );
    }
  }

  Future<void> cancel(Reminder reminder) async {
    await occurrenceStore?.cancelFuture(reminder.id);
    for (final occurrence in planOccurrences(
        reminder, DateTime.now().subtract(const Duration(days: 1)),
        horizonDays: _horizonDays, limit: _maxScheduled)) {
      await plugin
          .cancel(Occurrence.stableNotificationId(reminder.id, occurrence));
    }
  }

  Future<void> cancelAll() => plugin.cancelAll();

  Future<void> reconcile(Iterable<Reminder> reminders) async {
    await cancelAll();
    for (final reminder in reminders.where((item) => item.enabled)) {
      await schedule(reminder);
    }
  }

  Future<void> showTest() => plugin.show(
      999999,
      'موعد',
      'هذا اختبار لإعدادات الإشعارات',
      const NotificationDetails(
          android: AndroidNotificationDetails('reminders', 'التذكيرات',
              channelDescription: 'تنبيهات التذكيرات المحلية',
              importance: Importance.high,
              priority: Priority.high)));
}
