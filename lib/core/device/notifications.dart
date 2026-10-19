import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../i18n.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Casting stopwatch notification.
///
/// While a TM is being cast, the QS is busy at the drill hole and the phone is in
/// a pocket. A persistent notification with a running clock (Android chronometer
/// — counted by the system, does not need the app to stay alive) shows how long
/// this TM has been casting, and the "Selesai TM" button goes straight to its casting screen.
class Notifications {
  Notifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _stopwatchId = 7001;
  static const _reminderId = 7002;
  static const _handoverId = 7003;

  /// Pause reminders use ids 7100–7119, one per buzz.
  static const _pauseReminderBase = 7100;
  static const _pauseReminderCount = 20;
  static const pauseReminderEvery = Duration(minutes: 3);
  static const actionFinishTruck = 'finish_truck';

  /// "Selesai TM" yang DIKERJAKAN TANPA MEMBUKA LAYAR — dipakai dari arloji.
  ///
  /// Berbeda dari [actionFinishTruck], yang membuka log cor di HP. Di
  /// pergelangan tangan, tombol yang menyuruh mengeluarkan HP dari saku
  /// tidak menghemat satu pun gerakan — dan itulah satu-satunya alasan
  /// tombolnya ada di sana.
  static const actionFinishNow = 'finish_truck_now';

  static const _soundingId = 7004;

  /// Translations for code with no widget tree.
  ///
  /// Null only before the first build (a cold start in the background
  /// isolate), so every use falls back to Indonesian — the language of the
  /// site, and the one every foreman reads.
  ///
  /// CHANNEL names and descriptions are NOT translated. Android freezes them
  /// when the channel is first created and never re-reads them, so a
  /// translated name would simply be whatever language the app happened to
  /// be in on the very first run — worse than one consistent language.

  /// TerraBot blue, and the amber of a paused pour. Android tints the small
  /// icon and the app name with it — the only colouring a plain ongoing
  /// notification is allowed.
  static const _brand = Color(0xFF154DEC);
  static const _paused = Color(0xFFB4690E);

