import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../config/env.dart';
import '../network/api_client.dart';
import '../util/app_log.dart';
import 'notifications.dart';

/// Pesan dari SERVER ke HP ini (Firebase Cloud Messaging).
///
/// Bedanya dengan [Notifications]: yang di sana dipicu oleh kejadian DI HP
/// INI — arloji cor milik QS yang sedang menuang, pengingat sounding. Yang
/// di sini dipicu kejadian di SERVER, yang dikerjakan HP ORANG LAIN:
/// "SP.B56 mulai dicor 13:35 — R501." Sebelum berkas ini ada, aplikasi
/// lapangan tidak punya jalur apa pun untuk hal semacam itu; satu-satunya
/// cara mengetahuinya adalah membuka aplikasinya dan melihat sendiri.
///
/// SIAPA MENERIMA APA ditentukan SERVER, bukan di sini. HP mendaftarkan
/// tokennya; yang memutuskan "kabar ini untuk direktur" adalah
/// `_kabari_mulai` di server. Jadi tidak ada penyaringan di berkas ini, dan
/// memang tidak boleh ada — penyaringan di dua tempat berarti satu
/// pemberitahuan dapat hilang di tempat yang tidak dicurigai siapa pun.
///
/// TIDAK ADA ISOLATE LATAR, DAN ITU DISENGAJA
///
/// Server mengirim muatan ber-`notification`, sehingga saat aplikasi di
/// latar atau mati ANDROID SENDIRI yang menampilkan notifikasinya — tanpa
/// satu baris Dart pun ikut berjalan. Mendaftarkan
/// `FirebaseMessaging.onBackgroundMessage` hanya akan menambah satu
/// isolate yang harus menyiapkan ulang seluruh aplikasi (basis data,
/// sesi, zona waktu) untuk pekerjaan yang sudah dikerjakan Android. Itu
/// permukaan kegagalan baru tanpa satu pun manfaat.
///
/// Yang DIKERJAKAN Dart hanya dua hal: menampilkan kabar saat aplikasinya
/// sedang DI DEPAN (Android tidak menampilkan apa pun dalam keadaan itu),
/// dan membuka layar yang benar saat notifikasinya diketuk.
class PesanAwan {
  PesanAwan._();

  static bool _siap = false;
  static String? _token;

  /// ApiClient terakhir yang dipakai, dan apakah ADA YANG SEDANG MASUK.
  ///
  /// Dibutuhkan karena tokennya tidak lagi datang sebagai kembalian,
  /// melainkan lewat aliran `onRegistered` — kapan saja, dan lazimnya
  /// SESUDAH `main()` selesai memanggil [pastikanTerdaftar]. Tanpa
  /// keduanya, pendaftaran pertama pada HP yang baru memasang aplikasi
  /// tidak pernah terjadi sampai orangnya kebetulan menutup lalu membuka
  /// aplikasinya lagi — dan di lapangan itu bisa berarti berhari-hari.
  static ApiClient? _api;
  static bool _bolehDaftar = false;

  /// Token yang SUDAH tercatat di server, beserta atas nama siapa.
  ///
  /// Dipakai [pastikanTerdaftar] supaya pemanggilan berulang — tiap kali
  /// aplikasi kembali ke depan — tidak menjadi satu permintaan jaringan
  /// setiap kali. Disimpan di memori saja: pendaftaran ulang sesudah
  /// aplikasi dimatikan memang yang diinginkan, sebab barisnya di server
  /// bisa hilang tanpa HP ini tahu.
  static String? _terdaftar;

  /// Token FCM HP ini, bila sudah didapat. Null berarti FCM tidak jalan di
  /// HP ini — lihat [siapkan].
  static String? get token => _token;

