import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/database.dart';
import 'jaringan/api.dart';
import 'jaringan/galat.dart';
import 'konteks.dart';
import 'sesi/sesi.dart';
import 'sinkron/mesin_sinkron.dart';
import 'sinkron/pekerja_latar.dart';

/// Diisi di `main()` lewat `overrides`. Semua penyedia lain turunannya.
final konteksProvider = Provider<KonteksAplikasi>((ref) => throw UnimplementedError('konteksProvider belum diisi'));

final dbProvider = Provider<BasisData>((ref) => ref.watch(konteksProvider).db);
final apiProvider = Provider<KlienApi>((ref) => ref.watch(konteksProvider).api);
final mesinProvider = Provider<MesinSinkron>((ref) => ref.watch(konteksProvider).mesin);

// ===========================================================================
// Sesi
// ===========================================================================

class KeadaanSesi {
  const KeadaanSesi({this.pengguna, this.izin = PetaIzin.kosong, this.sesiHabis = false});

  final Pengguna? pengguna;
  final PetaIzin izin;

  /// Refresh token ditolak: data di HP tetap, tetapi harus masuk lagi
  /// sebelum antrean dapat dikirim.
  final bool sesiHabis;

  bool get masuk => pengguna != null && !sesiHabis;
  bool boleh(String modul, String aksi) => izin.boleh(modul, aksi);
}

class SesiNotifier extends AsyncNotifier<KeadaanSesi> {
  PenyimpanSesi get _simpan => ref.read(konteksProvider).sesi;

  @override
  Future<KeadaanSesi> build() async {
    final pengguna = await _simpan.pengguna();
    final token = await _simpan.aksesToken();
    final habis = await _simpan.sesiHabis();
    // Tanpa token dan bukan karena ditolak server = memang keluar.
    if (pengguna == null || (token == null && !habis)) return const KeadaanSesi();
    return KeadaanSesi(pengguna: pengguna, izin: await _simpan.izin(), sesiHabis: habis);
  }

  Future<void> masuk(String email, String sandi) async {
    final api = ref.read(apiProvider);
    final (pengguna, akses, segar) = await api.masuk(email, sandi);
    final sebelumnya = await _simpan.pengguna();
    if (sebelumnya != null && sebelumnya.id != pengguna.id) {
      await ref.read(dbProvider).gantiPengguna();
    }
    await _simpan.tulisToken(akses, segar);
    await _simpan.tulisPengguna(pengguna);
    var izin = PetaIzin.kosong;
    try {
      izin = await api.izin();
      await _simpan.tulisIzin(izin);
    } on GalatApi {
      izin = await _simpan.izin();
    }
    state = AsyncData(KeadaanSesi(pengguna: pengguna, izin: izin));
    unawaited(ref.read(sinkronProvider.notifier).jalankan());
  }

  /// Dipanggil KlienApi saat refresh token ditolak.
  void tandaiHabis() {
    final kini = state.value;
    if (kini == null || kini.pengguna == null) return;
    state = AsyncData(KeadaanSesi(pengguna: kini.pengguna, izin: kini.izin, sesiHabis: true));
  }

  /// Muat ulang izin dari server (mis. setelah admin menambah modul).
  Future<void> segarkanIzin() async {
    final kini = state.value;
    if (kini == null || !kini.masuk) return;
    try {
      final izin = await ref.read(apiProvider).izin();
      await _simpan.tulisIzin(izin);
      state = AsyncData(KeadaanSesi(pengguna: kini.pengguna, izin: izin));
    } on GalatApi {
      // tanpa sinyal: izin terakhir tetap dipakai
    }
  }

  Future<void> keluar() async {
    await ref.read(apiProvider).keluar();
    await _simpan.keluar();
    state = const AsyncData(KeadaanSesi());
  }
}

final sesiProvider = AsyncNotifierProvider<SesiNotifier, KeadaanSesi>(SesiNotifier.new);

/// Pengguna aktif — null bila belum pernah masuk.
final penggunaProvider = Provider<Pengguna?>((ref) => ref.watch(sesiProvider).value?.pengguna);

// ===========================================================================
// Sinkron
// ===========================================================================

class KeadaanSinkron {
  const KeadaanSinkron({this.berjalan = false, this.terakhir, this.waktu});

  final bool berjalan;
  final HasilSinkron? terakhir;
  final DateTime? waktu;
}

class SinkronNotifier extends Notifier<KeadaanSinkron> {
  @override
  KeadaanSinkron build() => const KeadaanSinkron();

  /// Kirim + tarik sekarang. Aman dipanggil berkali-kali: yang sedang
  /// berjalan tidak digandakan, dan pekerja latar dihalangi kunci.
  Future<HasilSinkron?> jalankan() async {
    if (state.berjalan) return null;
    state = KeadaanSinkron(berjalan: true, terakhir: state.terakhir, waktu: state.waktu);
    HasilSinkron? hasil;
    try {
      hasil = await ref.read(mesinProvider).jalankan();
      if (hasil.sesiHabis) ref.read(sesiProvider.notifier).tandaiHabis();
    } finally {
      state = KeadaanSinkron(terakhir: hasil ?? state.terakhir, waktu: DateTime.now());
    }
    return hasil;
  }

  /// Setelah menyimpan dokumen: coba kirim sekarang; bila tidak ada sinyal,
  /// pekerja latar mengirimnya begitu sinyal datang.
  void setelahSimpan() {
    unawaited(mintaSinkronSegera().catchError((_) {}));
    unawaited(jalankan());
  }
}

