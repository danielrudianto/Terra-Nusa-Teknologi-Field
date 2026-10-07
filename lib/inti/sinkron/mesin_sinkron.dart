import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:jam_monoton/jam_monoton.dart';

import '../db/database.dart';
import '../jaringan/api.dart';
import '../jaringan/galat.dart';
import '../konfigurasi/env.dart';
import '../sesi/sesi.dart';
import '../util/format.dart';

/// Ringkasan satu putaran sinkron — untuk banner di Beranda dan log latar.
class HasilSinkron {
  HasilSinkron();

  int terkirim = 0;
  int tertunda = 0;
  int ditolak = 0;
  int gagal = 0;
  int fotoTerkirim = 0;
  int fotoDitolak = 0;
  bool ditarik = false;

  /// Kunci sinkron dipegang isolate lain (layar vs latar) — bukan galat.
  bool sibuk = false;
  bool sesiHabis = false;
  bool tanpaJaringan = false;
  String? galat;

  bool get berhasil => galat == null && !sesiHabis && !tanpaJaringan && !sibuk;

  @override
  String toString() => 'terkirim $terkirim, tertunda $tertunda, ditolak $ditolak, gagal $gagal, '
      'foto $fotoTerkirim/$fotoDitolak, tarik $ditarik${galat == null ? '' : ', galat: $galat'}';
}

/// Mesin sinkron: KIRIM dokumen → KIRIM foto → TARIK data induk.
///
/// URUTANNYA DISENGAJA
///
/// 1. Dokumen dulu. Absen beberapa ratus byte; foto puluhan kB. Di sinyal
///    satu batang, absen yang ringan harus sudah masuk sebelum foto mulai
///    menghabiskan waktu. Server menandai `FOTO_BELUM_MASUK` selama fotonya
///    menyusul, dan tanda itu hilang sendiri saat fotonya tiba.
/// 2. Foto, satu per permintaan — gagal satu tidak mengulang yang lain.
/// 3. Tarik terakhir, supaya status yang ditarik sudah mencakup kiriman
///    barusan (mis. titik yang baru ditandai sudah dibor).
///
/// SATU SAJA SEKALIGUS
///
/// Layar (tombol "Kirim sekarang") dan pekerja latar dapat berjalan
/// bersamaan di isolate berbeda. Tanpa kunci, keduanya mengambil antrean
/// yang SAMA dan mengirimnya dua kali. Server memang aman terhadap itu
/// (versi yang sama dijawab `duplikat`), tetapi kuota data mandor tidak.
class MesinSinkron {
  MesinSinkron({required this.db, required this.api, required this.sesi});

  final BasisData db;
  final KlienApi api;
  final PenyimpanSesi sesi;

  static const _masaKunci = Duration(minutes: 3);
  static const _putaranKirimMaks = 20;
  static const _halamanTarikMaks = 20;

  Dio get _dio => api.dio;

  Future<HasilSinkron> jalankan({bool kirim = true, bool tarik = true}) async {
    final hasil = HasilSinkron();
    final pengguna = await sesi.pengguna();
    if (pengguna == null || await sesi.aksesToken() == null) {
      hasil.sesiHabis = true;
      return hasil;
    }
    if (await sesi.sesiHabis()) {
      hasil.sesiHabis = true;
      return hasil;
    }

    final pemilik = uuidBaru();
    if (!await db.ambilKunci('sinkron', pemilik, _masaKunci)) {
      hasil.sibuk = true;
      return hasil;
    }
    try {
      if (kirim) {
        await _kirimDokumen(pengguna.id, pemilik, hasil);
        await _kirimFoto(pengguna.id, pemilik, hasil);
      }
      if (tarik) await _tarik(pengguna.id, pemilik, hasil);
      await db.tulisMeta('sinkron_terakhir', isoBerzona(DateTime.now()));
    } on GalatApi catch (e) {
      if (e.sesiHabis) {
        hasil.sesiHabis = true;
      } else if (e.tanpaJaringan) {
        hasil.tanpaJaringan = true;
      } else {
        hasil.galat = e.pesan;
      }
    } catch (e) {
      hasil.galat = e.toString();
    } finally {
      await db.lepasKunci('sinkron', pemilik);
    }
    if (hasil.galat != null) await db.tulisMeta('sinkron_galat', hasil.galat);
    return hasil;
  }

