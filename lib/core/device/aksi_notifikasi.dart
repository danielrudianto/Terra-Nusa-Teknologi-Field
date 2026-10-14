import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../app_context.dart';
import '../i18n.dart';
import '../util/format.dart';
import 'notifications.dart';

/// TOMBOL "SELESAI TM" DARI JAM TANGAN.
///
/// DIMINTA DANIEL, 14 Oktober 2026, sesudah app masuk Google Play: kru perlu
/// menutup TM dari arlojinya tanpa mengeluarkan HP dari saku.
///
/// BERJALAN DI ISOLATE TERSENDIRI, tanpa layar dan tanpa `BuildContext` —
/// sama seperti `callbackDispatcher` pada sinkron latar, dan membuka basis
/// datanya dengan cara yang sama lewat [AppContext.open]. Pola itu sudah
/// dipakai di aplikasi ini sejak awal; yang baru di sini hanya pemicunya.
///
/// YANG DITUTUP HANYA JAM SELESAINYA — DAN ITU DISENGAJA.
///
/// `_finishTruck` di layar cor melakukan lebih banyak: ia menanyakan
/// sounding muka beton sesudah tuang, memeriksa kelebihan volume, lalu
/// menawarkan mencabut tremie. Ketiganya menuntut orang dan layar.
///
/// Dijalankan diam-diam dari jam tanpa ketiganya, sounding sesudah tuang
/// tidak akan pernah terisi — dan dari sounding itulah tertanam tremie,
/// muka beton akhir, dan seluruh pemeriksaan volume dihitung. Satu ketukan
/// di arloji akan diam-diam melubangi rantai bukti yang justru menjadi
/// seluruh nilai aplikasi ini.
///
/// Karena itu yang dibagi dua: JAM SELESAI diambil sekarang — ia tidak
/// dapat dipulihkan belakangan, sebab tidak ada yang ingat menit keberapa
/// tuangnya berhenti — dan SOUNDING-nya dikejar lewat pengingat bergetar
/// yang berbunyi sampai QS membukanya di HP. Sounding dapat diisi lima
/// menit kemudian; jam selesai tidak.
@pragma('vm:entry-point')
Future<void> tanganiAksiNotifikasiLatar(NotificationResponse r) async {
  if (r.actionId != Notifications.actionFinishNow) return;
  final uuid = _uuidDariRute(r.payload);
  if (uuid == null) return;

  // Sama dengan `callbackDispatcher` pada sinkron latar: isolate ini tidak
  // punya pengikat Flutter maupun pencatatan plugin sampai diminta sendiri.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final ctx = await AppContext.open();
  try {
    final pengguna = await ctx.session.user();
    if (pengguna == null) return;

    final akhir = DateTime.now();
    int? seqDitutup;
    final hasil = await ctx.db.mutateDocument(
      uuid: uuid,
      entity: 'casting',
      userId: pengguna.id,
      mutate: (d) {
        // TM YANG SEDANG DITUANG: punya `startAt`, belum punya `endAt`.
        //
        // Dicari dari isinya, bukan dari uuid yang dititipkan di muatan
        // notifikasi: notifikasi yang tertinggal dari TM sebelumnya akan
        // menutup TM yang salah, dan tidak ada satu pun pesan yang
        // mengatakannya.
        Map? berjalan;
        for (final x in (d['trucks'] as List? ?? const [])) {
          final m = x as Map;
          if (m['startAt'] != null && m['endAt'] == null) {
            final s = toIntOrNull(m['seq']) ?? 0;
            if (berjalan == null || s > (toIntOrNull(berjalan['seq']) ?? 0)) berjalan = m;
          }
        }
        if (berjalan == null) return;
        seqDitutup = toIntOrNull(berjalan['seq']) ?? 0;
        berjalan['endAt'] = isoWithOffset(akhir);
        // Jeda yang masih terbuka ikut ditutup, sama seperti di layar cor:
        // jeda tanpa akhir membuat lama tuang terhitung nol.
        for (final x in (d['pauses'] as List? ?? const [])) {
          final m = x as Map;
          if ('${m['truckSeq']}' == '$seqDitutup' && m['endAt'] == null) {
            m['endAt'] = isoWithOffset(akhir);
          }
        }
      },
    );

    // Tidak ada TM berjalan: notifikasinya basi. Dibersihkan, bukan
    // dibiarkan — tombol yang tidak mengerjakan apa-apa lebih buruk
    // daripada tombol yang hilang.
    if (hasil == null || seqDitutup == null) {
      await Notifications.clearStopwatch();
      return;
    }

    await Notifications.clearStopwatch();
    await Notifications.cancelTruckReminder();
    await Notifications.cancelPauseReminders();

    final l = L10n.current;
    await Notifications.showSoundingDue(
      route: '/casting/log/$uuid',
      title: l?.notifSoundingDue('$seqDitutup') ?? 'TM $seqDitutup selesai — sounding belum diisi',
      body: l?.notifSoundingDueBody ??
          'Buka log cor di HP dan isi sounding muka beton sesudah tuang. '
              'Tertanam tremie dan pemeriksaan volume dihitung dari angka itu.',
    );
  } finally {
    await ctx.close();
  }
}

/// `/casting/log/<uuid>` -> `<uuid>`. Null bila rutenya bukan log cor.
String? _uuidDariRute(String? rute) {
  const awalan = '/casting/log/';
  if (rute == null || !rute.startsWith(awalan)) return null;
  final sisa = rute.substring(awalan.length).split('?').first.split('/').first;
  return sisa.isEmpty ? null : sisa;
}
