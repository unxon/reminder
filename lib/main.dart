import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'domain.dart';
import 'storage.dart';
import 'notifications.dart';
import 'crypto_vault.dart';
import 'backup.dart';
import 'notification_settings.dart';
import 'occurrence_store.dart';
import 'restore_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeDateFormatting('ar');
    final prefs = await SharedPreferences.getInstance();
    final vault = CryptoVault();
    final db = await AppDatabase.open();
    final notifications = LocalNotificationService(
        NotificationPreferences(prefs),
        occurrenceStore: OccurrenceStore(db));
    await notifications.initialize();
    runApp(RemindersApp(
        repo: SqliteReminderRepository(db, vault),
        notifications: notifications,
        backup: BackupService(vault)));
  } catch (error) {
    runApp(BootstrapRecoveryScreen(error: error.toString()));
  }
}

class BootstrapRecoveryScreen extends StatelessWidget {
  final String error;
  const BootstrapRecoveryScreen({super.key, required this.error});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      home: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.health_and_safety_outlined,
                        size: 64, color: Color(0xff0e7c66)),
                    const SizedBox(height: 18),
                    const Text('نحتاج إلى استرداد التطبيق',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    const Text(
                        'تعذر فتح البيانات المحلية بأمان. لم يتم تعديل بياناتك. أعد المحاولة أو استخدم استعادة نسخة احتياطية.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                        onPressed: main,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة')),
                    const SizedBox(height: 12),
                    Text('رمز التشخيص المحلي: ${error.hashCode}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RemindersApp extends StatefulWidget {
  final ReminderRepository repo;
  final LocalNotificationService? notifications;
  final BackupService? backup;
  const RemindersApp(
      {super.key, required this.repo, this.notifications, this.backup});
  @override
  State<RemindersApp> createState() => _RemindersAppState();
}

class _RemindersAppState extends State<RemindersApp> {
  ThemeMode mode = ThemeMode.light;
  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'موعد',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      locale: const Locale('ar'),
      home: LaunchGate(
          repo: widget.repo,
          notifications: widget.notifications,
          backup: widget.backup,
          onToggleTheme: () => setState(() => mode =
              mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light)));
}

ThemeData appTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  const seed = Color(0xff0e7c66);
  return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: brightness,
          surface: dark ? const Color(0xff101816) : const Color(0xfff8faf8)),
      scaffoldBackgroundColor:
          dark ? const Color(0xff101816) : const Color(0xfff8faf8),
      fontFamily: 'sans',
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: dark ? const Color(0xff18221f) : Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15)),
      cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))));
}

class LaunchGate extends StatefulWidget {
  final ReminderRepository repo;
  final LocalNotificationService? notifications;
  final BackupService? backup;
  final VoidCallback onToggleTheme;
  const LaunchGate(
      {super.key,
      required this.repo,
      required this.notifications,
      required this.backup,
      required this.onToggleTheme});
  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  bool ready = false;
  bool onboarding = false;
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Future<void>.delayed(const Duration(milliseconds: 420));
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      ready = true;
      onboarding = !(prefs.getBool('privacy.onboarded') ?? false);
    });
  }

  Future<void> finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy.onboarded', true);
    if (mounted) setState(() => onboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const _LaunchScreen();
    if (onboarding) return PrivacyWelcome(onContinue: finishOnboarding);
    return HomeScreen(
        repo: widget.repo,
        notifications: widget.notifications,
        backup: widget.backup,
        onToggleTheme: widget.onToggleTheme);
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
            child: TweenAnimationBuilder<double>(
          tween: Tween(begin: .72, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOut,
          builder: (_, value, child) => Opacity(
              opacity: value,
              child: Transform.scale(scale: value, child: child)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(26)),
                child: const Icon(Icons.schedule_rounded,
                    color: Colors.white, size: 44)),
            const SizedBox(height: 18),
            Text('موعد',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('تذكيراتك، بهدوء ووضوح')
          ]),
        )),
      );
}