  /// Perpanjang kunci di sela putaran yang panjang (unggah foto di sinyal
  /// lemah dapat melewati masa kunci).
  Future<void> _perpanjang(String pemilik) => db.ambilKunci('sinkron', pemilik, _masaKunci);

  // -------------------------------------------------------------------------
  // Kirim dokumen
  // -------------------------------------------------------------------------

  Future<void> _kirimDokumen(int userId, String pemilik, HasilSinkron hasil) async {
    for (var putaran = 0; putaran < _putaranKirimMaks; putaran++) {
      final antrean = await db.antreanKirim(userId, batas: Env.itemPerKiriman);
      if (antrean.isEmpty) return;
      await _perpanjang(pemilik);

      final jamHp = await JamMonoton.ambil();
      final badan = <String, Object?>{
        'sentAtDevice': isoBerzona(DateTime.now()),
        'sentElapsedMs': jamHp?.elapsedMs,
        'bootCount': jamHp?.bootCount,
        'items': [
          for (final d in antrean)
            {
              'entity': d.entitas,
              'uuid': d.uuid,
              'version': d.versi,
              'data': jsonDecode(d.isi),
            },
        ],
      };

      final Map<String, dynamic> jawaban;
      try {
        final r = await _dio.post<Map<String, dynamic>>('/field/sync/push', data: badan);
        jawaban = r.data ?? const {};
      } catch (e) {
        throw GalatApi.dari(e);
      }

      final perUuid = <String, Map<String, Object?>>{};
      for (final h in (jawaban['results'] as List?) ?? const []) {
        final m = (h as Map).cast<String, Object?>();
        perUuid['${m['uuid']}'] = m;
      }

      var adaKemajuan = false;
      for (final d in antrean) {
        final h = perUuid[d.uuid];
        // Tidak ada jawaban untuk item ini = anggap gagal, coba lagi nanti.
        final status = (h?['status'] ?? 'gagal').toString();
        await db.catatJawaban(
          uuid: d.uuid,
          versiDikirim: d.versi,
          status: status,
          alasan: h?['reason']?.toString(),
          detail: h?['detail']?.toString(),
          penanda: h?['flags'] == null ? null : jsonEncode(h!['flags']),
          serverId: keInt(h?['id']),
        );
        switch (status) {
          case 'ok' || 'duplikat':
            hasil.terkirim++;
            adaKemajuan = true;
          case 'tertunda':
            hasil.tertunda++;
          case 'ditolak':
            hasil.ditolak++;
            adaKemajuan = true; // keluar dari antrean, bukan macet
          default:
            hasil.gagal++;
        }
      }
      // Semua gagal/tertunda: sudah diberi jeda, putaran berikutnya hanya
      // akan mengambil sisa yang belum dicoba — atau kosong.
      if (!adaKemajuan && antrean.length < Env.itemPerKiriman) return;
    }
  }

  // -------------------------------------------------------------------------
  // Kirim foto
  // -------------------------------------------------------------------------

  Future<void> _kirimFoto(int userId, String pemilik, HasilSinkron hasil) async {
    for (var putaran = 0; putaran < 10; putaran++) {
      final antrean = await db.antreanFoto(userId);
      if (antrean.isEmpty) return;
      for (final f in antrean) {
        await _perpanjang(pemilik);
        await _unggahSatu(f, hasil);
      }
      if (antrean.length < 20) return;
    }
  }

