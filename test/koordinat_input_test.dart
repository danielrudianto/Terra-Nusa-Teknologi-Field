import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/util/decimal_input.dart';
import 'package:terrabot_field/core/util/format.dart';

/// Mengetik `teks` SATU HURUF DEMI SATU, seperti papan tombol sungguhan.
///
/// Diketik huruf demi huruf, bukan disodorkan sekaligus, karena di situlah
/// kekeliruannya hidup: formatter ini MEMBACA ULANG teks keluarannya sendiri
/// pada tiap ketukan. Uji yang menyodorkan teks jadi tidak akan pernah
/// menemuinya.
String _ketik(String teks, {KoordinatInputFormatter? formatter}) {
  final f = formatter ?? KoordinatInputFormatter();
  var nilai = const TextEditingValue(text: '');
  for (final c in teks.split('')) {
    final sisip = nilai.text + c;
    nilai = f.formatEditUpdate(
      nilai,
      TextEditingValue(
        text: sisip,
        selection: TextSelection.collapsed(offset: sisip.length),
      ),
    );
  }
  return nilai.text;
}

void main() {
  group('titik maupun koma adalah pemisah desimal', () {
    // ROYAN, 21 Okt 2026. Papan tombol angka Android menaruh `.` dan `,`
    // berdampingan, dan `.` yang dipakai hampir semua orang untuk desimal.
    // Sebelum perbaikan ini titik tersebut dibuang sebagai pemisah ribuan:
    // `770874.052` tersimpan sebagai `770874052` — seribu kali lipat — dan
    // sembilan digit penuh sehingga isiannya tidak dapat diketik lagi.
    test('770874.052 ditulis sebagai 770874,052', () {
      expect(_ketik('770874.052'), '770874,052');
    });

    test('koma menghasilkan hal yang sama', () {
      expect(_ketik('770874,052'), '770874,052');
    });

    test('titik dan koma menghasilkan angka yang SAMA', () {
      expect(parseKoordinat(_ketik('9224128.858')),
          parseKoordinat(_ketik('9224128,858')));
    });

    test('nilainya bukan seribu kali lipat', () {
      final x = parseKoordinat(_ketik('770874.052'))!;
      expect(x, closeTo(770874.052, 0.0005));
      // Penjaga yang sesungguhnya: kekeliruan lamanya menghasilkan
      // 770.874.052 — dan itu yang membuat titiknya melenceng 770 km.
      expect(x, lessThan(1000000));
    });
  });

  group('TIDAK ada pemisah ribuan sambil diketik', () {
    // Diminta Daniel, 22 Okt 2026. Pengelompokan sambil mengetik itulah
    // yang membuat titik ketikan orang tidak dapat dibedakan dari titik
    // pasangan mesin — lihat `KoordinatInputFormatter`.
    test('enam digit tetap polos', () {
      expect(_ketik('770874'), '770874');
    });

    test('tujuh digit tetap polos', () {
      expect(_ketik('9224128'), '9224128');
    });

    test('tidak ada titik yang muncul sendiri', () {
      expect(_ketik('9224128.858').contains('.'), isFalse);
    });
  });

  group('titik sesudah koma tetap diabaikan', () {
    // Di sini titiknya TIDAK dapat berarti desimal: desimalnya sudah ada.
    test('titik kedua tidak menggeser apa pun', () {
      expect(_ketik('770874,052.'), '770874,052');
    });

    test('desimal dibatasi tiga angka', () {
      expect(_ketik('770874.0525'), '770874,052');
    });
  });

  test('batas digit bulat tetap berlaku', () {
    final f = KoordinatInputFormatter(maxIntDigits: 7);
    expect(_ketik('12345678', formatter: f), '1234567');
  });

  test('minus dipertahankan', () {
    expect(_ketik('-1234.5'), '-1234,5');
  });
}