class PrivacyWelcome extends StatelessWidget {
  final Future<void> Function() onContinue;
  const PrivacyWelcome({super.key, required this.onContinue});
  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(),
                      const Icon(Icons.shield_outlined,
                          size: 62, color: Color(0xff0e7c66)),
                      const SizedBox(height: 24),
                      Text('خصوصيتك أولًا',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      const Text(
                          'موعد يعمل محليًا على جهازك. لا نطلب حسابًا، ولا نستخدم إعلانات أو تتبعًا.'),
                      const SizedBox(height: 24),
                      const _PrivacyPoint(
                          icon: Icons.cloud_off_outlined,
                          text: 'تذكيراتك محفوظة على جهازك افتراضيًا'),
                      const _PrivacyPoint(
                          icon: Icons.notifications_none_rounded,
                          text: 'نطلب الإشعارات عند إنشاء أول تذكير فقط'),
                      const _PrivacyPoint(
                          icon: Icons.sync_lock_outlined,
                          text: 'المزامنة اختيارية وتحتاج موافقة صريحة'),
                      const Spacer(),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: onContinue,
                              child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Text('متابعة')))),
                      const SizedBox(height: 12),
                      const Center(
                          child: Text('يمكن تغيير إعدادات الخصوصية لاحقًا'))
                    ]))),
      ));
}

class _PrivacyPoint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PrivacyPoint({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text))
      ]));
}

class HomeScreen extends StatefulWidget {
  final ReminderRepository repo;
  final LocalNotificationService? notifications;
  final BackupService? backup;
  final VoidCallback onToggleTheme;
  const HomeScreen(
      {super.key,
      required this.repo,
      required this.notifications,
      required this.backup,
      required this.onToggleTheme});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  List<Reminder> reminders = [];
  bool loading = true;
  String filter = 'الكل';
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() => loading = true);
    reminders = await widget.repo.all();
    reminders.sort((a, b) => nextOccurrence(a, DateTime.now())
        .compareTo(nextOccurrence(b, DateTime.now())));
    final service = widget.notifications;
    if (service != null) {
      await service.occurrenceStore?.sweepMissed();
      await service.reconcile(reminders);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> scheduleWithPermission(Reminder reminder) async {
    final service = widget.notifications;
    if (service == null) return;
    final current = await service.permissionStatus();
    if (current.needsNotificationPermission && mounted) {
      final shouldAsk = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('السماح بالإشعارات؟'),
          content: const Text(
              'يحتاج موعد إلى إشعارات الجهاز ليذكّرك في الوقت المحدد. يمكنك المتابعة دونها وسيبقى التذكير محفوظًا.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('لاحقًا')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('السماح')),
          ],
        ),
      );
      if (shouldAsk == true) await service.requestNotificationPermission();
    }
    await service.schedule(reminder);
  }

  Future<void> create() async {
    final r = await Navigator.push<Reminder>(context,
        MaterialPageRoute(builder: (_) => EditorScreen(repo: widget.repo)));
    if (r != null) {
      await scheduleWithPermission(r);
      reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      Dashboard(
          reminders: reminders,
          loading: loading,
          filter: filter,
          onFilter: (v) => setState(() => filter = v),
          onToggle: (r) async {
            final updated = r.copyWith(enabled: !r.enabled);
            await widget.repo.save(updated);
            if (updated.enabled) {
              await widget.notifications?.schedule(updated);
            } else {
              await widget.notifications?.cancel(updated);
            }
            reload();
          },
          onEdit: (r) async {
            final x = await Navigator.push<Reminder>(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        EditorScreen(repo: widget.repo, reminder: r)));
            if (x != null) {
              await widget.notifications?.cancel(r);
              await scheduleWithPermission(x);
              reload();
            }
          },
          onDelete: (r) async {
            await widget.notifications?.cancel(r);
            await widget.repo.delete(r.id);
            reload();
          }),
      ReminderList(
          reminders: reminders,
          onEdit: (r) async {
            final x = await Navigator.push<Reminder>(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        EditorScreen(repo: widget.repo, reminder: r)));
            if (x != null) {
              await widget.notifications?.cancel(r);
              await scheduleWithPermission(x);
              reload();
            }
          }),
      SettingsScreen(
          onToggleTheme: widget.onToggleTheme,
          repo: widget.repo,
          backup: widget.backup,
          notifications: widget.notifications,
          onNotificationsChanged: reload)
    ];
    return Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Scaffold(
            body: SafeArea(child: IndexedStack(index: tab, children: pages)),
            floatingActionButton: tab < 2
                ? FloatingActionButton.extended(
                    onPressed: create,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('تذكير جديد'))
                : null,
            bottomNavigationBar: NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: (i) => setState(() => tab = i),
                destinations: const [
                  NavigationDestination(
                      icon: Icon(Icons.today_outlined),
                      selectedIcon: Icon(Icons.today_rounded),
                      label: 'اليوم'),
                  NavigationDestination(
                      icon: Icon(Icons.list_alt_outlined),
                      selectedIcon: Icon(Icons.list_alt_rounded),
                      label: 'تذكيراتي'),
                  NavigationDestination(
                      icon: Icon(Icons.tune_rounded), label: 'الإعدادات')
                ])));
  }
}

