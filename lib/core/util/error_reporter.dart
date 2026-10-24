import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../config/env.dart';
import 'app_log.dart';

/// Satu catatan galat, sebagaimana dikirim ke `POST /error-logs`.
class _Entry {
  _Entry({
    this.fallbackKey,
    this.code,
    this.status,
    this.screen,
    this.expected = false,
    required this.clientAt,
  });

  final String? fallbackKey;
  final String? code;
  final int? status;
  final String? screen;
  final bool expected;
  final DateTime clientAt;

  Map<String, Object?> toJson() => {
        'surface': 'field',
        if (fallbackKey != null) 'fallbackKey': fallbackKey,
        if (code != null) 'code': code,
        if (status != null) 'status': status,
        if (screen != null) 'screen': screen,
        'expected': expected,
        'appVersion': Env.appVersion,
        if (ErrorReporter.deviceId != null) 'device': ErrorReporter.deviceId,
        'clientAt': clientAt.toIso8601String(),
      };

  static _Entry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse('${raw['clientAt']}');
    if (at == null) return null;
    return _Entry(
      fallbackKey: raw['fallbackKey'] as String?,
      code: raw['code'] as String?,
      status: raw['status'] as int?,
      screen: raw['screen'] as String?,
      expected: raw['expected'] == true,
      clientAt: at,
    );
  }
}

/// Mengirimkan galat yang SAMPAI KE MATA PENGGUNA ke server.
///
/// KENAPA ADA, padahal sudah ada [AppLog]
///
/// [AppLog] menulis ke berkas di HP ini, dan satu-satunya jalan keluarnya
/// tombol "Kirim log" di Setelan yang membagikannya lewat WhatsApp. Itu
/// PASIF: kabarnya datang hanya kalau ada yang mengeluh cukup keras untuk
/// menekan tombol itu — dan karena berkasnya membuang separuh tertuanya saat
/// penuh, keluhan yang datang tiga hari kemudian kerap sudah kehilangan
/// buktinya. Keterangan di [AppLog] menyebutnya sendiri: tidak ada layanan
/// pelaporan galat, dan mandor tidak dapat membaca logcat.
///
/// Yang ini AKTIF, dan dibatasi: hanya kode dan kuncinya, tidak pernah
/// kalimat pesannya. Pesan server kerap memuat nama orang, dan tabel di
/// server sengaja tidak punya kolom untuk itu.
///
/// ANTREANNYA DISIMPAN KE BERKAS, dan itu bukan kemewahan: galat di lapangan
/// terjadi justru di tempat tanpa sinyal, dan HP yang ditutup lalu dibuka
/// lagi besok pagi akan kehilangan seluruh antrean memorinya — yaitu
/// kehilangan tepat galat yang paling tidak terlihat dari kantor.
///
/// STATIS, seperti [AppLog]: ia dipanggil dari `ApiError.from`, sebuah
/// pabrik model yang tidak punya dan tidak boleh punya wadah suntikan.
class ErrorReporter {
  ErrorReporter._();

  /// Perangkat ini. Dipasang sekali oleh `AppContext.create()`.
  static String? deviceId;

  /// Batas antrean. Di atas ini yang BARU dibuang, bukan yang lama: pada
  /// rentetan kegagalan, yang pertama biasanya sebabnya dan sisanya akibat.
  static const _maxQueue = 200;

  /// Kejadian yang sama persis diabaikan selama ini.
  static const _dedupe = Duration(seconds: 30);

  /// Sekali kirim paling banyak sebanyak ini — sama dengan batas server.
  static const _perFlush = 50;

  static final List<_Entry> _queue = [];
  static final Map<String, DateTime> _lastSeen = {};
  static File? _file;
  static bool _loaded = false;
  static bool _sending = false;

  static Future<File> _berkas() async {
    final f = _file;
    if (f != null) return f;
    final dir = await getApplicationSupportDirectory();
    return _file = File('${dir.path}/terrabot-galat.json');
  }

