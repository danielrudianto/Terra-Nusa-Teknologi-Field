import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'db/database.dart';
import 'jaringan/api.dart';
import 'perangkat/id_perangkat.dart';
import 'sesi/sesi.dart';
import 'sinkron/mesin_sinkron.dart';

/// Semua yang dibutuhkan untuk berbicara dengan server dan basis data lokal.
///
/// Dibuat di DUA tempat: `main()` untuk layar, dan pekerja latar untuk
/// sinkron berkala. Keduanya harus merakitnya dengan cara yang SAMA —
/// itulah alasan perakitannya ada di satu fungsi ini, bukan ditulis dua kali.
class KonteksAplikasi {
  KonteksAplikasi._({
    required this.db,
    required this.sesi,
    required this.api,
    required this.mesin,
    required this.idPerangkat,
  });

  final BasisData db;
  final PenyimpanSesi sesi;
  final KlienApi api;
  final MesinSinkron mesin;
  final String idPerangkat;

  static Future<KonteksAplikasi> buka() async {
    const simpan = FlutterSecureStorage();
    final id = await idPerangkat(simpan);
    final db = BasisData();
    final sesi = PenyimpanSesi(simpan);
    final api = KlienApi(db: db, sesi: sesi, idPerangkat: id);
    final mesin = MesinSinkron(db: db, api: api, sesi: sesi);
    return KonteksAplikasi._(db: db, sesi: sesi, api: api, mesin: mesin, idPerangkat: id);
  }

  Future<void> tutup() => db.close();
}
