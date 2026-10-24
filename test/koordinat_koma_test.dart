import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/drilling/koordinat_aktual.dart';

/// KOMA YANG TERLEWAT pada isian koordinat.
///
/// ARSAFIN, 22 Okt 2026, lewat Daniel: "1 angka nya ga bisa pak yang Y".
/// Yang diketiknya `924128248` untuk titik yang koordinatnya `9241282,485`
/// — seluruh angka diketik tanpa komanya, sehingga bagian bulatnya menabrak
/// batas sembilan angka dan ketukan berikutnya ditolak TANPA SUARA.
///
/// Yang diuji di sini bukan batasnya (itu sudah benar: sembilan angka meter
/// adalah sejuta kilometer), melainkan apakah layarnya dapat MENGENALI
/// sebabnya dan menyebutkannya.
void main() {
  group('angkaSebelumKoma', () {
    test('tanpa koma menghitung seluruh angka', () {
      expect(angkaSebelumKoma('924128248'), 9);
    });

    test('dengan koma hanya menghitung bagian bulatnya', () {
      expect(angkaSebelumKoma('9241282,485'), 7);
    });

    test('kosong adalah nol, bukan melempar', () {
      expect(angkaSebelumKoma(''), 0);
      expect(angkaSebelumKoma('  '), 0);
    });

    test('minus tidak ikut dihitung sebagai angka', () {
      expect(angkaSebelumKoma('-1234,5'), 4);
    });
  });

  group('angkaRencana', () {
    test('koordinat tujuh digit', () {
      expect(angkaRencana(9241282.485), 7);
    });

    test('nol tetap satu angka, bukan nol angka', () {
      // Grid lokal boleh beracuan (0,0). Dihitung nol angka, SETIAP ketikan
      // akan dinyatakan kelebihan koma.
      expect(angkaRencana(0), 1);
    });

    test('negatif dibaca dari besarnya', () {
      expect(angkaRencana(-770883.24), 6);
    });

    test('tanpa rencana tidak dapat dinyatakan apa pun', () {
      expect(angkaRencana(null), isNull);
    });
  });

  group('komaMungkinTerlewat', () {
    test('kejadian Arsafin: 9 angka pada titik yang rencananya 7', () {
      expect(
        komaMungkinTerlewat(teks: '924128248', rencana: 9241282.485),
        isTrue,
      );
    });

    test('begitu komanya diketik, peringatannya padam', () {
      // Sesudah komanya ada, yang menjaga kebenarannya palang simpangan —
      // bukan hitungan angka.
      expect(
        komaMungkinTerlewat(teks: '9241282,485', rencana: 9241282.485),
        isFalse,
      );
    });

    test('yang panjangnya pas tidak diganggu', () {
      expect(
        komaMungkinTerlewat(teks: '9241282', rencana: 9241282.485),
        isFalse,
      );
    });

    test('yang masih setengah diketik tidak diganggu', () {
      // Menyala saat baru tiga angka akan membuat banner berkedip pada
      // setiap ketukan — dan peringatan yang selalu ada berhenti dibaca.
      expect(komaMungkinTerlewat(teks: '924', rencana: 9241282.485), isFalse);
    });

    test('tanpa koordinat rencana TIDAK menuduh apa pun', () {
      // Tanpa acuan, "terlalu panjang" tidak dapat dinyatakan — dan menebak
      // lebih buruk daripada diam.
      expect(komaMungkinTerlewat(teks: '924128248', rencana: null), isFalse);
    });

    test('X yang rencananya enam angka juga terdeteksi', () {
      expect(
        komaMungkinTerlewat(teks: '770883240', rencana: 770883.240),
        isTrue,
      );
    });
  });
}
