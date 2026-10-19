# موعد — Product & Engineering Specification

**المنتج:** موعد (Mawed)  
**الحزمة:** `com.localfirst.reminders_alerts`  
**المنصة الحالية:** Flutter / Android، Local-first، Arabic-first RTL  
**الإصدار المستهدف:** 1.0 Production  
**آخر تحديث:** 2026-10-17

## 1. الرؤية والحدود

موعد تطبيق تذكيرات شخصية هادئ، خاص، يعمل دون اتصال، ولا يرسل بيانات المستخدم إلى خادم. الوظيفة الأساسية هي إنشاء تذكير واضح، جدولة تنبيه موثوق، تسجيل ما حدث، وتمكين المستخدم من تعديل أو إيقاف أو استعادة بياناته دون فقدان.

الإصدار الأول لا يضم حسابات أو تحليلات أو إعلانات أو صلاحيات غير لازمة. أي مزامنة لاحقة ستكون اختيارية، مشفرة، ومبنية على موافقة صريحة من الطرفين.

## 2. مبادئ المنتج

1. **Local-first:** القراءة والإنشاء والتعديل والإشعارات تعمل دون شبكة.
2. **Privacy by default:** العنوان والملاحظة مشفران في السكون، ومحتوى الإشعار مخفي اختياريًا على شاشة القفل.
3. **Progressive disclosure:** المحرر يعرض الأساسيات أولًا ثم التكرار والأولوية والخصوصية.
4. **No silent failure:** كل فشل في الصلاحيات أو قاعدة البيانات أو الاستعادة له حالة مرئية ومسار تعافٍ.
5. **Idempotent scheduling:** إعادة تشغيل التطبيق أو تحديث التفضيلات لا يضاعف الإشعارات.
6. **Accessible Arabic UX:** RTL، نص قابل للتكبير، مناطق لمس لا تقل عن 48dp، وألوان ذات تباين واضح.

## 3. العلامة وواجهة المستخدم

### 3.1 الهوية

- الاسم المرئي: **موعد**.
- اللون الأساسي: `#0E7C66`.
- لون السطح الداكن: `#0B5F50`.
- لون الإشارة: `#F5E7B2`.
- الرمز: حلقة وقت مفتوحة مع علامة إنجاز ذهبية.
- الأيقونة الأصلية وLaunch Screen يجب أن يستخدما نفس الرمز، لا أيقونة Material افتراضية.

### 3.2 شجرة الصفحات

```text
Bootstrap
├── Launch / Brand
├── First-run Privacy
├── Home / Today
│   ├── Reminder Detail
│   ├── Reminder Editor
│   └── Delete Confirmation + Undo
├── All Reminders
│   ├── Search / Filter / Category
│   └── Reminder Detail
├── Missed Summary
├── Calendar
├── Settings
│   ├── Notification Permission
│   ├── Sound / Vibration / Quiet Hours
│   ├── Privacy Center
│   ├── Encrypted Backup Export
│   ├── Backup Restore / Preview / Rollback
│   └── Diagnostics
└── Recovery
    ├── Retry Bootstrap
    ├── Restore Backup
    └── Safe Local Reset
```

### 3.3 حالات كل صفحة

كل شاشة إنتاجية يجب أن تصمم حالات: loading، empty، populated، disabled، permission denied، offline، error، retry، success confirmation. لا يسمح بزر بلا نتيجة مرئية أو tile يوحي بأنه قابل للنقر دون مسار فعلي.

## 4. نموذج المجال

### Reminder

- `id`: UUID غير قابل للتغيير.
- `title`: مطلوب، من 1 إلى 160 محرفًا.
- `note`: اختياري، من 0 إلى 2,000 محرف.
- `scheduledAt`: وقت محلي محفوظ مع UTC offset وقت الإنشاء.
- `repeat`: once، daily، weekdays، weekly، monthly، ثم custom في مرحلة لاحقة.
- `priority`: low، normal، high.
- `category`: personal، religious، work، health.
- `enabled` و`privateNotification`.
- `createdAt` و`updatedAt`.
- `deletedAt` للحذف الناعم.

### Occurrence

كل موعد فعلي يجب أن يصبح سجلًا مستقلًا:

- `id` حتمي من `reminderId + occurrenceAt`.
- `reminderId`.
- `occurrenceAt` بالـUTC مع timezone identifier.
- `status`: scheduled، fired، completed، snoozed، missed، cancelled.
- `notificationId`.
- `scheduledAtVersion`.
- `firedAt`, `completedAt`, `snoozedUntil`.

## 5. المعمارية

```text
presentation/
  screens/
  widgets/
  design_system/
application/
  reminder_service.dart
  scheduling_service.dart
  backup_service.dart
domain/
  reminder.dart
  recurrence.dart
  occurrence.dart
  repositories.dart
infrastructure/
  sqlite/
  notifications/
  crypto/
  backup/
bootstrap/
  app_bootstrap.dart
```

الواجهة لا تستدعي SQLite أو plugin مباشرة. كل mutation تمر عبر application service، وتحدث قاعدة البيانات وجدولة الإشعار داخل workflow واحد قابل لإعادة المحاولة.

## 6. قاعدة البيانات والهجرات

- SQLite version 2: إضافة `occurrences` و`app_meta`.
- كل migration منفصلة، قابلة لإعادة التشغيل، وتحت transaction.
- لا تتم إزالة الأعمدة قبل migration ثلاثية المراحل.
- فشل migration لا يغلق التطبيق بصمت؛ يعرض Recovery.
- يتم تشفير الحقول النصية الحساسة بواسطة AES-256-GCM ومفتاح Android Keystore.
- يتم وضع integrity marker لكل سجل مشفر.