class Dashboard extends StatelessWidget {
  final List<Reminder> reminders;
  final bool loading;
  final String filter;
  final ValueChanged<String> onFilter;
  final Future<void> Function(Reminder) onToggle;
  final Future<void> Function(Reminder) onEdit;
  final Future<void> Function(Reminder) onDelete;
  const Dashboard(
      {super.key,
      required this.reminders,
      required this.loading,
      required this.filter,
      required this.onFilter,
      required this.onToggle,
      required this.onEdit,
      required this.onDelete});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final active = reminders
        .where((r) =>
            r.enabled &&
            (filter == 'الكل' || categoryLabel(r.category) == filter))
        .toList();
    final upcoming = active.where((r) {
      final delta = nextOccurrence(r, now).difference(now);
      return !delta.isNegative && delta.inHours < 24;
    }).toList();
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(greeting(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary)),
                                const SizedBox(height: 4),
                                Text('يومك بوضوح',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(fontWeight: FontWeight.w800))
                              ]),
                          CircleAvatar(
                              radius: 24,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: Icon(Icons.notifications_none_rounded,
                                  color: Theme.of(context).colorScheme.primary))
                        ]),
                    const SizedBox(height: 22),
                    TodaySummary(count: upcoming.length),
                    const SizedBox(height: 22),
                    Text('تذكيرات اليوم',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                        height: 38,
                        child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: ['الكل', 'شخصي', 'ديني', 'عمل', 'صحة']
                                .map((x) => Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                        end: 8),
                                    child: ChoiceChip(
                                        label: Text(x),
                                        selected: filter == x,
                                        onSelected: (_) => onFilter(x))))
                                .toList()))
                  ]))),
      loading
          ? const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()))
          : active.isEmpty
              ? const SliverFillRemaining(child: EmptyState())
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 110),
                  sliver: SliverList.builder(
                    itemCount: active.length,
                    itemBuilder: (context, i) {
                      final reminder = active[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ReminderCard(
                          reminder: reminder,
                          onToggle: () => onToggle(reminder),
                          onEdit: () => onEdit(reminder),
                          onDelete: () => onDelete(reminder),
                          onOpen: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ReminderDetailScreen(
                                      reminder: reminder))),
                        ),
                      );
                    },
                  ),
                )
    ]);
  }
}

String greeting() => DateTime.now().hour < 12
    ? 'صباح الخير'
    : DateTime.now().hour < 17
        ? 'نهارك سعيد'
        : 'مساء الخير';

class TodaySummary extends StatelessWidget {
  final int count;
  const TodaySummary({super.key, required this.count});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withValues(alpha: .78)
          ]),
          borderRadius: BorderRadius.circular(24)),
      child: Row(children: [
        Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.check_circle_outline_rounded,
                color: Colors.white, size: 28)),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(' $count تذكيرات قادمة',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          const Text('أنت مستعد ليوم هادئ ومنظم',
              style: TextStyle(color: Colors.white70))
        ])
      ]));
}

class ReminderCard extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback onToggle, onEdit, onDelete;
  final VoidCallback? onOpen;
  const ReminderCard(
      {super.key,
      required this.reminder,
      required this.onToggle,
      required this.onEdit,
      required this.onDelete,
      this.onOpen});
  @override
  Widget build(BuildContext context) {
    final color = categoryColor(reminder.category, context);
    return Card(
        child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(15)),
                      child:
                          Icon(categoryIcon(reminder.category), color: color)),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(reminder.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 5),
                        Text(
                            '${DateFormat('h:mm a', 'ar').format(nextOccurrence(reminder, DateTime.now()))}  •  ${repeatLabel(reminder.repeat)}',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 13))
                      ])),
                  PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') onEdit();
                        if (v == 'delete') onDelete();
                      },
                      itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('تعديل')),
                            PopupMenuItem(value: 'delete', child: Text('حذف'))
                          ]),
                  Switch(value: reminder.enabled, onChanged: (_) => onToggle())
                ]))));
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.event_note_rounded,
                size: 58, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 18),
            Text('لا توجد تذكيرات بعد',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('ابدأ بتذكير واحد يساعدك على ترتيب يومك.',
                textAlign: TextAlign.center)
          ])));
}

