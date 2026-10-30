import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Nama placeholder di dalam kalimat HARUS sama dengan yang dideklarasikan.
///
/// Ditulis setelah kejadian nyata, 27 Okt 2026. Penyapuan istilah mengganti
/// kata "log" menjadi "catatan" di seluruh teks Indonesia — dan ikut
/// menangkap nama placeholder di dalam kurung kurawal: `{log}` menjadi
/// `{catatan}`, sementara blok `@`-nya masih menyebut `log`.
///
/// `gen-l10n` tidak mengeluh. Ia justru MEMBANGKITKAN metode dengan DUA
/// parameter — satu dari deklarasinya, satu dari kalimatnya — dan yang
/// mogok adalah `flutter analyze` di sembilan tempat pemakaian, jauh dari
/// sebabnya, dengan pesan "2 positional arguments expected" yang tidak
/// menyebut berkas terjemahan sama sekali.
///
/// Nama placeholder adalah PENGENAL, bukan teks yang dibaca orang. Tidak
/// ada penyapuan kata yang boleh menyentuhnya.
void main() {
  Map<String, dynamic> baca(String nama) =>
      jsonDecode(File('lib/l10n/$nama').readAsStringSync()) as Map<String, dynamic>;

  Set<String> dipakai(String pesan) =>
      RegExp(r'\{(\w+)\}').allMatches(pesan).map((m) => m.group(1)!).toSet();

  Set<String> dideklarasi(Map<String, dynamic> arb, String kunci) {
    final meta = arb['@$kunci'];
    if (meta is! Map) return <String>{};
    final p = meta['placeholders'];
    if (p is! Map) return <String>{};
    return p.keys.map((e) => '$e').toSet();
  }

  /// Daftar ketidakcocokan; kosong berarti sehat. Dipakai dua kali —
  /// sekali untuk berkas sungguhan, sekali untuk berkas yang sengaja
  /// dirusak, supaya penjaganya sendiri terbukti menangkap.
  List<String> bedaDeklarasi(Map<String, dynamic> arb) {
    final hasil = <String>[];
    for (final e in arb.entries) {
      if (e.key.startsWith('@') || e.value is! String) continue;
      final a = dipakai(e.value as String);
      final b = dideklarasi(arb, e.key);
      if (b.isEmpty) continue; // tanpa deklarasi: tidak ada yang dibandingkan
      if (a.length != b.length || !a.containsAll(b)) {
        hasil.add('${e.key}: dipakai $a, dideklarasi $b');
      }
    }
    return hasil;
  }

  List<String> bedaTerjemahan(Map<String, dynamic> induk, Map<String, dynamic> anak, String nama) {
    final hasil = <String>[];
    for (final e in anak.entries) {
      if (e.key.startsWith('@') || e.value is! String) continue;
      final asli = induk[e.key];
      if (asli is! String) continue;
      final a = dipakai(e.value as String);
      final b = dipakai(asli);
      if (a.length != b.length || !a.containsAll(b)) {
        hasil.add('$nama ${e.key}: $a vs $b');
      }
    }
    return hasil;
  }

  test('app_id.arb: placeholder yang dipakai sama dengan yang dideklarasikan', () {
    expect(bedaDeklarasi(baca('app_id.arb')), isEmpty);
  });

  test('terjemahan memakai placeholder yang sama dengan templatnya', () {
    final induk = baca('app_id.arb');
    expect(bedaTerjemahan(induk, baca('app_en.arb'), 'en'), isEmpty);
    expect(bedaTerjemahan(induk, baca('app_zh.arb'), 'zh'), isEmpty);
  });

  test('penjaga untuk penjaganya: kesalahan 27 Okt 2026 tertangkap', () {
    // Persis bentuk cacatnya: kalimatnya disapu, deklarasinya tidak.
    final rusak = <String, dynamic>{
      'sendingFirst': 'Mengirim {catatan} dulu…',
      '@sendingFirst': {
        'placeholders': {'log': {'type': 'String'}},
      },
    };
    expect(bedaDeklarasi(rusak), hasLength(1));

    // ...dan terjemahan yang placeholdernya ikut tergeser.
    expect(
      bedaTerjemahan(
        {'takingLog': 'Mengambil {log}…'},
        {'takingLog': 'Taking {catatan}…'},
        'en',
      ),
      hasLength(1),
    );
  });
}