## 7. خوارزمية الجدولة

1. عند إنشاء أو تعديل أو تعطيل Reminder، ينفذ service transaction.
2. تحذف occurrences المستقبلية لذلك التذكير فقط.
3. يولد occurrence planner نافذة مستقبلية محددة، مع سياسة لكل recurrence.
4. يكتب occurrences أولًا.
5. يبرمج إشعاراتها بمعرف حتمي.
6. إذا فشل جزء من العملية، ينفذ reconciliation عند فتح التطبيق.
7. عند boot، timezone change، app update أو تغيير إعدادات الإشعار، يعاد بناء النافذة بدون duplicate.
8. لا يستخدم التطبيق `DateTime` arithmetic غير واعٍ للـDST في recurrence production.

### قواعد التكرار

- once: موعد واحد.
- daily: نفس الوقت كل يوم.
- weekdays: الإثنين–الجمعة فقط.
- weekly: نفس weekday والوقت.
- monthly: سياسة explicit: clamp إلى آخر يوم صالح.
- لا يضاف recurrence جديد دون اختبار property-based لحالات leap year وDST.

## 8. الإشعارات والصلاحيات

- لا يطلب POST_NOTIFICATIONS أثناء Launch.
- يطلبها عند أول حفظ مع شرح السبب.
- حالة denied وpermanently denied لها مسار system settings.
- `SCHEDULE_EXACT_ALARM` لا تعرض للمستخدم إلا إذا كان السلوك يستخدم exact فعلًا.
- محتوى الإشعار الخاص لا يظهر على lock screen.
- sound/vibration/quiet hours تغير الإعدادات ثم تشغل reconciliation فورًا.
- action buttons المستقبلية: Complete، Snooze، Open.

## 9. النسخ والاستعادة

### Export

- ملف بامتداد `.mwb`.
- تشفير مستقل عن Keystore باستخدام passphrase يختارها المستخدم.
- KDF بطيء مناسب للهاتف، مع salt وversion وalgorithm metadata.
- لا يتم حفظ passphrase.

### Restore

- File picker.
- فحص حجم وحدود schema وversion وMAC قبل أي كتابة.
- Preview للعدد والتغييرات.
- staging database.
- atomic swap أو transaction كاملة.
- rollback عند أي فشل.
- إعادة جدولة الإشعارات بعد النجاح.

## 10. الأمان

- لا logging للنصوص الحساسة.
- لا backup تلقائي لقاعدة البيانات المشفرة إلا وفق قرار واضح.
- مفاتيح خارج Git وCI secrets.
- لا network permission في الإصدار المحلي إلا إذا أضيفت مزامنة معلنة.
- fuzz tests للـbackup parser.
- rate/size limits لكل import.

## 11. الاختبارات

### Unit

- recurrence لكل نوع.
- نهاية الشهر، leap year، DST، timezone.
- deterministic occurrence IDs.
- crypto tamper detection.
- backup schema and migration.

### Integration

- create → save → occurrence → notification.
- edit يزيل القديم ولا يكرر الجديد.
- disable يلغي المستقبل.
- reboot reconciliation.
- denied permission لا يفقد التذكير.
- corrupted DB يظهر Recovery.
- failed restore لا يغير البيانات.

### UI / Device

- Android 12–15.
- light/dark.
- RTL.
- TalkBack.
- text scale 200%.
- reduced motion.
- Doze، force stop، reboot، timezone change.

## 12. Release gates

لا تعتبر النسخة Production إلا بعد:

- [ ] SQLite v2 مع occurrences.
- [ ] Restore مستقل عن Keystore وatomic.
- [ ] Recovery مجرب على DB corruption.
- [ ] Android device matrix ناجحة.
- [ ] AAB موقّع بمفتاح إنتاجي خارج Git.
- [ ] Play Data Safety وPrivacy Policy.
- [ ] إزالة legacy repository.
- [ ] لا توجد شاشة أو tile غير مربوطة.
- [ ] `flutter analyze` بلا issues.
- [ ] جميع الاختبارات وGolden UI ناجحة.

## 13. خطة التنفيذ الحالية

### المرحلة A — الأساس التشغيلي

- [x] SQLite local-first.
- [x] AES-GCM للعنوان والملاحظة.
- [x] Permissions UX.
- [x] Horizon scheduling.
- [x] Brand icon وnative launch.
- [x] Recovery bootstrap.

### المرحلة B — الموثوقية التي يجري تنفيذها الآن

- [x] SQLite v2 وoccurrences.
- [x] قاعدة مشتركة لمخطط التكرار ومعرّفات الإشعارات الحتمية.
- [ ] Scheduler reconciliation service كامل مع boot/timezone hooks.
- [x] إجراء إكمال مباشر من الإشعار وتسجيل fired/completed.
- [ ] إزالة `LocalReminderRepository` من codebase الإنتاجي.
- [x] Restore UI مع File Picker والتحقق قبل الكتابة.
- [x] saveAll transaction في SQLite للاستعادة الجماعية.
- [ ] Missed Summary من occurrences الحقيقية.

### المرحلة C — النضج قبل النشر العام

- [ ] تقسيم `main.dart` إلى modules.
- [ ] Calendar وCategories وSearch.
- [ ] Accessibility/device matrix.
- [ ] Production signing/AAB.
- [ ] P2P sync كمشروع مستقل بعد تثبيت النسخة المحلية.

## 14. تعريف الإنجاز

كل مرحلة لا تعتبر منجزة بوجود ملف أو class فقط. يجب أن يكون لها: workflow UI كامل، data contract، error state، unit test، integration test، وتحقق على Release build.