class ReminderList extends StatelessWidget {
  final List<Reminder> reminders;
  final Future<void> Function(Reminder) onEdit;
  const ReminderList(
      {super.key, required this.reminders, required this.onEdit});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('تذكيراتي',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('${reminders.length} تذكيرات محفوظة على هذا الجهاز',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 22),
        Expanded(
            child: reminders.isEmpty
                ? const EmptyState()
                : ListView.separated(
                    itemCount: reminders.length,
                    itemBuilder: (context, i) => ReminderCard(
                        reminder: reminders[i],
                        onToggle: () {},
                        onEdit: () => onEdit(reminders[i]),
                        onDelete: () {},
                        onOpen: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ReminderDetailScreen(
                                    reminder: reminders[i])))),
                    separatorBuilder: (_, __) => const SizedBox(height: 10)))
      ]));
}

class SettingsScreen extends StatelessWidget {
  final VoidCallback onToggleTheme;
  final ReminderRepository repo;
  final BackupService? backup;
  final LocalNotificationService? notifications;
  final Future<void> Function()? onNotificationsChanged;
  const SettingsScreen(
      {super.key,
      required this.onToggleTheme,
      required this.repo,
      required this.backup,
      required this.notifications,
      this.onNotificationsChanged});
  Future<void> _openNotificationSettings(BuildContext context) async {
    if (notifications == null) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                NotificationSettingsScreen(service: notifications!)));
    await onNotificationsChanged?.call();
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(22, 22, 22, 40), children: [
        Text('الإعدادات',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 22),
        const _SettingsSection(title: 'المظهر', children: [
          _SettingTile(
              icon: Icons.dark_mode_outlined,
              title: 'المظهر',
              subtitle: 'فاتح أو داكن أو حسب النظام')
        ]),
        _SettingsSection(title: 'الإشعارات', children: [
          _SettingTile(
              icon: Icons.notifications_active_outlined,
              title: 'الإشعارات المحلية',
              subtitle: 'الصوت، الاهتزاز، الخصوصية والصلاحيات',
              onTap: () => _openNotificationSettings(context)),
          _SettingTile(
              icon: Icons.tune_rounded,
              title: 'تخصيص التنبيهات',
              subtitle: 'تغيير الهدوء الليلي والتفضيلات الافتراضية',
              onTap: () => _openNotificationSettings(context)),
        ]),
        const _SettingsSection(title: 'الخصوصية', children: [
          _SettingTile(
              icon: Icons.lock_outline_rounded,
              title: 'الخصوصية والأمان',
              subtitle: 'حقول التذكيرات مشفرة بمفتاح الجهاز')
        ]),
        _SettingsSection(title: 'النسخ الاحتياطي', children: [
          _SettingTile(
              icon: Icons.backup_outlined,
              title: 'تصدير نسخة مشفرة',
              subtitle: 'نسخة محلية قابلة للاستعادة لاحقًا',
              onTap: () async {
                if (backup == null) return;
                await backup!.exportLocal(repo);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('تم حفظ النسخة المشفرة محليًا')));
                }
              }),
          _SettingTile(
              icon: Icons.restore_page_outlined,
              title: 'استعادة نسخة مشفرة',
              subtitle: 'فحص واستعادة ملف موعد من الجهاز',
              onTap: backup == null
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => RestoreScreen(
                              repo: repo,
                              backup: backup!,
                              notifications: notifications))))
        ]),
        const SizedBox(height: 18),
        OutlinedButton.icon(
            onPressed: onToggleTheme,
            icon: const Icon(Icons.brightness_6_outlined),
            label: const Text('تبديل المظهر'))
      ]);
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection({required this.title, required this.children});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(title,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold))),
        Card(child: Column(children: children)),
        const SizedBox(height: 16)
      ]);
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  const _SettingTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
      onTap: onTap,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_left_rounded));
}

