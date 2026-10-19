import 'package:flutter_test/flutter_test.dart';
import 'package:reminders_alerts/domain.dart';
import 'package:reminders_alerts/occurrence_store.dart';

void main() {
  test('planner creates a bounded future window for weekdays', () {
    final reminder = ReminderFactory.create(
      title: 'عمل',
      at: DateTime(2026, 10, 16, 9),
      repeat: ReminderRepeat.weekdays,
    );
    final planned = planOccurrences(reminder, DateTime(2026, 10, 16, 10),
        horizonDays: 14, limit: 20);
    expect(planned, isNotEmpty);
    expect(planned.length, lessThanOrEqualTo(10));
    expect(
        planned.every((date) =>
            date.weekday >= DateTime.monday && date.weekday <= DateTime.friday),
        isTrue);
  });

  test('occurrence notification id is deterministic', () {
    final at = DateTime(2026, 10, 17, 9);
    expect(Occurrence.stableNotificationId('r1', at),
        Occurrence.stableNotificationId('r1', at));
    expect(Occurrence.deterministicId('r1', at),
        'r1:${at.toUtc().toIso8601String()}');
  });
}
