import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

// ===========================================================================
// BENTUK PENYIMPANAN LOKAL — dan kenapa tidak satu tabel per entitas
//
// Server menerima DOKUMEN UTUH berversi: absen beserta semua baris
// pekerjanya, log cor beserta semua TM dan segmen tremienya. Jadi HP pun
// menyimpan dokumen utuh: satu baris di `Dokumen`, isinya JSON persis
// seperti yang akan dikirim.
//
// Akibat yang dibeli dengan bentuk ini:
//
//   * ANTREAN KIRIM TIDAK DAPAT TERLUPA. Menyimpan = menaikkan `versi`.
//     Yang belum terkirim = `versi > versiTerkirim`. Tidak ada tabel antrean
//     terpisah yang harus diisi bersamaan (dan suatu hari lupa diisi).
//
//   * Kiriman ulang aman: server menolak versi yang tidak lebih baru.
//
// Data induk dari server (proyek, pekerja, titik) disimpan di `Induk`,
// juga sebagai JSON — HP tidak menulisnya, hanya menggantinya dari tarikan.
// ===========================================================================

@DataClassName('BarisInduk')
class Induk extends Table {
  /// proyek | pekerja | titik
  TextColumn get entitas => text()();

  /// id server (proyek) atau uuid (pekerja, titik).
  TextColumn get kunci => text()();
  TextColumn get isi => text()();
  BoolColumn get terhapus => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {entitas, kunci};
}

@DataClassName('BarisDokumen')
class Dokumen extends Table {
  TextColumn get uuid => text()();

  /// worker | attendance | drill_mark | casting — sama dengan server.
  TextColumn get entitas => text()();

  /// Antrean terikat PENGGUNA. Bila orang lain masuk di HP yang sama,
  /// dokumen milik yang sebelumnya tidak dikirim atas namanya.
  IntColumn get userId => integer()();
  IntColumn get versi => integer().withDefault(const Constant(1))();
  IntColumn get versiTerkirim => integer().withDefault(const Constant(0))();
  TextColumn get isi => text()();

  /// lokal | terkirim | tertunda | ditolak | gagal
  TextColumn get statusKirim => text().withDefault(const Constant('lokal'))();
  TextColumn get alasan => text().nullable()();
  TextColumn get detail => text().nullable()();

  /// Penanda curang dari server (JSON), untuk banner di HP.
  TextColumn get penanda => text().nullable()();
  IntColumn get serverId => integer().nullable()();

  /// Status di server: dikirim/ditinjau/ditolak (absen),
  /// berjalan/selesai/diperiksa (cor). Diisi dari tarikan.
  TextColumn get statusServer => text().nullable()();
  TextColumn get catatanServer => text().nullable()();
  IntColumn get percobaan => integer().withDefault(const Constant(0))();
  DateTimeColumn get tundaSampai => dateTime().nullable()();
  DateTimeColumn get dibuat => dateTime()();
  DateTimeColumn get diubah => dateTime()();

  @override
  Set<Column> get primaryKey => {uuid};
}

@DataClassName('BarisFoto')
class Foto extends Table {
  TextColumn get uuid => text()();

  /// wajah | absen_masuk | absen_pulang | tiket_tm
  TextColumn get jenis => text()();
  TextColumn get path => text()();
  TextColumn get sha256 => text()();
  IntColumn get ukuran => integer()();
  IntColumn get jumlahWajah => integer().nullable()();
  DateTimeColumn get diambil => dateTime()();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  IntColumn get userId => integer()();

  /// lokal | terkirim | ditolak
  TextColumn get statusKirim => text().withDefault(const Constant('lokal'))();
  TextColumn get alasan => text().nullable()();
  IntColumn get percobaan => integer().withDefault(const Constant(0))();
  DateTimeColumn get tundaSampai => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {uuid};
}

@DataClassName('BarisMeta')
class MetaLokal extends Table {
  TextColumn get kunci => text()();
  TextColumn get nilai => text().nullable()();

  @override
  Set<Column> get primaryKey => {kunci};
}

/// Urutan kirim: pekerja dulu (dirujuk absen), tanda bor sebelum cor.
const urutanEntitas = {'worker': 0, 'drill_mark': 1, 'attendance': 2, 'casting': 3};

@DriftDatabase(tables: [Induk, Dokumen, Foto, MetaLokal])
class BasisData extends _$BasisData {
  BasisData([QueryExecutor? executor]) : super(executor ?? _buka());

  @override
  int get schemaVersion => 1;

  /// Dibagi antar-isolate: layar dan pekerja latar (workmanager) membuka
  /// berkas yang SAMA, lewat satu isolate drift.
  static QueryExecutor _buka() => driftDatabase(
        name: 'terrabot_field',
        native: const DriftNativeOptions(shareAcrossIsolates: true),
      );