class NotificationSettingsScreen extends StatefulWidget {
  final LocalNotificationService service;
  const NotificationSettingsScreen({super.key, required this.service});
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late NotificationPreferences prefs;
  NotificationPermissionStatus? status;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    prefs = widget.service.preferences;
    _refresh();
  }

  Future<void> _refresh() async {
    final value = await widget.service.permissionStatus();
    if (mounted) {
      setState(() {
        status = value;
        loading = false;
      });
    }
  }

  Future<void> _requestNotifications() async {
    await widget.service.requestNotificationPermission();
    await _refresh();
  }

  Future<void> _requestExact() async {
    await widget.service.requestExactAlarmPermission();
    await _refresh();
  }

  Future<void> _test() async {
    await widget.service.showTest();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال إشعار الاختبار')));
    }
  }

  Future<void> _pickQuietWindow() async {
    final start = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
            hour: prefs.quietStart ~/ 60, minute: prefs.quietStart % 60));
    if (start == null || !mounted) return;
    final end = await showTimePicker(
        context: context,
        initialTime:
            TimeOfDay(hour: prefs.quietEnd ~/ 60, minute: prefs.quietEnd % 60));
    if (end == null) return;
    await prefs.setQuietWindow(
        start: start.hour * 60 + start.minute, end: end.hour * 60 + end.minute);
    if (mounted) setState(() {});
  }

  String _formatMinute(int value) {
    final h = value ~/ 60;
    final m = value % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('الإشعارات والتخصيص')),
          body: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 40),
              children: [
                Text('تحكم كامل بدون مفاجآت',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('تُحفظ هذه الاختيارات على جهازك ولا تحتاج اتصالًا.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 20),
                _PermissionCard(
                    title: 'إشعارات التطبيق',
                    icon: Icons.notifications_active_outlined,
                    granted: status?.notificationsEnabled == true,
                    actionLabel: 'السماح بالإشعارات',
                    onAction: status?.needsNotificationPermission == true
                        ? _requestNotifications
                        : null),
                _PermissionCard(
                    title: 'التنبيه في الوقت المحدد',
                    icon: Icons.alarm_on_outlined,
                    granted: status?.exactAlarmAllowed != false,
                    actionLabel: 'السماح بالدقة',
                    onAction: status?.needsExactAlarmPermission == true
                        ? _requestExact
                        : null),
                const SizedBox(height: 12),
                Card(
                    child: Column(children: [
                  SwitchListTile(
                      value: prefs.enabled,
                      onChanged: (v) async {
                        await prefs.setEnabled(v);
                        setState(() {});
                      },
                      secondary: const Icon(Icons.power_settings_new_rounded),
                      title: const Text('تفعيل الإشعارات'),
                      subtitle: const Text('إيقاف مؤقت دون حذف التذكيرات')),
                  SwitchListTile(
                      value: prefs.sound,
                      onChanged: (v) async {
                        await prefs.setSound(v);
                        setState(() {});
                      },
                      secondary: const Icon(Icons.volume_up_outlined),
                      title: const Text('الصوت'),
                      subtitle: const Text('تشغيل صوت التنبيه')),
                  SwitchListTile(
                      value: prefs.vibration,
                      onChanged: (v) async {
                        await prefs.setVibration(v);
                        setState(() {});
                      },
                      secondary: const Icon(Icons.vibration_outlined),
                      title: const Text('الاهتزاز'),
                      subtitle: const Text('اهتزاز الجهاز مع التنبيه')),
                  SwitchListTile(
                      value: prefs.privateByDefault,
                      onChanged: (v) async {
                        await prefs.setPrivateByDefault(v);
                        setState(() {});
                      },
                      secondary: const Icon(Icons.visibility_off_outlined),
                      title: const Text('إخفاء التفاصيل افتراضيًا'),
                      subtitle: const Text('يظهر “لديك تذكير” على شاشة القفل')),
                ])),
                const SizedBox(height: 16),
                Card(
                    child: Column(children: [
                  SwitchListTile(
                      value: prefs.quietEnabled,
                      onChanged: (v) async {
                        await prefs.setQuietEnabled(v);
                        setState(() {});
                      },
                      secondary: const Icon(Icons.nights_stay_outlined),
                      title: const Text('الهدوء الليلي'),
                      subtitle: Text(
                          'عدم إصدار تنبيهات من ${_formatMinute(prefs.quietStart)} إلى ${_formatMinute(prefs.quietEnd)}')),
                  ListTile(
                      onTap: _pickQuietWindow,
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('تعديل وقت الهدوء'),
                      subtitle: const Text('اختر بداية ونهاية الفترة الهادئة'),
                      trailing: const Icon(Icons.chevron_left_rounded)),
                ])),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                    onPressed: _test,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('إرسال إشعار اختبار')),
              ]),
        ));
  }
}