  Future<void> _unggahSatu(BarisFoto f, HasilSinkron hasil) async {
    final berkas = File(f.path);
    if (!await berkas.exists()) {
      // Berkas hilang (dibersihkan sistem / aplikasi dipasang ulang).
      // Tidak ada yang dapat dikirim lagi; tandai ditolak supaya antrean
      // tidak macet, dan server tetap menandai FOTO_BELUM_MASUK.
      await db.catatFoto(f.uuid, status: 'ditolak', alasan: 'BERKAS_HILANG');
      hasil.fotoDitolak++;
      return;
    }
    final isi = await berkas.readAsBytes();
    try {
      await _dio.put<dynamic>(
        '/field/photos/${f.uuid}',
        data: Stream<List<int>>.value(isi),
        options: Options(
          contentType: 'image/jpeg',
          sendTimeout: const Duration(minutes: 2),
          headers: {
            Headers.contentLengthHeader: isi.length,
            'X-Photo-Kind': f.jenis,
            'X-Photo-Sha256': f.sha256,
            'X-Photo-Taken-At': isoBerzona(f.diambil),
            if (f.jumlahWajah != null) 'X-Photo-Face-Count': '${f.jumlahWajah}',
            if (f.lat != null) 'X-Photo-Lat': f.lat!.toStringAsFixed(7),
            if (f.lng != null) 'X-Photo-Lng': f.lng!.toStringAsFixed(7),
          },
        ),
      );
      await db.catatFoto(f.uuid, status: 'terkirim');
      hasil.fotoTerkirim++;
    } catch (e) {
      final g = GalatApi.dari(e);
      if (g.tanpaJaringan || g.sesiHabis) throw g;
      final s = g.status ?? 0;
      if (s >= 400 && s < 500 && s != 408 && s != 429) {
        // Ditolak karena isinya (bukan JPEG, terlalu besar, uuid bentrok,
        // tidak berhak): mengulang tidak akan mengubah jawabannya.
        await db.catatFoto(f.uuid, status: 'ditolak', alasan: g.kode ?? g.pesan);
        hasil.fotoDitolak++;
      } else {
        await db.catatFoto(f.uuid, status: 'gagal', alasan: g.pesan);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Tarik
  // -------------------------------------------------------------------------

  Future<void> _tarik(int userId, String pemilik, HasilSinkron hasil) async {
    final kunciKursor = 'kursor:$userId';
    var kursor = await db.bacaMeta(kunciKursor);
    for (var halaman = 0; halaman < _halamanTarikMaks; halaman++) {
      await _perpanjang(pemilik);
      final Map<String, dynamic> d;
      try {
        final r = await _dio.get<Map<String, dynamic>>(
          '/field/sync/pull',
          queryParameters: {if (kursor != null && kursor.isNotEmpty) 'cursor': kursor},
        );
        d = r.data ?? const {};
      } catch (e) {
        throw GalatApi.dari(e);
      }

      await db.transaction(() async {
        final proyek = d['projects'];
        if (proyek is List) {
          await db.gantiSemuaProyek([for (final p in proyek) (p as Map).cast<String, Object?>()]);
        }
        for (final w in (d['workers'] as List?) ?? const []) {
          final m = (w as Map).cast<String, Object?>();
          await db.gantiInduk('pekerja', '${m['uuid']}', m, terhapus: m['isDelete'] == true);
        }
        for (final t in (d['pilePoints'] as List?) ?? const []) {
          final m = (t as Map).cast<String, Object?>();
          await db.gantiInduk('titik', '${m['uuid']}', m, terhapus: m['isDelete'] == true);
        }
        for (final a in (d['attendanceStatus'] as List?) ?? const []) {
          final m = (a as Map).cast<String, Object?>();
          await db.catatStatusServer('${m['uuid']}', '${m['status']}', m['reviewNote']?.toString());
        }
        for (final c in (d['castingStatus'] as List?) ?? const []) {
          final m = (c as Map).cast<String, Object?>();
          await db.catatStatusServer('${m['uuid']}', '${m['status']}', m['note']?.toString());
        }
        kursor = d['cursor']?.toString();
        await db.tulisMeta(kunciKursor, kursor);
        final jamServer = d['serverTime']?.toString();
        if (jamServer != null) await db.tulisMeta('jam_server', '$jamServer|${DateTime.now().toIso8601String()}');
      });
      hasil.ditarik = true;
      if (d['hasMore'] != true) return;
    }
  }
}
