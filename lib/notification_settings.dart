import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationPreferences {
  static const enabledKey = 'notifications.enabled';
  static const soundKey = 'notifications.sound';
  static const vibrationKey = 'notifications.vibration';
  static const privateKey = 'notifications.privateByDefault';
  static const quietEnabledKey = 'notifications.quiet.enabled';
  static const quietStartKey = 'notifications.quiet.start';
  static const quietEndKey = 'notifications.quiet.end';

  final SharedPreferences prefs;
  NotificationPreferences(this.prefs);
  bool get enabled => prefs.getBool(enabledKey) ?? true;
  bool get sound => prefs.getBool(soundKey) ?? true;
  bool get vibration => prefs.getBool(vibrationKey) ?? true;
  bool get privateByDefault => prefs.getBool(privateKey) ?? false;
  bool get quietEnabled => prefs.getBool(quietEnabledKey) ?? false;
  int get quietStart => prefs.getInt(quietStartKey) ?? 22 * 60;
  int get quietEnd => prefs.getInt(quietEndKey) ?? 7 * 60;

  Future<void> setEnabled(bool value) => prefs.setBool(enabledKey, value);
  Future<void> setSound(bool value) => prefs.setBool(soundKey, value);
  Future<void> setVibration(bool value) => prefs.setBool(vibrationKey, value);
  Future<void> setPrivateByDefault(bool value) =>
      prefs.setBool(privateKey, value);
  Future<void> setQuietEnabled(bool value) =>
      prefs.setBool(quietEnabledKey, value);
  Future<void> setQuietWindow({required int start, required int end}) async {
    await prefs.setInt(quietStartKey, start);
    await prefs.setInt(quietEndKey, end);
  }

  bool isQuietNow(DateTime now) {
    if (!quietEnabled) return false;
    final minute = now.hour * 60 + now.minute;
    return quietStart > quietEnd
        ? minute >= quietStart || minute < quietEnd
        : minute >= quietStart && minute < quietEnd;
  }
}

class NotificationPermissionStatus {
  final bool? notificationsEnabled;
  final bool? exactAlarmAllowed;
  const NotificationPermissionStatus(
      {required this.notificationsEnabled, required this.exactAlarmAllowed});
  bool get needsNotificationPermission => notificationsEnabled != true;
  bool get needsExactAlarmPermission => exactAlarmAllowed == false;
}

class PermissionOrchestrator {
  final FlutterLocalNotificationsPlugin plugin;
  PermissionOrchestrator(this.plugin);
  AndroidFlutterLocalNotificationsPlugin? get android =>
      plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<NotificationPermissionStatus> status() async =>
      NotificationPermissionStatus(
        notificationsEnabled: await android?.areNotificationsEnabled(),
        exactAlarmAllowed: await android?.canScheduleExactNotifications(),
      );

  Future<bool> requestNotifications() async =>
      await android?.requestNotificationsPermission() ?? false;
  Future<bool> requestExactAlarm() async =>
      await android?.requestExactAlarmsPermission() ?? false;
}
