import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Pengguna yang masuk — dari jawaban `POST /auth/`.
class Pengguna {
  const Pengguna({required this.id, required this.nama, required this.email, required this.level});

  final int id;
  final String nama;
  final String email;
  final int level;

  factory Pengguna.dariJson(Map<String, Object?> j) => Pengguna(
        id: (j['id'] as num).toInt(),
        nama: (j['name'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        level: (j['authenticationLevel'] as num?)?.toInt() ?? 1,
      );

  Map<String, Object?> keJson() => {'id': id, 'name': nama, 'email': email, 'authenticationLevel': level};

  String get inisial {
    final kata = nama.trim().split(RegExp(r'\s+')).where((k) => k.isNotEmpty).toList();
    if (kata.isEmpty) return '?';
    return (kata.first[0] + (kata.length > 1 ? kata.last[0] : '')).toUpperCase();
  }
}

/// Peta izin dari `GET /permissions/me` — ditampilkan apa adanya.
///
/// Menyembunyikan menu BUKAN pengamanan; server tetap memeriksa setiap
/// kiriman. Ini hanya supaya mandor tidak melihat tombol yang pasti ditolak.
class PetaIzin {
  const PetaIzin({required this.level, required this.divisi, required this.izin, required this.hanyaBaca});

  final int level;
  final List<String> divisi;
  final Map<String, Map<String, bool>> izin;
  final bool hanyaBaca;

  static const kosong = PetaIzin(level: 1, divisi: [], izin: {}, hanyaBaca: false);

  bool boleh(String modul, String aksi) => izin[modul]?[aksi] ?? false;

  factory PetaIzin.dariJson(Map<String, Object?> j) {
    final mentah = (j['permissions'] as Map?) ?? const {};
    return PetaIzin(
      level: (j['level'] as num?)?.toInt() ?? 1,
      divisi: [for (final d in (j['departments'] as List?) ?? const []) d.toString()],
      izin: {
        for (final e in mentah.entries)
          e.key.toString(): {
            for (final a in ((e.value as Map?) ?? const {}).entries) a.key.toString(): a.value == true,
          },
      },
      hanyaBaca: j['readOnly'] == true,
    );
  }

  Map<String, Object?> keJson() =>
      {'level': level, 'departments': divisi, 'permissions': izin, 'readOnly': hanyaBaca};
}

/// Penyimpanan aman: token, pengguna, dan izin terakhir.
///
/// Izin TERAKHIR disimpan supaya HP tetap tahu menu mana yang ditampilkan
/// ketika dibuka tanpa sinyal — setelah login pertama, aplikasi harus dapat
/// dipakai seharian di lokasi tanpa jaringan.
class PenyimpanSesi {
  PenyimpanSesi(this.simpan);

  final FlutterSecureStorage simpan;

  static const _akses = 'token_akses';
  static const _segar = 'token_segar';
  static const _pengguna = 'pengguna';
  static const _izin = 'izin';
  static const _habis = 'sesi_habis';

  Future<String?> aksesToken() => simpan.read(key: _akses);
  Future<String?> segarToken() => simpan.read(key: _segar);

  Future<void> tulisToken(String akses, String segar) async {
    await simpan.write(key: _akses, value: akses);
    await simpan.write(key: _segar, value: segar);
    await simpan.delete(key: _habis);
  }

  Future<void> tulisPengguna(Pengguna p) => simpan.write(key: _pengguna, value: jsonEncode(p.keJson()));
  Future<void> tulisIzin(PetaIzin i) => simpan.write(key: _izin, value: jsonEncode(i.keJson()));

  Future<Pengguna?> pengguna() async {
    final t = await simpan.read(key: _pengguna);
    if (t == null) return null;
    return Pengguna.dariJson((jsonDecode(t) as Map).cast<String, Object?>());
  }

  Future<PetaIzin> izin() async {
    final t = await simpan.read(key: _izin);
    if (t == null) return PetaIzin.kosong;
    return PetaIzin.dariJson((jsonDecode(t) as Map).cast<String, Object?>());
  }

  /// Refresh token ditolak server. Dokumen di HP TIDAK dihapus; yang
  /// diminta hanya masuk lagi supaya antreannya dapat dikirim.
  Future<void> tandaiSesiHabis() => simpan.write(key: _habis, value: '1');
  Future<bool> sesiHabis() async => (await simpan.read(key: _habis)) == '1';

  /// Keluar: token dan izin dibuang. Pengguna terakhir DIPERTAHANKAN supaya
  /// antrean miliknya tetap dikenali bila ia masuk lagi.
  Future<void> keluar() async {
    await simpan.delete(key: _akses);
    await simpan.delete(key: _segar);
    await simpan.delete(key: _izin);
    await simpan.delete(key: _habis);
  }

  Future<void> lupakanPengguna() => simpan.delete(key: _pengguna);
}
