import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/drilling/bor_kurva.dart';

/// Waktu BERHENTI vs waktu MENGEBOR pada ringkasan log bor.
///
/// Aturannya harus SAMA DENGAN WEB (`helpers/bor-kurva.helper.ts`). Dua
/// layar yang menyebut jumlah berhenti berbeda untuk titik yang sama
/// merusak kepercayaan pada dua-duanya, dan yang membaca tidak punya cara
/// mengetahui yang mana yang benar.
void main() {
  DateTime jam(int h, int m) => DateTime(2026, 10, 19, h, m);

  Map<String, Object?> bacaan(DateTime at, double dalam) => {
        'uuid': '${at.hour}-${at.minute}',
        'at': at.toIso8601String(),
        'depthM': dalam.toStringAsFixed(2),
      };

  test('tanpa berhenti: efektif = total, dan tidak ada ruas berhenti', () {
    final r = ringkasBor([
      bacaan(jam(8, 0), 0),
      bacaan(jam(9, 0), 4),
      bacaan(jam(10, 0), 9),
    ]);
    expect(r.durasiJam, closeTo(2, 1e-9));
    expect(r.durasiEfektifJam, closeTo(2, 1e-9));
    expect(r.durasiBerhentiJam, closeTo(0, 1e-9));
    expect(r.berhenti, isEmpty);
    expect(r.lajuEfektifMPerJam, closeTo(4.5, 1e-9));
  });

  test('kedalaman tetap selama dua jam: dua jam itu bukan waktu mengebor', () {
    final r = ringkasBor([
      bacaan(jam(8, 0), 0),
      bacaan(jam(9, 0), 6),
      bacaan(jam(11, 0), 6), // menunggu material
      bacaan(jam(12, 0), 12),
    ]);
    expect(r.durasiJam, closeTo(4, 1e-9));
    expect(r.durasiEfektifJam, closeTo(2, 1e-9));
    expect(r.durasiBerhentiJam, closeTo(2, 1e-9));
    expect(r.berhenti, hasLength(1));
    expect(r.berhenti.single.jam, closeTo(2, 1e-9));
    // Laju atas durasi efektif LEBIH TINGGI daripada atas durasi total —
    // itu seluruh gunanya memisahkan keduanya.
    expect(r.lajuEfektifMPerJam, closeTo(6, 1e-9));
    expect(r.lajuRataMPerJam, closeTo(3, 1e-9));
  });

  test('ketiganya selalu saling menjumlah', () {
    final r = ringkasBor([
      bacaan(jam(7, 10), 0),
      bacaan(jam(7, 55), 3.4),
      bacaan(jam(10, 30), 3.4),
      bacaan(jam(10, 50), 5),
      bacaan(jam(11, 5), 5),
      bacaan(jam(13, 0), 14.2),
    ]);
    expect(
      r.durasiEfektifJam! + r.durasiBerhentiJam!,
      closeTo(r.durasiJam!, 1e-9),
    );
  });

  test('mandek 14 menit: mengurangi durasi efektif, TIDAK disebut berhenti',
      () {
    final r = ringkasBor([
      bacaan(jam(8, 0), 0),
      bacaan(jam(9, 0), 5),
      bacaan(jam(9, 14), 5), // sambung pipa
      bacaan(jam(10, 0), 9),
    ]);
    expect(r.berhenti, isEmpty, reason: 'di bawah $menitBerhenti menit');
    // 14 menit itu tetap hilang dari waktu mengebor.
    expect(r.durasiEfektifJam, closeTo(1 + 46 / 60, 1e-9));
    expect(r.durasiBerhentiJam, closeTo(14 / 60, 1e-9));
  });

  test('mandek tepat 15 menit: sudah disebut berhenti', () {
    final r = ringkasBor([
      bacaan(jam(8, 0), 0),
      bacaan(jam(9, 0), 5),
      bacaan(jam(9, 15), 5),
      bacaan(jam(10, 0), 9),
    ]);
    expect(r.berhenti, hasLength(1));
    expect(r.berhenti.single.jam, closeTo(0.25, 1e-9));
  });

  test('bor DIANGKAT lama juga berhenti — bukan pengeboran mundur', () {
    final r = ringkasBor([
      bacaan(jam(8, 0), 0),
      bacaan(jam(9, 0), 8),
      bacaan(jam(10, 0), 6), // diangkat, dibaca lagi
      bacaan(jam(11, 0), 11),
    ]);
    expect(r.berhenti, hasLength(1));
    expect(r.durasiEfektifJam, closeTo(2, 1e-9));
    // Kedalamannya tetap yang TERDALAM, bukan bacaan terakhir yang lebih
    // dangkal.
    expect(r.kedalamanM, 11);
  });

  test('BACAAN DI TENGAH BERHENTI tidak memecahnya menjadi dua', () {
    /*
     * Dilaporkan Daniel, 19 Okt 2026: engineer diminta tetap mengabarkan
     * keadaan selama rig diam, jadi berhenti 11.00–13.00 kerap berisi satu
     * bacaan di jam 12.00 dengan kedalaman yang sama.
     *
     * Dihitung apa adanya, itu menjadi "2 kali berhenti · masing-masing 1
     * jam" — dan yang paling disiplin mengabarkan justru tampak paling
     * sering berhenti.
     */
    final r = ringkasBor([
      bacaan(jam(10, 0), 0),
      bacaan(jam(11, 0), 12), // mengebor
      bacaan(jam(12, 0), 12), // diam, dikabarkan di tengah
      bacaan(jam(13, 0), 12), // masih diam
      bacaan(jam(14, 0), 20), // mengebor lagi
    ]);
    expect(r.berhenti, hasLength(1));
    expect(r.berhenti.single.jam, closeTo(2, 1e-9));
    expect(
      DateTime.fromMillisecondsSinceEpoch(r.berhenti.single.dariWaktu).hour,
      11,
    );
    expect(
      DateTime.fromMillisecondsSinceEpoch(r.berhenti.single.sampaiWaktu).hour,
      13,
    );
    // Penggabungan TIDAK menyentuh durasi efektif.
    expect(r.durasiEfektifJam, closeTo(2, 1e-9));
    expect(r.durasiBerhentiJam, closeTo(2, 1e-9));
  });

  test('mandek pendek berturut-turut yang totalnya lewat ambang ikut terhitung',
      () {
    // Tiga mandek sepuluh menit berurutan adalah setengah jam rig diam.
    final r = ringkasBor([
      bacaan(jam(8, 0), 0),
      bacaan(jam(8, 30), 5),
      bacaan(jam(8, 40), 5),
      bacaan(jam(8, 50), 5),
      bacaan(jam(9, 0), 5),
      bacaan(jam(9, 30), 9),
    ]);
    expect(r.berhenti, hasLength(1));
    expect(r.berhenti.single.jam, closeTo(0.5, 1e-9));
  });

  test('bor diangkat lalu diam dihitung sebagai SATU berhenti', () {
    final r = ringkasBor([
      bacaan(jam(8, 0), 0),
      bacaan(jam(9, 0), 20),
      bacaan(jam(10, 0), 15), // diangkat
      bacaan(jam(11, 0), 15), // diam
      bacaan(jam(12, 0), 25),
    ]);
    expect(r.berhenti, hasLength(1));
    expect(r.berhenti.single.jam, closeTo(2, 1e-9));
    expect(r.berhenti.single.deltaM, closeTo(-5, 1e-9));
  });

  test('satu bacaan: null, BUKAN nol', () {
    final r = ringkasBor([bacaan(jam(8, 0), 3)]);
    expect(r.durasiJam, isNull);
    expect(r.durasiEfektifJam, isNull);
    expect(r.durasiBerhentiJam, isNull);
    expect(r.lajuEfektifMPerJam, isNull);
    expect(r.berhenti, isEmpty);
    expect(r.jumlahBacaan, 1);
  });

  test('tanpa bacaan sama sekali', () {
    final r = ringkasBor(const []);
    expect(r.jumlahBacaan, 0);
    expect(r.durasiEfektifJam, isNull);
    expect(r.berhenti, isEmpty);
  });

  test('seluruhnya mandek: efektif nol, laju efektif null bukan tak hingga',
      () {
    final r = ringkasBor([
      bacaan(jam(8, 0), 4),
      bacaan(jam(10, 0), 4),
    ]);
    expect(r.durasiEfektifJam, closeTo(0, 1e-9));
    expect(r.durasiBerhentiJam, closeTo(2, 1e-9));
    expect(r.lajuEfektifMPerJam, isNull);
  });

  test('durasi berhenti tidak pernah negatif', () {
    final r = ringkasBor([
      bacaan(jam(8, 0), 0),
      bacaan(jam(8, 30), 2),
      bacaan(jam(9, 0), 5),
    ]);
    expect(r.durasiBerhentiJam, greaterThanOrEqualTo(0));
  });
}