class _PermissionCard extends StatelessWidget {
  final String title, actionLabel;
  final IconData icon;
  final bool granted;
  final VoidCallback? onAction;
  const _PermissionCard(
      {required this.title,
      required this.actionLabel,
      required this.icon,
      required this.granted,
      required this.onAction});
  @override
  Widget build(BuildContext context) => Card(
      color: granted
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
          leading: Icon(icon),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(granted
              ? 'الحالة: مفعّلة'
              : 'الحالة: تحتاج إلى إجراء من إعدادات النظام'),
          trailing: onAction == null
              ? const Icon(Icons.check_circle_outline)
              : TextButton(onPressed: onAction, child: Text(actionLabel))));
}

class ReminderDetailScreen extends StatelessWidget {
  final Reminder reminder;
  const ReminderDetailScreen({super.key, required this.reminder});
  @override
  Widget build(BuildContext context) {
    final next = nextOccurrence(reminder, DateTime.now());
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تفاصيل التذكير')),
        body: ListView(padding: const EdgeInsets.all(22), children: [
          CircleAvatar(
              radius: 34,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(categoryIcon(reminder.category),
                  size: 32, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 18),
          Text(reminder.title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          if (reminder.note?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(reminder.note!, textAlign: TextAlign.center)
          ],
          const SizedBox(height: 24),
          Card(
              child: Column(children: [
            ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('الموعد القادم'),
                subtitle: Text(
                    DateFormat('EEEE، d MMMM، h:mm a', 'ar').format(next))),
            ListTile(
                leading: const Icon(Icons.repeat_rounded),
                title: const Text('التكرار'),
                subtitle: Text(repeatLabel(reminder.repeat))),
            ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('التصنيف'),
                subtitle: Text(categoryLabel(reminder.category))),
            ListTile(
                leading: const Icon(Icons.priority_high_rounded),
                title: const Text('الأولوية'),
                subtitle: Text(priorityLabel(reminder.priority))),
            ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('خصوصية الإشعار'),
                subtitle: Text(reminder.privateNotification
                    ? 'تفاصيل مخفية على شاشة القفل'
                    : 'تفاصيل ظاهرة حسب إعدادات النظام')),
          ])),
          const SizedBox(height: 18),
          OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check_rounded),
              label: const Text('إغلاق')),
        ]),
      ),
    );
  }
}