  /// Catat satu galat. Kembali segera; pengirimannya menyusul saat sinkron.
  ///
  /// TIDAK PERNAH MELEMPAR. Dipanggil ketika sesuatu SUDAH gagal, dan
  /// melempar di sini berarti menukar satu kegagalan dengan dua.
  static void record({
    String? fallbackKey,
    String? code,
    int? status,
    String? screen,
    bool expected = false,
  }) {
    try {
      final sidik = '${fallbackKey ?? ''}|${code ?? ''}|${status ?? ''}|${screen ?? ''}';
      final sekarang = DateTime.now();
      final terakhir = _lastSeen[sidik];
      if (terakhir != null && sekarang.difference(terakhir) < _dedupe) return;
      _lastSeen[sidik] = sekarang;
      if (_lastSeen.length > 200) _lastSeen.clear();

      if (_queue.length >= _maxQueue) return;
      _queue.add(_Entry(
        fallbackKey: fallbackKey,
        code: code,
        status: status,
        screen: screen,
        expected: expected,
        clientAt: sekarang,
      ));
      unawaited(_simpan());
    } catch (_) {
      // Mencatat galat tidak boleh menjadi galat.
    }
  }

  /// Tulis antrean ke berkas, supaya ia selamat dari HP yang ditutup.
  static Future<void> _simpan() async {
    try {
      final f = await _berkas();
      await f.writeAsString(
        jsonEncode(_queue.map((e) => e.toJson()).toList()),
        flush: false,
      );
    } catch (_) {
      // Penyimpanan penuh atau izin ditolak. Antrean memorinya tetap jalan.
    }
  }

  static Future<void> _muat() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _berkas();
      if (!await f.exists()) return;
      final isi = jsonDecode(await f.readAsString());
      if (isi is! List) return;
      for (final baris in isi) {
        final e = _Entry.fromJson(baris);
        if (e != null && _queue.length < _maxQueue) _queue.add(e);
      }
    } catch (_) {
      // Berkas rusak — dibuang, bukan dipertahankan: antrean yang tidak
      // dapat diurai akan menggagalkan setiap pengiriman sesudahnya.
      try {
        final f = await _berkas();
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Kirim antrean. Dipanggil dari `SyncEngine.run` saat sinkronnya berhasil
  /// — artinya sinyalnya ada dan tokennya sah, dua syarat yang sudah
  /// terbukti tanpa perlu diuji ulang di sini.
  static Future<void> flush(Dio dio) async {
    if (_sending) return;
    _sending = true;
    try {
      await _muat();
      while (_queue.isNotEmpty) {
        final kirim = _queue.take(_perFlush).toList();
        await dio.post('error-logs', data: {
          'entries': kirim.map((e) => e.toJson()).toList(),
        });
        /*
         * DIBUANG dari antrean meski server menjawab `accepted: 0`.
         *
         * Jawaban itu muncul ketika pembatas laju per pengguna sedang
         * penuh — yaitu saat ada badai galat. Dipertahankan untuk dicoba
         * lagi, antreannya tidak akan pernah habis selama badainya
         * berlangsung, dan catatan BARU yang mungkin menjelaskan sebabnya
         * ikut tertahan di belakangnya.
         *
         * Yang hilang karena ini adalah catatan ke-301 sampai seterusnya
         * dalam satu jam, pada layar yang sama, dari orang yang sama.
         * Tiga ratus yang pertama sudah sampai.
         */
        _queue.removeRange(0, kirim.length);
        await _simpan();
        if (kirim.length < _perFlush) break;
      }
    } catch (e) {
      // SENGAJA DIAM soal kegagalan kirimnya, dan tidak lewat `ApiError`:
      // jalur itu memanggil `record()`, dan melaporkan kegagalan pelaporan
      // adalah lingkaran yang tidak berujung. Antreannya tetap di berkas,
      // dan sinkron berikutnya mencobanya lagi.
      AppLog.info('galat', 'antrean galat belum terkirim (${_queue.length} baris)');
    } finally {
      _sending = false;
    }
  }
}
