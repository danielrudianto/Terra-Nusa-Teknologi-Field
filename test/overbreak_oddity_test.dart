import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/casting/calc/casting_state.dart';

/// Rasio overbreak yang MELOMPAT dari pola titiknya sendiri.
///
/// Dari kejadian nyata, 27 Okt 2026: satu titik berjalan 1,04 · 1,04 ·
/// 1,05 lalu tiba-tiba 0,50 — dan yang 0,50 itu salah ketik sounding,
/// bukan lubangnya yang berubah.
///
/// Yang dijaga di sini BUKAN "rasio harus mendekati 1". Lubang boleh
/// melebar dan boleh menyempit (necking), dan tiap titik punya angkanya
/// sendiri: yang 1,30 sepanjang cor itu wajar, yang 0,90 sepanjang cor
/// juga wajar. Karena itu setengah dari uji di bawah justru memastikan
/// aplikasinya DIAM pada titik-titik semacam itu. Peringatan yang
/// berbunyi untuk pekerjaan yang benar akan dimatikan orangnya, dan yang
/// sungguhan ikut mati bersamanya.
void main() {
  bool ganjil(double rasio, List<double> sebelumnya) =>
      overbreakOddity(ratio: rasio, sebelumnya: sebelumnya) != null;

  group('melompat dari pola titiknya', () {
    test('kasus 27 Okt 2026: 1,04 · 1,04 · 1,05 lalu 0,50', () {
      expect(ganjil(0.50, [1.04, 1.04, 1.05]), isTrue);
    });
    test('melompat naik juga tertangkap: 1,04 lalu 1,60', () {
      expect(ganjil(1.60, [1.04, 1.04, 1.05]), isTrue);
    });
    test('TM berikutnya yang wajar: 1,05 setelah 1,04', () {
      expect(ganjil(1.05, [1.04, 1.04]), isFalse);
    });
  });

  group('lubang yang memang begitu bentuknya TIDAK diganggu', () {
    test('necking konsisten: 0,88 setelah 0,92 · 0,90 · 0,91', () {
      expect(ganjil(0.88, [0.92, 0.90, 0.91]), isFalse);
    });
    test('lubang lebar konsisten: 1,32 setelah 1,30 · 1,28 · 1,31', () {
      expect(ganjil(1.32, [1.30, 1.28, 1.31]), isFalse);
    });
  });

  group('batas 20 persen', () {
    test('tepat di dalam batas lolos', () {
      expect(ganjil(1.04 * (1 + ratioDeviationMax) - 0.001, [1.04, 1.04]), isFalse);
    });
    test('sedikit di luar batas tertangkap', () {
      expect(ganjil(1.04 * (1 + ratioDeviationMax) + 0.01, [1.04, 1.04]), isTrue);
    });
  });

  group('TM pertama, belum ada pembanding', () {
    test('0,50 tertangkap oleh batas kewarasan', () {
      expect(ganjil(0.50, const []), isTrue);
    });
    test('0,85 lolos — necking yang masuk akal', () {
      expect(ganjil(0.85, const []), isFalse);
    });
    test('batasnya sama dengan clamp averageRatio', () {
      expect(ratioFloor, 0.80);
      expect(ratioCeiling, 2.00);
    });
  });

  test('pembandingnya MEDIAN, bukan rata-rata', () {
    // Satu angka buruk yang terlanjur tersimpan menggeser RATA-RATA ke
    // arahnya, dan angka salah berikutnya ikut terlihat normal. Median
    // tidak bergeser.
    //
    // Titik ini sebenarnya berjalan di 1,04, tetapi satu sounding kacau
    // (0,20) sudah masuk. Lalu datang 0,75 — juga salah.
    //
    //   rata-rata [1,04 1,04 1,04 0,20] = 0,83 -> 0,75 cuma 10% meleset,
    //                                             LOLOS tanpa sepatah kata
    //   median                          = 1,04 -> 0,75 meleset 28%,
    //                                             TERTANGKAP
    expect(ganjil(0.75, [1.04, 1.04, 1.04, 0.20]), isTrue);

    // Dan dengan satu pembanding buruk saja, angka yang BENAR tetap
    // dipertanyakan — bukan diterima diam-diam. Itu memang yang
    // diinginkan: yang ditanya ulang akan ketahuan mana yang salah.
    expect(ganjil(1.04, [0.50]), isTrue);
  });
}