  // -------------------------------------------------------------------------
  // Meta
  // -------------------------------------------------------------------------

  Future<String?> bacaMeta(String kunci) async {
    final baris = await (select(metaLokal)..where((t) => t.kunci.equals(kunci))).getSingleOrNull();
    return baris?.nilai;
  }

  Future<void> tulisMeta(String kunci, String? nilai) =>
      into(metaLokal).insertOnConflictUpdate(MetaLokalCompanion.insert(kunci: kunci, nilai: Value(nilai)));

  /// Kunci lintas-isolate berbatas waktu. `true` bila berhasil diambil.
  ///
  /// Dipakai untuk dua hal yang TIDAK BOLEH berjalan dua sekaligus: sinkron
  /// (layar dan latar bersamaan mengirim dokumen yang sama) dan penyegaran
  /// token (dua penyegaran serentak = token lama dipakai dua kali = seluruh
  /// sesi dicabut server).
  Future<bool> ambilKunci(String nama, String pemilik, Duration masa) {
    return transaction(() async {
      final kini = DateTime.now().millisecondsSinceEpoch;
      final ada = await bacaMeta('kunci:$nama');
      if (ada != null) {
        final bagian = ada.split('|');
        final habis = bagian.length == 2 ? int.tryParse(bagian[1]) ?? 0 : 0;
        if (bagian[0] != pemilik && habis > kini) return false;
      }
      await tulisMeta('kunci:$nama', '$pemilik|${kini + masa.inMilliseconds}');
      return true;
    });
  }