class EditorScreen extends StatefulWidget {
  final ReminderRepository repo;
  final Reminder? reminder;
  const EditorScreen({super.key, required this.repo, this.reminder});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, note;
  late DateTime at;
  ReminderRepeat repeat = ReminderRepeat.once;
  ReminderPriority priority = ReminderPriority.normal;
  ReminderCategory category = ReminderCategory.personal;
  bool privateNote = false;
  @override
  void initState() {
    super.initState();
    final r = widget.reminder;
    title = TextEditingController(text: r?.title);
    note = TextEditingController(text: r?.note);
    at = r?.scheduledAt ?? DateTime.now().add(const Duration(hours: 1));
    repeat = r?.repeat ?? repeat;
    priority = r?.priority ?? priority;
    category = r?.category ?? category;
    privateNote = r?.privateNotification ?? false;
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final r = widget.reminder?.copyWith(
            title: title.text,
            note: note.text,
            scheduledAt: at,
            repeat: repeat,
            priority: priority,
            category: category,
            privateNotification: privateNote) ??
        ReminderFactory.create(
            title: title.text,
            note: note.text,
            at: at,
            repeat: repeat,
            priority: priority,
            category: category,
            privateNotification: privateNote);
    await widget.repo.save(r);
    if (mounted) Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
          appBar: AppBar(
              title: Text(
                  widget.reminder == null ? 'تذكير جديد' : 'تعديل التذكير'),
              actions: [TextButton(onPressed: save, child: const Text('حفظ'))]),
          body: Form(
              key: form,
              child: ListView(padding: const EdgeInsets.all(22), children: [
                TextFormField(
                    controller: title,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'ما الذي تريد تذكره؟',
                        prefixIcon: Icon(Icons.edit_outlined)),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'اكتب عنوانًا للتذكير'
                        : null),
                const SizedBox(height: 16),
                TextFormField(
                    controller: note,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'ملاحظة اختيارية',
                        prefixIcon: Icon(Icons.notes_outlined))),
                const SizedBox(height: 22),
                _FieldLabel('وقت التذكير'),
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_rounded),
                    title: Text(
                        DateFormat('EEEE، d MMMM • h:mm a', 'ar').format(at)),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: pickDate),
                const Divider(height: 26),
                _FieldLabel('التكرار'),
                DropdownButtonFormField(
                    initialValue: repeat,
                    items: ReminderRepeat.values
                        .map((x) => DropdownMenuItem(
                            value: x, child: Text(repeatLabel(x))))
                        .toList(),
                    onChanged: (x) => setState(() => repeat = x!),
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.repeat_rounded))),
                const SizedBox(height: 16),
                _FieldLabel('التصنيف'),
                Wrap(
                    spacing: 8,
                    children: ReminderCategory.values
                        .map((x) => ChoiceChip(
                            label: Text(categoryLabel(x)),
                            selected: category == x,
                            onSelected: (_) => setState(() => category = x)))
                        .toList()),
                const SizedBox(height: 20),
                _FieldLabel('الأولوية'),
                SegmentedButton<ReminderPriority>(
                    segments: const [
                      ButtonSegment(
                          value: ReminderPriority.low, label: Text('منخفضة')),
                      ButtonSegment(
                          value: ReminderPriority.normal, label: Text('عادية')),
                      ButtonSegment(
                          value: ReminderPriority.high, label: Text('عالية'))
                    ],
                    selected: {
                      priority
                    },
                    onSelectionChanged: (v) =>
                        setState(() => priority = v.first)),
                const SizedBox(height: 20),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: privateNote,
                    onChanged: (v) => setState(() => privateNote = v),
                    title: const Text('إخفاء تفاصيل الإشعار'),
                    subtitle: const Text('يظهر تنبيه عام على شاشة القفل'),
                    secondary: const Icon(Icons.visibility_off_outlined))
              ]))));
  Future<void> pickDate() async {
    final d = await showDatePicker(
        context: context,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
        initialDate: at);
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(at));
    if (t != null && mounted) {
      setState(() => at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
    }
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext c) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: Theme.of(c)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold)));
}

String repeatLabel(ReminderRepeat x) => switch (x) {
      ReminderRepeat.once => 'مرة واحدة',
      ReminderRepeat.daily => 'يوميًا',
      ReminderRepeat.weekdays => 'أيام العمل',
      ReminderRepeat.weekly => 'أسبوعيًا',
      ReminderRepeat.monthly => 'شهريًا'
    };
String categoryLabel(ReminderCategory x) => switch (x) {
      ReminderCategory.personal => 'شخصي',
      ReminderCategory.religious => 'ديني',
      ReminderCategory.work => 'عمل',
      ReminderCategory.health => 'صحة'
    };
String priorityLabel(ReminderPriority x) => switch (x) {
      ReminderPriority.low => 'منخفضة',
      ReminderPriority.normal => 'عادية',
      ReminderPriority.high => 'عالية'
    };
IconData categoryIcon(ReminderCategory x) => switch (x) {
      ReminderCategory.personal => Icons.person_outline_rounded,
      ReminderCategory.religious => Icons.auto_awesome_outlined,
      ReminderCategory.work => Icons.work_outline_rounded,
      ReminderCategory.health => Icons.favorite_border_rounded
    };
Color categoryColor(ReminderCategory x, BuildContext c) => switch (x) {
      ReminderCategory.personal => Theme.of(c).colorScheme.primary,
      ReminderCategory.religious => Colors.amber.shade700,
      ReminderCategory.work => Colors.indigo,
      ReminderCategory.health => Colors.pink
    };
