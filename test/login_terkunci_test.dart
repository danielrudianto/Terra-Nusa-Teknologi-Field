import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/login/login_page.dart';

/// Hitung mundur penguncian masuk.
///
/// Server menolak percobaan beruntun dengan 429 berkode `TOO_MANY_ATTEMPTS`
/// dan menyebutkan sisa detiknya. Sampai 22 Okt 2026 layar HP hanya
/// menampilkan kalimat server apa adanya — "Coba lagi dalam 15 menit" —
/// yang TIDAK BERGERAK. Yang sudah menunggu lima menit tetap membaca lima
/// belas, dan menyimpulkan kuncinya tidak jalan.
///
/// Yang diuji di sini bentuk bacaannya, karena itulah satu-satunya tanda
/// di layar bahwa kuncinya memang berjalan.
void main() {
  test('detik selalu dua angka, supaya lebarnya tidak melompat', () {
    expect(sisaTerbaca(63), '1:03');
    expect(sisaTerbaca(70), '1:10');
  });

  test('menit penuh tidak berbunyi "1:0"', () {
    expect(sisaTerbaca(60), '1:00');
    expect(sisaTerbaca(900), '15:00');
  });

  test('di bawah satu menit tetap menyebut menitnya', () {
    // "0:09", bukan "9": tanpa menitnya, angka kecil terbaca sebagai menit
    // oleh yang melirik sekilas — dan sembilan menit jauh berbeda dari
    // sembilan detik.
    expect(sisaTerbaca(9), '0:09');
    expect(sisaTerbaca(59), '0:59');
  });

  test('nol dan negatif tidak menghasilkan tulisan aneh', () {
    expect(sisaTerbaca(0), '0:00');
    expect(sisaTerbaca(-5), '0:00');
  });
}