final sinkronProvider = NotifierProvider<SinkronNotifier, KeadaanSinkron>(SinkronNotifier.new);

final jumlahBelumTerkirimProvider = StreamProvider<int>((ref) {
  final p = ref.watch(penggunaProvider);
  if (p == null) return Stream.value(0);
  return ref.watch(dbProvider).pantauJumlahBelumTerkirim(p.id);
});

final jumlahDitolakProvider = StreamProvider<int>((ref) {
  final p = ref.watch(penggunaProvider);
  if (p == null) return Stream.value(0);
  return ref.watch(dbProvider).pantauJumlahDitolak(p.id);
});

final jumlahFotoBelumTerkirimProvider = StreamProvider<int>((ref) {
  final p = ref.watch(penggunaProvider);
  if (p == null) return Stream.value(0);
  return ref.watch(dbProvider).pantauJumlahFotoBelumTerkirim(p.id);
});

// ===========================================================================
// Data induk & dokumen
// ===========================================================================

final proyekProvider = StreamProvider<List<Map<String, Object?>>>((ref) {
  return ref.watch(dbProvider).pantauInduk('proyek').map((d) {
    d.sort((a, b) => '${a['code']}'.compareTo('${b['code']}'));
    return d;
  });
});

/// Dokumen milik pengguna aktif, per entitas, terbaru di atas.
final dokumenProvider = StreamProvider.family<List<BarisDokumen>, String>((ref, entitas) {
  final p = ref.watch(penggunaProvider);
  if (p == null) return Stream.value(const []);
  return ref.watch(dbProvider).pantauDokumen(entitas, p.id);
});

/// Pekerja (kru) yang dapat diabsen.
///
/// Gabungan dua sumber: yang sudah ada di server (data induk), dan yang
/// BARU didaftarkan dari HP ini tetapi belum terkirim. Tanpa yang kedua,
/// pekerja yang didaftarkan pagi di lokasi tanpa sinyal tidak dapat
/// diabsen sampai HP menemukan sinyal.
class Pekerja {
  const Pekerja({required this.uuid, required this.nama, this.telepon, this.aktif = true, this.lokal = false, this.fotoUuid});

  final String uuid;
  final String nama;
  final String? telepon;
  final bool aktif;

  /// Belum ada di server.
  final bool lokal;
  final String? fotoUuid;
}

final pekerjaProvider = StreamProvider<List<Pekerja>>((ref) {
  final db = ref.watch(dbProvider);
  final p = ref.watch(penggunaProvider);
  final induk = db.pantauInduk('pekerja');
  final lokal = p == null ? Stream.value(const <BarisDokumen>[]) : db.pantauDokumen('worker', p.id);
  return _gabung(induk, lokal, (dariServer, dokumen) {
    final hasil = <String, Pekerja>{};
    for (final w in dariServer) {
      if (w['isDelete'] == true) continue;
      hasil['${w['uuid']}'] = Pekerja(
        uuid: '${w['uuid']}',
        nama: '${w['name']}',
        telepon: w['phone']?.toString(),
        aktif: w['isActive'] != false,
        fotoUuid: w['facePhotoUuid']?.toString(),
      );
    }
    for (final d in dokumen) {
      final isi = (jsonDecode(d.isi) as Map).cast<String, Object?>();
      // Versi HP lebih baru dari server selama belum terkirim.
      if (hasil.containsKey(d.uuid) && d.versi <= d.versiTerkirim) continue;
      if (d.statusKirim == 'ditolak') continue;
      hasil[d.uuid] = Pekerja(
        uuid: d.uuid,
        nama: '${isi['name']}',
        telepon: isi['phone']?.toString(),
        aktif: isi['isActive'] != false,
        lokal: !hasil.containsKey(d.uuid),
        fotoUuid: isi['facePhotoUuid']?.toString(),
      );
    }
    final daftar = hasil.values.where((w) => w.aktif).toList()
      ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
    return daftar;
  });
});

/// Titik bor per proyek, urut `sortOrder` lalu kode.
final titikProvider = StreamProvider.family<List<Map<String, Object?>>, int>((ref, projectId) {
  return ref.watch(dbProvider).pantauInduk('titik').map((semua) {
    final d = [for (final t in semua) if ('${t['projectID']}' == '$projectId' && t['isDelete'] != true) t];
    d.sort((a, b) {
      final s = ((a['sortOrder'] as num?) ?? 0).compareTo((b['sortOrder'] as num?) ?? 0);
      return s != 0 ? s : '${a['code']}'.compareTo('${b['code']}');
    });
    return d;
  });
});

/// Gabungkan dua stream — nilai terakhir masing-masing.
Stream<R> _gabung<A, B, R>(Stream<A> a, Stream<B> b, R Function(A, B) f) {
  late StreamController<R> c;
  A? na;
  B? nb;
  var adaA = false;
  var adaB = false;
  StreamSubscription<A>? sa;
  StreamSubscription<B>? sb;
  void kirim() {
    if (adaA && adaB) c.add(f(na as A, nb as B));
  }

  c = StreamController<R>(
    onListen: () {
      sa = a.listen((v) {
        na = v;
        adaA = true;
        kirim();
      }, onError: c.addError);
      sb = b.listen((v) {
        nb = v;
        adaB = true;
        kirim();
      }, onError: c.addError);
    },
    onPause: () {
      sa?.pause();
      sb?.pause();
    },
    onResume: () {
      sa?.resume();
      sb?.resume();
    },
    onCancel: () async {
      await sa?.cancel();
      await sb?.cancel();
    },
  );
  return c.stream;
}
