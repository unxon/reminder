import 'package:flutter_test/flutter_test.dart';
import 'package:reminders_alerts/domain.dart';

void main() {
  test('daily reminder advances to the next future occurrence', () {
    final now = DateTime(2026, 10, 14, 10);
    final r = ReminderFactory.create(
        title: 'اختبار',
        at: DateTime(2026, 10, 13, 9),
        repeat: ReminderRepeat.daily);
    expect(nextOccurrence(r, now), DateTime(2026, 10, 15, 9));
  });
  test('factory creates enabled local reminder', () {
    final r = ReminderFactory.create(title: '  قراءة  ', at: DateTime.now());
    expect(r.title, 'قراءة');
    expect(r.enabled, true);
  });
  test('missed occurrences are bounded and deterministic', () {
    final r = ReminderFactory.create(
        title: 'متابعة',
        at: DateTime(2026, 10, 14, 9),
        repeat: ReminderRepeat.daily);
    final missed = missedOccurrences(
        r, DateTime(2026, 10, 14, 10), DateTime(2026, 10, 17, 10),
        limit: 2);
    expect(missed, [DateTime(2026, 10, 15, 9), DateTime(2026, 10, 16, 9)]);
  });
  test('monthly reminder clamps day 31 to the last day of the next month', () {
    final r = ReminderFactory.create(
        title: 'فاتورة',
        at: DateTime(2026, 1, 31, 9),
        repeat: ReminderRepeat.monthly);
    expect(nextOccurrence(r, DateTime(2026, 2, 1)), DateTime(2026, 2, 28, 9));
  });
}