  /// `onTapped(payload, action)` — the payload holds the destination route.
  static Future<void> init(
    void Function(String? payload, String? action) onTapped, {
    void Function(NotificationResponse)? diLatar,
  }) async {
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notification')),
      onDidReceiveNotificationResponse: (r) => onTapped(r.payload, r.actionId),
      // Ditekan dari ARLOJI, aplikasinya kerap tidak berjalan sama sekali.
      // Tanpa penangan latar ini, ketukannya hanya meluncurkan aplikasi —
      // yaitu persis yang hendak dihindari.
      onDidReceiveBackgroundNotificationResponse: diLatar,
    );
  }

  /// Android 13+: the notification permission is requested the first time it is needed.
  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Whether the phone lets this app show notifications (and so buzz).
  /// Unknown (no Android plugin) counts as allowed.
  static Future<bool> enabled() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled() ??
      true;

  /// Route that opened the app via a notification (the app was previously closed).
  static Future<String?> initialRoute() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d == null || !d.didNotificationLaunchApp) return null;
    return d.notificationResponse?.payload;
  }

  /// The casting notification, dressed like the phone's own stopwatch.
  ///
  /// Everything here earns its place on a lock screen seen through a glove,
  /// at arm's length, in daylight:
  ///
  ///   * the running clock is Android's own chronometer — counted by the OS,
  ///     so it keeps ticking with the screen off and the app killed;
  ///   * [subText] rides in the header next to the app name, so the project
  ///     and point are readable while the notification is collapsed;
  ///   * the progress bar is the concrete climbing toward cut-off — the one
  ///     number the QS actually watches, and the reason to glance at all;
  ///   * the large icon makes it look like a running job, not a message.
  ///
  /// What is deliberately NOT used: `colorized`. Android only honours a
  /// coloured background for foreground-service and media notifications, and
  /// MediaStyle — the one style that would colour it — cannot show a
  /// chronometer. A pretty box is not worth losing the clock.
  static Future<void> showStopwatch({
    required String route,
    required String title,
    required String body,
    required DateTime start,
    String? subText,
    String? detail,
    int? progress,
  }) {
    return _plugin.show(
      id: _stopwatchId,
      title: title,
      body: body,
      payload: route,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'casting',
          'Pengecoran berjalan',
          channelDescription: 'Stopwatch TM yang sedang dicor',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: true,
          when: start.millisecondsSinceEpoch,
          usesChronometer: true,
          category: AndroidNotificationCategory.stopwatch,
          color: _brand,
          largeIcon: const DrawableResourceAndroidBitmap('splash_mark'),
          subText: subText,
          // Pulled down, the notification tells the whole story without
          // opening the app — which is the point when both hands are busy.
          styleInformation: detail == null
              ? null
              : BigTextStyleInformation(detail, contentTitle: title, summaryText: subText),
          showProgress: progress != null,
          maxProgress: 100,
          progress: progress ?? 0,
          actions: [
            // SELESAI TM lebih dulu: di arloji hanya tombol pertama yang
            // terbaca tanpa menggulir, dan itulah yang dicari saat tuangnya
            // berhenti.
            //
            // `showsUserInterface: false` — dikerjakan di isolate latar,
            // tanpa membuka apa pun. Lihat `aksi_notifikasi.dart`.
            AndroidNotificationAction(
              actionFinishNow,
              L10n.current?.finishTruckAction ?? 'Selesai TM',
              showsUserInterface: false,
              cancelNotification: false,
            ),
            AndroidNotificationAction(actionFinishTruck, L10n.current?.openCastLog ?? 'Buka log cor', showsUserInterface: true),
          ],
        ),
      ),
    );
  }

  /// SOUNDING SESUDAH TUANG yang belum diisi, sesudah TM ditutup dari arloji.
  ///
  /// Berdering dan bergetar, bukan diam: dari sounding inilah tertanam
  /// tremie, muka beton akhir, dan seluruh pemeriksaan volume dihitung.
  /// Ditutup dari arloji tanpa pengingat ini, angka itu tidak akan pernah
  /// terisi — dan tidak ada satu pun galat yang mengatakannya.
  static Future<void> showSoundingDue({
    required String route,
    required String title,
    required String body,
  }) {
    return _plugin.show(
      id: _soundingId,
      title: title,
      body: body,
      payload: route,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'casting_reminder',
          'Pengingat cor',
          channelDescription: 'Getar saat satu TM sudah 20 menit belum selesai dicor',
          importance: Importance.high,
          priority: Priority.high,
          vibrationPattern: _buzz,
          category: AndroidNotificationCategory.reminder,
          color: _brand,
          styleInformation: BigTextStyleInformation(body, contentTitle: title),
        ),
      ),
    );
  }

  static Future<void> clearSoundingDue() => _plugin.cancel(id: _soundingId);

  /// Same slot as the stopwatch, without a running clock: Android's
  /// notification clock cannot be paused, so a paused pour shows text only.
  static Future<void> showPaused({
    required String route,
    required String title,
    required String body,
    String? subText,
    String? detail,
  }) {
    return _plugin.show(
      id: _stopwatchId,
      title: title,
      body: body,
      payload: route,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'casting',
          'Pengecoran berjalan',
          channelDescription: 'Stopwatch TM yang sedang dicor',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: false,
          category: AndroidNotificationCategory.stopwatch,
          color: _paused,
          largeIcon: const DrawableResourceAndroidBitmap('splash_mark'),
          subText: subText,
          styleInformation: detail == null
              ? null
              : BigTextStyleInformation(detail, contentTitle: title, summaryText: subText),
          actions: [
            AndroidNotificationAction(actionFinishTruck, L10n.current?.resumePouring ?? 'Lanjutkan cor', showsUserInterface: true),
          ],
        ),
      ),
    );
  }
  static Future<void> clearStopwatch() => _plugin.cancel(id: _stopwatchId);

  /// Long buzz-pause-buzz: noticeable in a pocket next to a running rig.
  static final _buzz = Int64List.fromList([0, 900, 350, 900, 350, 900]);

  /// One reminder at [at] that a TM is still being poured, with vibration.
  ///
  /// Scheduled with the system alarm, so it fires with the app closed.
  /// "Inexact" needs no extra permission; Android may deliver it up to a
  /// minute or so late, which is fine for a 20-minute reminder.
  static Future<void> scheduleTruckReminder({
    required String route,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    await cancelTruckReminder();
    if (!at.isAfter(DateTime.now())) return;
    await _plugin.zonedSchedule(
      id: _reminderId,
      title: title,
      body: body,
      payload: route,
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // A channel of its own: a channel's sound and vibration are fixed once
      // Android has created it, and the stopwatch one is silent.
      notificationDetails: _buzzDetails,
    );
  }

  static Future<void> cancelTruckReminder() => _plugin.cancel(id: _reminderId);

  /// Seorang rekan di titik meminta log yang dipegang HP ini.
  ///
  /// Berbunyi dan bergetar: ini satu-satunya pemberitahuan di aplikasi yang
  /// ada ORANG menunggu jawaban di lapangan, bukan sekadar pengingat. Isinya
  /// menyebut nama dan kode titik, sebab "seseorang meminta log Anda" adalah
  /// kalimat yang orang belajar mengabaikannya.
  static Future<void> showHandoverRequest({
    required String entity,
    required String logUuid,
    required String pointCode,
    String? requesterName,
  }) {
    final l = L10n.current;
    final siapa = requesterName ?? l?.colleague ?? 'Rekan';
    final rute = entity == 'drill_log' ? '/drilling/log/$logUuid' : '/casting/log/$logUuid';
    return _plugin.show(
      id: _handoverId,
      title: l?.handoverRequestTitle(siapa) ?? '$siapa minta oper',
      body: l?.handoverRequestBody(pointCode) ?? 'Titik $pointCode — buka untuk menyetujui atau menolak.',
      payload: rute,
      notificationDetails: _buzzDetails,
    );
  }

  static Future<void> clearHandoverRequest() => _plugin.cancel(id: _handoverId);

  static NotificationDetails get _buzzDetails => NotificationDetails(
        android: AndroidNotificationDetails(
          'casting_reminder',
          'Pengingat cor',
          channelDescription: 'Getar saat satu TM sudah 20 menit belum selesai dicor',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          vibrationPattern: _buzz,
          category: AndroidNotificationCategory.reminder,
        ),
      );

  /// While a pour is paused: buzz every [pauseReminderEvery] for up to an
  /// hour, so nobody forgets to tap Lanjut. All cancelled on Lanjut or
  /// Selesai TM. Scheduled up front, so it works with the app closed.
  static Future<void> schedulePauseReminders({
    required String route,
    required String title,
    required String body,
    required DateTime from,
  }) async {
    await cancelPauseReminders();
    for (var i = 1; i <= _pauseReminderCount; i++) {
      final at = from.add(pauseReminderEvery * i);
      await _plugin.zonedSchedule(
        id: _pauseReminderBase + i,
        title: title,
        body: L10n.current?.pauseReminderMin(body, (pauseReminderEvery * i).inMinutes) ??
            '$body · ${(pauseReminderEvery * i).inMinutes} menit',
        payload: route,
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: _buzzDetails,
      );
    }
  }

  /// No new truck after the last one finished: buzz at 30, 40 … 90 minutes.
  /// Cancelled when the next truck arrives or the casting is finished.
  static const _idleBase = 7200;
  static const idleFirstAfter = Duration(minutes: 30);
  static const _idleEvery = Duration(minutes: 10);
  static const _idleCount = 7;

  static Future<void> scheduleIdleReminders({
    required String route,
    required String title,
    required String body,
    required DateTime from,
  }) async {
    await cancelIdleReminders();
    for (var i = 0; i < _idleCount; i++) {
      final wait = idleFirstAfter + _idleEvery * i;
      final at = from.add(wait);
      if (!at.isAfter(DateTime.now())) continue;
      await _plugin.zonedSchedule(
        id: _idleBase + i,
        title: title,
        body: L10n.current?.idleReminderMin(body, wait.inMinutes) ?? '$body · ${wait.inMinutes} menit sejak TM terakhir',
        payload: route,
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: _buzzDetails,
      );
    }
  }

  static Future<void> cancelIdleReminders() async {
    for (var i = 0; i < _idleCount; i++) {
      await _plugin.cancel(id: _idleBase + i);
    }
  }

  // -------------------------------------------------------------------------
  // Drilling with no new reading
  // -------------------------------------------------------------------------

  /// While a hole is being drilled the foreman logs the depth now and then;
  /// a forgotten log is worthless afterwards. Buzz when the newest reading is
  /// [drillIdleFirst] old, then every [drillIdleEvery], [drillIdleCount]
  /// times in all. Rescheduled on every save of the log, cancelled when it is
  /// finished. Scheduled up front, so it works with the app closed.
  ///
  /// DIPERKETAT 19 Okt 2026 atas permintaan Daniel: bacaan yang terlupakan
  /// adalah kebiasaan, bukan kecelakaan, dan 1 jam + tiap 30 menit × 5
  /// terlalu sabar untuk kebiasaan. Sekarang 45 menit, lalu tiap 15 menit,
  /// delapan kali — berbunyi dari menit ke-45 sampai jam ke-2.30.
  ///
  /// Yang membuatnya aman untuk diperketat adalah adanya jalan keluar:
  /// "Diamkan sampai besok" pada notifikasinya sendiri. Tanpa itu, alarm
  /// seberisik ini akan membuat orang mematikan SELURUH notifikasi aplikasi
  /// lewat setelan Android — diam-diam, dan selamanya.
  static const drillIdleFirst = Duration(minutes: 45);
  static const drillIdleEvery = Duration(minutes: 15);
  static const drillIdleCount = 8;

  /// Sesudah bunyi ke-sekian, getarnya diperpanjang dan tingkatnya dinaikkan.
  ///
  /// Bunyi yang persis sama tiap lima belas menit berubah menjadi latar
  /// belakang; yang berubah tetap menuntut perhatian. Dinaikkan pada bunyi
  /// KETIGA (menit ke-75), bukan sejak awal — yang pertama cukup berupa
  /// ingatan, bukan tuduhan.
  static const _drillIdleKeras = 3;
  static final _buzzKeras =
      Int64List.fromList([0, 1200, 250, 1200, 250, 1200, 250, 1200]);

  /// Tombol "Diamkan sampai besok" pada pengingat log bor.
  static const actionSnoozeDrill = 'snooze_drill_until_tomorrow';
  static const _drillIdleBase = 7500;
  static const _drillIdleSlots = 20;

  /// Ids for one log. Stable across app restarts (String.hashCode is not),
  /// so a later save or finish can cancel what an earlier run scheduled.
  static int _drillIdleId(String logUuid, int i) {
    var h = 0;
    for (final c in logUuid.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _drillIdleBase + (h % _drillIdleSlots) * drillIdleCount + i;
  }

  /// [snoozeUntil] — pengingat yang jatuh SEBELUM jam itu dilewati.
  ///
  /// Dilewati, bukan dibatalkan seluruhnya: yang jatuh SESUDAHnya tetap
  /// dipasang, sehingga pengingatnya menyala sendiri besok pagi tanpa ada
  /// yang perlu mengingatnya. Penundaan yang mematikan alarm sampai ada
  /// yang menyalakannya lagi adalah penundaan yang menjadi permanen.
  static Future<void> scheduleDrillIdleReminders({
    required String logUuid,
    required String pointCode,
    required DateTime lastReadingAt,
    DateTime? snoozeUntil,
  }) async {
    await cancelDrillIdleReminders(logUuid);
    final now = DateTime.now();
    for (var i = 0; i < drillIdleCount; i++) {
      final wait = drillIdleFirst + drillIdleEvery * i;
      final at = lastReadingAt.add(wait);
      if (!at.isAfter(now)) continue;
      if (snoozeUntil != null && at.isBefore(snoozeUntil)) continue;
      await _plugin.zonedSchedule(
        id: _drillIdleId(logUuid, i),
        title: L10n.current?.drillIdleTitle(pointCode) ?? 'Log bor $pointCode belum diisi',
        body: L10n.current?.drillIdleBody(_minutesText(wait), _dayTime(lastReadingAt).split(' ').last) ??
            'Sudah ${_minutesText(wait)} sejak bacaan terakhir (${_dayTime(lastReadingAt).split(' ').last}). '
                'Catat kedalaman sekarang, atau tekan Selesai bor bila sudah selesai.',
        payload: '/drilling/log/$logUuid',
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'drill_reminder',
            'Pengingat log bor',
            channelDescription: 'Getar bila log bor yang berjalan 45 menit belum ada bacaan baru',
            importance: i >= _drillIdleKeras ? Importance.max : Importance.high,
            priority: i >= _drillIdleKeras ? Priority.max : Priority.high,
            enableVibration: true,
            vibrationPattern: i >= _drillIdleKeras ? _buzzKeras : _buzz,
            category: AndroidNotificationCategory.reminder,
            actions: [
              // Satu-satunya jalan keluar yang sah. `showsUserInterface:
              // false` — dikerjakan di isolate latar tanpa membuka apa pun,
              // sama seperti "Selesai TM" dari arloji.
              AndroidNotificationAction(
                actionSnoozeDrill,
                L10n.current?.drillSnoozeAction ?? 'Diamkan sampai besok',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ],
          ),
        ),
      );
    }
  }

  static Future<void> cancelDrillIdleReminders(String logUuid) async {
    for (var i = 0; i < drillIdleCount; i++) {
      await _plugin.cancel(id: _drillIdleId(logUuid, i));
    }
  }

  static String _minutesText(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final l = L10n.current;
    if (m == 0) return l?.hoursText(h) ?? '$h jam';
    if (h == 0) return l?.minutesText(m) ?? '$m menit';
    return l?.hoursMinutesText(h, m) ?? '$h jam $m menit';
  }

  // -------------------------------------------------------------------------
  // Data not sent for a long time
  // -------------------------------------------------------------------------

  static const _unsentId = 7400;

  /// A phone that rarely gets signal can sit on a day's logs without anyone
  /// noticing. Rescheduled after every save and every sync from the OLDEST
  /// change still waiting: it fires 24 hours after that change, and every
  /// [unsentRepeat] after that while the app keeps finding it unsent.
  static const unsentAfter = Duration(hours: 24);
  static const unsentRepeat = Duration(hours: 3);

  static Future<void> scheduleUnsentReminder(DateTime oldestPending) async {
    var at = oldestPending.add(unsentAfter);
    final now = DateTime.now();
    if (!at.isAfter(now)) at = now.add(unsentRepeat);
    await _plugin.zonedSchedule(
      id: _unsentId,
      title: L10n.current?.unsentTitle ?? 'Ada data belum terkirim',
      body: L10n.current?.unsentBody(_dayTime(oldestPending)) ??
          'Sejak ${_dayTime(oldestPending)}. Buka TerraBot Field di tempat bersinyal supaya terkirim.',
      payload: '/queue',
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'unsent_reminder',
          'Data belum terkirim',
          channelDescription: 'Pengingat bila data lapangan lebih dari sehari belum terkirim',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
    );
  }

  static Future<void> cancelUnsentReminder() => _plugin.cancel(id: _unsentId);

  static String _dayTime(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.day}/${l.month} ${two(l.hour)}:${two(l.minute)}';
  }

  static Future<void> cancelPauseReminders() async {
    for (var i = 1; i <= _pauseReminderCount; i++) {
      await _plugin.cancel(id: _pauseReminderBase + i);
    }
  }
}
