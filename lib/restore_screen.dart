import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'backup.dart';
import 'domain.dart';
import 'notifications.dart';

class RestoreScreen extends StatefulWidget {
  final ReminderRepository repo;
  final BackupService backup;
  final LocalNotificationService? notifications;
  const RestoreScreen(
      {super.key,
      required this.repo,
      required this.backup,
      required this.notifications});
  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  bool working = false;
  String? result;

  Future<void> _pickAndRestore() async {
    final selection = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['mwb']);
    if (selection.isEmpty || selection.first.path == null) return;
    setState(() {
      working = true;
      result = null;
    });
    try {
      final count = await widget.backup
          .restoreFile(File(selection.first.path!), widget.repo);
      final reminders = await widget.repo.all();
      await widget.notifications?.reconcile(reminders);
      if (mounted) {
        setState(() =>
            result = 'تمت استعادة $count تذكيرًا وإعادة جدولة التنبيهات.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => result =
            'تعذر الاستعادة: ${error.toString().replaceFirst('FormatException: ', '')}');
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('استعادة نسخة مشفرة')),
          body: ListView(padding: const EdgeInsets.all(22), children: [
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(children: [
                      Icon(Icons.verified_user_outlined,
                          size: 52,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 14),
                      const Text('استعادة آمنة',
                          style: TextStyle(
                              fontSize: 21, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text(
                          'سيتم فحص الملف وفك تشفيره والتحقق من كل السجلات قبل حفظها. لا يتم قبول الملفات المعدلة أو غير المدعومة.',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                          onPressed: working ? null : _pickAndRestore,
                          icon: working
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.folder_open_rounded),
                          label: Text(
                              working ? 'جارٍ التحقق…' : 'اختيار ملف .mwb')),
                    ]))),
            if (result != null) ...[
              const SizedBox(height: 16),
              Card(
                  child: ListTile(
                      leading: Icon(result!.startsWith('تمت')
                          ? Icons.check_circle_outline
                          : Icons.error_outline),
                      title: Text(result!)))
            ],
          ]),
        ),
      );
}
