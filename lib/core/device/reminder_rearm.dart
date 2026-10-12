import 'dart:convert';

import '../db/app_database.dart';
import '../util/format.dart';
import '../../features/casting/calc/pauses.dart';
import '../../features/casting/calc/truck_command.dart';
import '../../features/drilling/drill_readings.dart';
import 'notifications.dart';

/// Put the time-based reminders back from what is STORED, not from what a
/// screen happens to know.
///
/// Every reminder here is an Android alarm scheduled once, when the thing it
/// watches started. Alarms do not survive everything: a phone that reboots
/// loses them, and so does an app update. The foreman would never see that —
/// the pour simply stops buzzing, silently, which is the worst kind of
/// failure for a reminder.
///
/// So the app re-arms them whenever it comes back to the foreground. It is
/// cheap (a few document reads) and idempotent: every schedule call cancels
/// its own ids first, so re-arming twice leaves exactly one set.
///
/// It never fires a buzz for something the user is looking at right now —
/// while the app is open the screen already says it. What it guarantees is
/// that after closing the app, the alarms exist again.
Future<void> rearmReminders({required AppDatabase db, required int userId}) async {
  await _rearmCasting(db, userId);
  await _rearmDrilling(db, userId);
}

Future<String> _pointCode(AppDatabase db, Object? uuid) async {
  final point = await db.getMaster('pile_point', '$uuid');
  return '${point?['code'] ?? '-'}';
}

Future<void> _rearmCasting(AppDatabase db, int userId) async {
  final docs = await db.watchDocuments('casting', userId).first;
  for (final d in docs) {
    if (d.sendStatus == 'rejected') continue;
    final body = (jsonDecode(d.body) as Map).cast<String, Object?>();
    if (body['status'] != 'berjalan') continue;

    final route = '/casting/log/${d.uuid}';
    final code = await _pointCode(db, body['pilePointUuid']);
    final pauses = [
      for (final p in (body['pauses'] as List? ?? const [])) (p as Map).cast<String, Object?>(),
    ];
    final running = runningTruckOf(body);
    final now = DateTime.now();

    if (running != null) {
      final seq = toIntOrNull(running['seq']) ?? 0;
      final open = openPause(pauses, seq);
      if (open != null) {
        await Notifications.schedulePauseReminders(
          route: route,
          title: 'TM #$seq masih dijeda · $code',
          body: 'Sudah lanjut cor? Ketuk Lanjut di log cor',
          from: DateTime.parse('${open['startAt']}').toLocal(),
        );
        continue;
      }
      final start = DateTime.tryParse('${running['startAt']}')?.toLocal();
      if (start == null) continue;
      final due = start.add(truckReminderAfter + pausedTime(pauses, seq, now));
      await Notifications.scheduleTruckReminder(
        route: route,
        title: 'TM #$seq sudah ${truckReminderAfter.inMinutes} menit · $code',
        body: 'Belum selesai dicor. Cek muka beton dan posisi tremie.',
        // Already past: the TM is overdue and the alarm is gone. One buzz
        // shortly after the phone is put down says so; firing it this
        // second, with the screen in the foreman's hand, would not.
        at: due.isAfter(now) ? due : now.add(const Duration(minutes: 1)),
      );
      continue;
    }

    // Nothing pouring: the risk is the NEXT truck being late (cold joint).
    DateTime? lastEnd;
    for (final x in (body['trucks'] as List? ?? const [])) {
      final end = DateTime.tryParse('${(x as Map)['endAt']}')?.toLocal();
      if (end != null && (lastEnd == null || end.isAfter(lastEnd))) lastEnd = end;
    }
    if (lastEnd != null) {
      await Notifications.scheduleIdleReminders(
        route: route,
        title: 'Belum ada TM berikutnya · $code',
        body: 'Awas sambungan dingin. Cek kapan TM datang',
        from: lastEnd,
      );
    }
  }
}

Future<void> _rearmDrilling(AppDatabase db, int userId) async {
  final docs = await db.watchDocuments('drill_log', userId).first;
  for (final d in docs) {
    if (d.sendStatus == 'rejected') continue;
    final body = (jsonDecode(d.body) as Map).cast<String, Object?>();
    if (body['status'] != 'berjalan') continue;
    final readings = readingsOf(body);
    if (readings.isEmpty) continue;
    final newest = readings.map((r) => r.at).reduce((a, b) => a.isAfter(b) ? a : b);
    await Notifications.scheduleDrillIdleReminders(
      logUuid: d.uuid,
      pointCode: await _pointCode(db, body['pilePointUuid']),
      lastReadingAt: newest,
    );
  }
}
