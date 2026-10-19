import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reminders_alerts/main.dart';
import 'package:reminders_alerts/domain.dart';

void main() {
  testWidgets('app renders Arabic home shell', (tester) async {
    SharedPreferences.setMockInitialValues({'privacy.onboarded': true});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(RemindersApp(repo: LocalReminderRepository(prefs)));
    await tester.pumpAndSettle();
    expect(find.text('يومك بوضوح'), findsOneWidget);
    expect(find.text('تذكير جديد'), findsOneWidget);
  });
}
