import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/drilling/koordinat_aktual.dart';

/// SIMPANGAN X/Y — aturannya.
///
/// DIMINTA DANIEL, 14 Oktober 2026: X/Y aktual diisi di HP, diwajibkan
/// setelah pengeboran selesai. Angka ini yang dibandingkan dengan toleransi
/// proyek, dan yang salah di sini tidak bersuara: ia menghasilkan angka yang
/// tampak wajar, bukan galat.
void main() {
  group('simpanganMm', () {
    test('jarak lurus, dalam milimeter', () {
      // 3-4-5: 0,003 m dan 0,004 m -> 0,005 m -> 5 mm.
      expect(
        simpanganMm(designX: 0, designY: 0, actualX: 0.003, actualY: 0.004),
        closeTo(5, 1e-9),
      );
    });

    test('tepat di rencana = nol', () {
      expect(simpanganMm(designX: 100, designY: 200, actualX: 100, actualY: 200), 0);
    });

    test('arah tidak berpengaruh', () {
      final a = simpanganMm(designX: 0, designY: 0, actualX: -0.05, actualY: 0)!;
      final b = simpanganMm(designX: 0, designY: 0, actualX: 0.05, actualY: 0)!;
      expect(a, closeTo(b, 1e-9));
      expect(a, closeTo(50, 1e-9));
    });

    test('koordinat yang BELUM LENGKAP menghasilkan null, bukan nol', () {
      // Nol berarti "tepat di rencana" dan LULUS pemeriksaan toleransi.
      // Titik yang koordinat rencananya belum pernah diisi dari kantor akan
      // terbaca sebagai titik yang paling tepat di seluruh proyek.
      expect(simpanganMm(designX: null, designY: 0, actualX: 0, actualY: 0), isNull);
      expect(simpanganMm(designX: 0, designY: null, actualX: 0, actualY: 0), isNull);
      expect(simpanganMm(designX: 0, designY: 0, actualX: null, actualY: 0), isNull);
      expect(simpanganMm(designX: 0, designY: 0, actualX: 0, actualY: null), isNull);
      expect(simpanganMm(), isNull);
    });

    test('nol adalah koordinat yang SAH, bukan kekosongan', () {
      // (0, 0) titik acuan grid lokal. Diperlakukan sebagai kosong,
      // simpangan titik di acuannya tidak akan pernah terhitung.
      expect(simpanganMm(designX: 0, designY: 0, actualX: 0, actualY: 0), 0);
      expect(simpanganMm(designX: 0, designY: 0, actualX: 0.075, actualY: 0),
          closeTo(75, 1e-9));
    });

    test('koordinat grid besar tidak kehilangan milimeternya', () {
      // Grid proyek nyata berangka ratusan ribu meter. Dihitung dengan
      // presisi yang kurang, selisih 50 mm di antara dua angka tujuh digit
      // hilang ke pembulatan — dan setiap titik terbaca tepat di rencana.
      final d = simpanganMm(
        designX: 1234567.000,
        designY: 9876543.000,
        actualX: 1234567.050,
        actualY: 9876543.000,
      )!;
      expect(d, closeTo(50, 1e-6));
    });
  });

  group('formatMm', () {
    test('milimeter bulat', () {
      expect(formatMm(74.83), '75 mm');
      expect(formatMm(0), '0 mm');
      expect(formatMm(null), '—');
    });
  });
}