  Future<void> lepasKunci(String nama, String pemilik) async {
    await transaction(() async {
      final ada = await bacaMeta('kunci:$nama');
      if (ada != null && ada.split('|').first == pemilik) {
        await tulisMeta('kunci:$nama', null);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Induk
  // -------------------------------------------------------------------------

  Future<void> gantiInduk(String entitas, String kunci, Map<String, Object?> isi, {bool terhapus = false}) {
    return into(induk).insertOnConflictUpdate(
      IndukCompanion.insert(
        entitas: entitas,
        kunci: kunci,
        isi: jsonEncode(isi),
        terhapus: Value(terhapus),
      ),
    );
  }

  /// Proyek selalu dikirim UTUH — yang tidak ada di daftar baru dihapus.
  Future<void> gantiSemuaProyek(List<Map<String, Object?>> proyek) {
    return transaction(() async {
      await (delete(induk)..where((t) => t.entitas.equals('proyek'))).go();
      for (final p in proyek) {
        await gantiInduk('proyek', '${p['id']}', p);
      }
    });
  }

  /// Pengguna lain masuk di HP ini: data induk dan kursor tarikan dibuang
  /// supaya ditarik ulang menurut hak pengguna BARU (kru mandor A tidak
  /// boleh tampil di HP mandor B). Dokumen dan foto TIDAK disentuh —
  /// antrean pengguna lama tetap utuh dan terkirim bila ia masuk lagi.
  Future<void> gantiPengguna() {
    return transaction(() async {
      await delete(induk).go();
      await (delete(metaLokal)..where((t) => t.kunci.like('kursor%'))).go();
    });
  }

  Stream<List<Map<String, Object?>>> pantauInduk(String entitas) {
    final q = select(induk)
      ..where((t) => t.entitas.equals(entitas) & t.terhapus.equals(false));
    return q.watch().map((baris) => [for (final b in baris) _peta(b.isi)]);
  }

  Future<List<Map<String, Object?>>> daftarInduk(String entitas) async {
    final q = select(induk)
      ..where((t) => t.entitas.equals(entitas) & t.terhapus.equals(false));
    return [for (final b in await q.get()) _peta(b.isi)];
  }

  Future<Map<String, Object?>?> satuInduk(String entitas, String kunci) async {
    final b = await (select(induk)..where((t) => t.entitas.equals(entitas) & t.kunci.equals(kunci)))
        .getSingleOrNull();
    if (b == null || b.terhapus) return null;
    return _peta(b.isi);
  }

  // -------------------------------------------------------------------------
  // Dokumen
  // -------------------------------------------------------------------------

  /// Simpan dokumen = SATU tulisan yang sekaligus memasukkannya ke antrean.
  ///
  /// [versiServer] — untuk dokumen yang BERASAL dari server (mis. pekerja
  /// yang disunting dari HP): versi lokal pertamanya harus melewati versi
  /// server, kalau tidak server menjawab `duplikat` dan perubahannya
  /// diam-diam tidak dipakai.
  Future<void> simpanDokumen({
    required String uuid,
    required String entitas,
    required int userId,
    required Map<String, Object?> isi,
    int? versiServer,
  }) {
    return transaction(() async {
      final kini = DateTime.now();
      final ada = await satuDokumen(uuid);
      if (ada == null) {
        final dasar = versiServer ?? 0;
        await into(dokumen).insert(
          DokumenCompanion.insert(
            uuid: uuid,
            entitas: entitas,
            userId: userId,
            isi: jsonEncode(isi),
            versi: Value(dasar + 1),
            versiTerkirim: Value(dasar),
            dibuat: kini,
            diubah: kini,
          ),
        );
      } else {
        await (update(dokumen)..where((t) => t.uuid.equals(uuid))).write(
          DokumenCompanion(
            isi: Value(jsonEncode(isi)),
            versi: Value(ada.versi + 1),
            statusKirim: const Value('lokal'),
            alasan: const Value(null),
            detail: const Value(null),
            percobaan: const Value(0),
            tundaSampai: const Value(null),
            diubah: Value(kini),
          ),
        );
      }
    });
  }

  Future<BarisDokumen?> satuDokumen(String uuid) =>
      (select(dokumen)..where((t) => t.uuid.equals(uuid))).getSingleOrNull();

  Stream<BarisDokumen?> pantauSatuDokumen(String uuid) =>
      (select(dokumen)..where((t) => t.uuid.equals(uuid))).watchSingleOrNull();

  /// Buang dokumen yang DITOLAK dari HP (mandor memilih tidak memperbaikinya).
  /// Hanya yang ditolak atau belum pernah terkirim sama sekali.
  Future<void> buangDokumen(String uuid) => (delete(dokumen)
        ..where((t) => t.uuid.equals(uuid) & (t.statusKirim.equals('ditolak') | t.versiTerkirim.equals(0))))
      .go();

  /// Kirim ulang yang ditolak SETELAH diperbaiki di tempat lain (mis. admin
  /// mengisi mutu beton proyek). Versi dinaikkan supaya server memprosesnya.
  Future<void> cobaLagiDokumen(String uuid) {
    return transaction(() async {
      final ada = await satuDokumen(uuid);
      if (ada == null) return;
      await (update(dokumen)..where((t) => t.uuid.equals(uuid))).write(
        DokumenCompanion(
          versi: Value(ada.versi + 1),
          statusKirim: const Value('lokal'),
          alasan: const Value(null),
          detail: const Value(null),
          percobaan: const Value(0),
          tundaSampai: const Value(null),
          diubah: Value(DateTime.now()),
        ),
      );
    });
  }

  /// Semua dokumen yang belum selesai urusannya, untuk layar Antrean.
  Stream<List<BarisDokumen>> pantauAntrean(int userId) {
    final q = select(dokumen)
      ..where((t) =>
          t.userId.equals(userId) &
          (t.versi.isBiggerThan(t.versiTerkirim) | t.statusKirim.isIn(const ['ditolak', 'tertunda', 'gagal'])))
      ..orderBy([(t) => OrderingTerm.desc(t.diubah)]);
    return q.watch();
  }

  Stream<List<BarisFoto>> pantauFotoBelumTerkirim(int userId) {
    final q = select(foto)
      ..where((t) => t.userId.equals(userId) & t.statusKirim.isNotIn(const ['terkirim']))
      ..orderBy([(t) => OrderingTerm.desc(t.diambil)]);
    return q.watch();
  }

  Stream<List<BarisDokumen>> pantauDokumen(String entitas, int userId) {
    final q = select(dokumen)
      ..where((t) => t.entitas.equals(entitas) & t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.desc(t.diubah)]);
    return q.watch();
  }

  /// Yang menunggu dikirim untuk pengguna ini, dalam urutan aman.
  Future<List<BarisDokumen>> antreanKirim(int userId, {int batas = 50}) async {
    final kini = DateTime.now();
    final q = select(dokumen)
      ..where((t) =>
          t.userId.equals(userId) &
          t.versi.isBiggerThan(t.versiTerkirim) &
          t.statusKirim.isNotIn(const ['ditolak']) &
          (t.tundaSampai.isNull() | t.tundaSampai.isSmallerOrEqualValue(kini)))
      ..orderBy([(t) => OrderingTerm.asc(t.dibuat)]);
    final semua = await q.get();
    semua.sort((a, b) {
      final ua = urutanEntitas[a.entitas] ?? 9;
      final ub = urutanEntitas[b.entitas] ?? 9;
      return ua != ub ? ua.compareTo(ub) : a.dibuat.compareTo(b.dibuat);
    });
    return semua.take(batas).toList();
  }

  Stream<int> pantauJumlahBelumTerkirim(int userId) {
    final jumlah = dokumen.uuid.count();
    final q = selectOnly(dokumen)
      ..addColumns([jumlah])
      ..where(dokumen.userId.equals(userId) &
          dokumen.versi.isBiggerThan(dokumen.versiTerkirim) &
          dokumen.statusKirim.isNotIn(const ['ditolak']));
    return q.watchSingle().map((r) => r.read(jumlah) ?? 0);
  }

  Stream<int> pantauJumlahDitolak(int userId) {
    final jumlah = dokumen.uuid.count();
    final q = selectOnly(dokumen)
      ..addColumns([jumlah])
      ..where(dokumen.userId.equals(userId) & dokumen.statusKirim.equals('ditolak'));
    return q.watchSingle().map((r) => r.read(jumlah) ?? 0);
  }

  /// Catat jawaban server atas SATU dokumen.
  ///
  /// `versiDikirim` — versi yang dikirim. Bila dokumen diubah lagi selama
  /// kiriman di perjalanan (versinya kini lebih besar), yang ditandai
  /// terkirim hanya versi itu; perubahan sesudahnya tetap di antrean.
  Future<void> catatJawaban({
    required String uuid,
    required int versiDikirim,
    required String status,
    String? alasan,
    String? detail,
    String? penanda,
    int? serverId,
  }) {
    return transaction(() async {
      final ada = await satuDokumen(uuid);
      if (ada == null) return;
      final berhasil = status == 'ok' || status == 'duplikat';
      final percobaan = berhasil ? 0 : ada.percobaan + 1;
      await (update(dokumen)..where((t) => t.uuid.equals(uuid))).write(
        DokumenCompanion(
          versiTerkirim: berhasil ? Value(versiDikirim) : const Value.absent(),
          statusKirim: Value(berhasil ? (ada.versi > versiDikirim ? 'lokal' : 'terkirim') : status),
          alasan: Value(alasan),
          detail: Value(detail),
          penanda: penanda == null ? const Value.absent() : Value(penanda),
          serverId: serverId == null ? const Value.absent() : Value(serverId),
          percobaan: Value(percobaan),
          tundaSampai: Value(berhasil || status == 'ditolak' ? null : DateTime.now().add(jedaUlang(percobaan))),
        ),
      );
    });
  }

  Future<void> catatStatusServer(String uuid, String status, String? catatan) {
    return (update(dokumen)..where((t) => t.uuid.equals(uuid))).write(
      DokumenCompanion(statusServer: Value(status), catatanServer: Value(catatan)),
    );
  }

  // -------------------------------------------------------------------------
  // Foto
  // -------------------------------------------------------------------------

  Future<void> simpanFoto(FotoCompanion baris) => into(foto).insert(baris);

  Future<BarisFoto?> satuFoto(String uuid) =>
      (select(foto)..where((t) => t.uuid.equals(uuid))).getSingleOrNull();

  Future<List<BarisFoto>> antreanFoto(int userId, {int batas = 20}) {
    final kini = DateTime.now();
    final q = select(foto)
      ..where((t) =>
          t.userId.equals(userId) &
          t.statusKirim.equals('lokal') &
          (t.tundaSampai.isNull() | t.tundaSampai.isSmallerOrEqualValue(kini)))
      ..orderBy([(t) => OrderingTerm.asc(t.diambil)])
      ..limit(batas);
    return q.get();
  }

  Stream<int> pantauJumlahFotoBelumTerkirim(int userId) {
    final jumlah = foto.uuid.count();
    final q = selectOnly(foto)
      ..addColumns([jumlah])
      ..where(foto.userId.equals(userId) & foto.statusKirim.equals('lokal'));
    return q.watchSingle().map((r) => r.read(jumlah) ?? 0);
  }

  Future<void> catatFoto(String uuid, {required String status, String? alasan}) {
    return transaction(() async {
      final ada = await satuFoto(uuid);
      if (ada == null) return;
      final berhasil = status == 'terkirim';
      final percobaan = berhasil ? 0 : ada.percobaan + 1;
      await (update(foto)..where((t) => t.uuid.equals(uuid))).write(
        FotoCompanion(
          statusKirim: Value(status == 'gagal' ? 'lokal' : status),
          alasan: Value(alasan),
          percobaan: Value(percobaan),
          tundaSampai: Value(status == 'gagal' ? DateTime.now().add(jedaUlang(percobaan)) : null),
        ),
      );
    });
  }
}

/// Jeda sebelum mencoba lagi: 30 dtk, 1, 2, 4, ... maks 30 menit.
Duration jedaUlang(int percobaan) {
  final detik = 30 * (1 << (percobaan.clamp(1, 7) - 1));
  return Duration(seconds: detik > 1800 ? 1800 : detik);
}

Map<String, Object?> _peta(String json) => (jsonDecode(json) as Map).cast<String, Object?>();