  /// Siapkan Firebase, minta izin, dan pasang penangan pesannya.
  ///
  /// TIDAK PERNAH MELEMPAR. HP lapangan tanpa Google Play Services — merek
  /// rugged tertentu, HP yang layanan Google-nya dimatikan — membuat
  /// `register()` gagal, dan kegagalan itu TIDAK BOLEH menjatuhkan
  /// aplikasinya saat mulai. Yang hilang hanya kabar dari server; absensi,
  /// log cor, arloji, dan pengingat tetap jalan seluruhnya.
  ///
  /// [buka] dipanggil dengan rute tujuan saat notifikasinya diketuk SAAT
  /// APLIKASI SUDAH JALAN. Ketukan yang MELUNCURKAN aplikasi dari mati
  /// tidak lewat sana melainkan dikembalikan sebagai hasil fungsi ini:
  /// pada saat ini dipanggil, `runApp` belum terjadi dan router-nya belum
  /// punya pohon widget untuk berpindah ke mana pun — persis seperti
  /// `Notifications.initialRoute()`, yang ditangani dengan cara yang sama
  /// di `main()`.
  ///
  /// Kembalian: rute dari notifikasi yang meluncurkan aplikasi, atau null.
  static Future<String?> siapkan({
    required void Function(String rute) buka,
  }) async {
    try {
      await Firebase.initializeApp();

      // Izin notifikasi Android 13+ diminta lewat [Notifications], bukan
      // lewat `FirebaseMessaging.requestPermission`. Keduanya meminta izin
      // sistem yang SAMA, dan memanggil dua-duanya berarti dua dialog
      // untuk satu izin pada HP yang belum pernah memberikannya.
      await Notifications.requestPermission();

      final messaging = FirebaseMessaging.instance;

      // Aplikasi DI DEPAN: Android tidak menampilkan apa pun, jadi
      // ditampilkan sendiri.
      FirebaseMessaging.onMessage.listen((pesan) {
        final rute = pesan.data['rute']?.toString() ?? '/';
        final n = pesan.notification;
        if (n == null) return;
        unawaited(
          Notifications.showKabar(
            route: rute,
            title: n.title ?? 'TerraBot',
            body: n.body ?? '',
            // Satu titik satu baris. Bukan `tag` kiriman servernya —
            // `tag` dipakai Android saat ia menampilkan sendiri, dan
            // yang ini dipakai saat APLIKASI menampilkan; keduanya tidak
            // pernah menampilkan kabar yang sama, jadi cukup masing-masing
            // tetap sama untuk titik dan jenis pekerjaan yang sama.
            kunci: '${pesan.data['jenis']}-${pesan.data['titikId']}',
          ).catchError((_) {}),
        );
      });

      // DIKETUK saat aplikasinya masih hidup di latar.
      FirebaseMessaging.onMessageOpenedApp.listen((pesan) {
        final rute = pesan.data['rute']?.toString();
        if (rute != null && rute.startsWith('/')) buka(rute);
      });

      // DIKETUK saat aplikasinya mati sama sekali. Dibaca SEKALI di sini;
      // pembacaan kedua mengembalikan null.
      final awal = await messaging.getInitialMessage();
      final ruteAwal = awal?.data['rute']?.toString();

      // TOKEN DATANG LEWAT ALIRAN, BUKAN SEBAGAI KEMBALIAN.
      //
      // `getToken()` dulu memberikannya langsung; sejak
      // firebase_messaging 17 ia usang dan digantikan `register()` yang
      // tidak mengembalikan apa pun — tokennya muncul di `onRegistered`.
      // Aliran yang SAMA juga dipakai saat Firebase MEMUTAR token tanpa
      // diminta (data aplikasi dibersihkan, aplikasi dipasang ulang,
      // token kedaluwarsa), jadi satu penangan menangani dua-duanya.
      //
      // DIPASANG SEBELUM `register()`, bukan sesudah: kalau sebaliknya,
      // token yang datang cepat terbit sebelum ada yang mendengarkan dan
      // hilang tanpa jejak.
      messaging.onRegistered.listen((baru) {
        _token = baru;
        _terdaftar = null;
        AppLog.info('fcm', 'token diterima');
        // Pendaftarannya dikerjakan DI SINI juga, bukan hanya di
        // pemanggil: saat `main()` memanggil `pastikanTerdaftar`,
        // tokennya lazimnya belum ada.
        final api = _api;
        if (_bolehDaftar && api != null) unawaited(pastikanTerdaftar(api));
      });

      // Disetel sebelum `register()` supaya penangan di atas — yang dapat
      // berjalan seketika — tidak ditolak oleh penjaga `_siap` di
      // [pastikanTerdaftar].
      _siap = true;

      // TIDAK DI-`await`, DAN ITU PENTING.
      //
      // `siapkan()` dipanggil `main()` SEBELUM `runApp`. `register()`
      // menghubungi Firebase lewat jaringan; di lokasi tanpa sinyal ia
      // dapat menggantung lama, dan menunggunya di sini berarti aplikasi
      // tertahan di layar kosong karena notifikasi — fitur yang paling
      // tidak penting saat kru justru sedang menunggu bisa mencatat.
      //
      // Hasilnya memang tidak dibutuhkan: tokennya datang lewat
      // `onRegistered` kapan pun ia siap, dan penangannya sudah terpasang
      // di atas.
      unawaited(
        messaging.register().catchError((Object e, StackTrace st) {
          AppLog.error('fcm', 'register gagal: $e', st);
        }),
      );

      return (ruteAwal != null && ruteAwal.startsWith('/')) ? ruteAwal : null;
    } catch (e, st) {
      // Dicatat, bukan dilempar: lihat catatan pada dokumentasi fungsi ini.
      AppLog.error('fcm', 'tidak dapat disiapkan: $e', st);
      return null;
    }
  }

