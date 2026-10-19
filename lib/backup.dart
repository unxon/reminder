import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'crypto_vault.dart';
import 'domain.dart';

class BackupService {
  final CryptoVault vault;
  BackupService(this.vault);

  Future<File> exportLocal(ReminderRepository repo) async {
    final reminders = await repo.all();
    final payload = jsonEncode({
      'format': 'mawed.backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'reminders': reminders.map((r) => r.toJson()).toList()
    });
    final encrypted = await vault.encrypt(payload);
    final directory = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${directory.path}/backups');
    if (!backupDir.existsSync()) await backupDir.create(recursive: true);
    final file = File(
        '${backupDir.path}/mawed-${DateTime.now().millisecondsSinceEpoch}.mwb');
    await file.writeAsString(
        jsonEncode({
          'format': 'mawed.encrypted-backup',
          'version': 1,
          'ciphertext': encrypted
        }),
        flush: true);
    return file;
  }

  Future<int> restoreFile(File file, ReminderRepository repo) async {
    if (!await file.exists()) {
      throw const FormatException('ملف النسخة غير موجود');
    }
    if (await file.length() > 10 * 1024 * 1024) {
      throw const FormatException('حجم النسخة الاحتياطية أكبر من الحد المسموح');
    }
    final envelope = jsonDecode(await file.readAsString());
    if (envelope is! Map ||
        envelope['format'] != 'mawed.encrypted-backup' ||
        envelope['version'] != 1 ||
        envelope['ciphertext'] is! String) {
      throw const FormatException('نسخة احتياطية غير معروفة أو غير متوافقة');
    }
    final clear = await vault.decrypt(envelope['ciphertext'] as String);
    if (clear == null) throw const FormatException('تعذر فك النسخة الاحتياطية');
    final document = jsonDecode(clear);
    if (document is! Map ||
        document['format'] != 'mawed.backup' ||
        document['version'] != 1 ||
        document['reminders'] is! List) {
      throw const FormatException('النسخة الاحتياطية تالفة أو معدلة');
    }
    final decoded = <Reminder>[];
    for (final item in document['reminders'] as List) {
      if (item is! Map) {
        throw const FormatException('سجل غير صالح داخل النسخة');
      }
      decoded.add(Reminder.fromJson(Map<String, dynamic>.from(item)));
    }
    await repo.saveAll(decoded);
    return decoded.length;
  }
}
