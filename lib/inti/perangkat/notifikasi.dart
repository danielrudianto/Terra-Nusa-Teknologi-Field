import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifikasi stopwatch pengecoran.
///
/// Selama TM dicor, QS sibuk di lubang bor dan HP masuk saku. Notifikasi
/// tetap dengan jam berjalan (chronometer Android — dihitung sistem, tidak
/// butuh aplikasi tetap hidup) menunjukkan sudah berapa lama TM ini dicor,
/// dan tombol "Selesai TM" membawa langsung ke layar cor-nya.
class Notifikasi {
  Notifikasi._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _idStopwatch = 7001;
  static const aksiSelesaiTm = 'selesai_tm';

  /// `padaKetuk(payload, aksi)` — payload berisi rute tujuan.
  static Future<void> siapkan(void Function(String? payload, String? aksi) padaKetuk) async {
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => padaKetuk(r.payload, r.actionId),
    );
  }

  /// Android 13+: izin notifikasi diminta saat pertama dibutuhkan.
  static Future<void> mintaIzin() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Rute yang membuka aplikasi lewat notifikasi (aplikasi tadinya mati).
  static Future<String?> ruteAwal() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d == null || !d.didNotificationLaunchApp) return null;
    return d.notificationResponse?.payload;
  }

  static Future<void> tampilkanStopwatch({
    required String rute,
    required String judul,
    required String isi,
    required DateTime mulai,
  }) {
    return _plugin.show(
      id: _idStopwatch,
      title: judul,
      body: isi,
      payload: rute,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'pengecoran',
          'Pengecoran berjalan',
          channelDescription: 'Stopwatch TM yang sedang dicor',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: true,
          when: mulai.millisecondsSinceEpoch,
          usesChronometer: true,
          category: AndroidNotificationCategory.stopwatch,
          actions: const [
            AndroidNotificationAction(aksiSelesaiTm, 'Selesai TM', showsUserInterface: true),
          ],
        ),
      ),
    );
  }

  static Future<void> hapusStopwatch() => _plugin.cancel(id: _idStopwatch);
}