  /// Pastikan token HP ini tercatat di server atas nama pengguna sekarang.
  ///
  /// Aman dipanggil berulang-ulang, dan memang dipanggil begitu: saat
  /// mulai, sesudah masuk, dan setiap kali aplikasi kembali ke depan.
  /// Pemanggilan yang kedua tidak menyentuh jaringan selama tokennya belum
  /// berganti.
  ///
  /// KEGAGALANNYA DITELAN. HP lapangan kerap tanpa sinyal saat dibuka, dan
  /// pendaftaran token bukan hal yang boleh menghentikan apa pun; yang
  /// gagal dicoba lagi pada kesempatan berikutnya — itulah sebabnya
  /// fungsi ini dipanggil juga dari `didChangeAppLifecycleState`.
  static Future<void> pastikanTerdaftar(ApiClient api) async {
    // Diingat SEBELUM penjaga di bawah: pemanggilan yang pulang lebih awal
    // karena tokennya belum ada tetap menyatakan "ada yang sedang masuk",
    // dan itulah yang dipakai `onRegistered` saat tokennya akhirnya tiba.
    _api = api;
    _bolehDaftar = true;
    if (!_siap) return;
    final t = _token;
    if (t == null || t == _terdaftar) return;
    try {
      await api.registerPushToken(
        token: t,
        platform: Platform.isIOS ? 'ios' : 'android',
        appVersion: Env.appVersion,
      );
      _terdaftar = t;
      AppLog.info('fcm', 'token terdaftar');
    } catch (e) {
      // Tidak ada sinyal, atau sesi belum sah. Dicoba lagi nanti.
      AppLog.info('fcm', 'token belum terdaftar: $e');
    }
  }

  /// Cabut token HP ini — dipanggil SEBELUM `ApiClient.logout()`.
  ///
  /// Satu HP lapangan dipakai berganti-ganti orang, dan token FCM melekat
  /// pada PEMASANGAN aplikasi, bukan pada akun. Tanpa pencabutan ini, HP
  /// yang sudah diserahkan ke orang lain tetap membunyikan kabar untuk
  /// pemegang sebelumnya sampai ada orang yang masuk di HP itu.
  static Future<void> cabut(ApiClient api) async {
    final t = _token;
    _terdaftar = null;
    // Tanpa ini, token yang diputar Firebase sesudah orangnya keluar akan
    // didaftarkan ulang sendiri atas nama yang sudah keluar.
    _bolehDaftar = false;
    if (t == null) return;
    try {
      await api.unregisterPushToken(t);
    } catch (e) {
      // Keluar tetap terjadi di HP walau servernya tidak terjangkau —
      // sama seperti `ApiClient.logout()`. Barisnya akan berpindah
      // pemilik saat orang berikutnya masuk di HP ini.
      AppLog.info('fcm', 'token gagal dicabut: $e');
    }
  }
}
