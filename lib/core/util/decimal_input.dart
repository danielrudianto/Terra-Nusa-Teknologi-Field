import 'package:flutter/services.dart';

/// Keeps a number field to a sane shape WHILE typing: at most [maxIntDigits]
/// digits before the decimal mark, at most [decimals] after it, one decimal
/// mark (comma or dot), and a leading minus only when [signed].
///
/// A keystroke that would break the shape is simply ignored, so "18888888"
/// cannot be typed into a depth field. The range check (e.g. ≤ 200 m) still
/// happens on save; this only stops the absurd input early.
class DecimalInputFormatter extends TextInputFormatter {
  DecimalInputFormatter({required this.maxIntDigits, this.decimals = 2, this.signed = false})
      : _pattern = RegExp(
          '^${signed ? '-?' : ''}\\d{0,$maxIntDigits}'
          '${decimals > 0 ? '([.,]\\d{0,$decimals})?' : ''}\$',
        );

  final int maxIntDigits;
  final int decimals;
  final bool signed;
  final RegExp _pattern;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(' ', '');
    if (!_pattern.hasMatch(text)) return oldValue;
    if (text == newValue.text) return newValue;
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Shorthand for `inputFormatters:`.
List<TextInputFormatter> decimalInput({required int maxIntDigits, int decimals = 2, bool signed = false}) =>
    [DecimalInputFormatter(maxIntDigits: maxIntDigits, decimals: decimals, signed: signed)];

/// KOORDINAT dengan pemisah ribuan, DIKELOMPOKKAN SAMBIL DIKETIK.
///
/// DIMINTA DANIEL, 20 Oktober 2026: "koordinat kadang angkanya besar
/// banget, minta tolong ada thousand separator pas input ataupun pas di
/// view".
///
/// Koordinat grid lokal berbentuk seperti `792345.120`. Tanpa pengelompokan,
/// yang mengetik tidak punya cara memeriksa apakah ia sudah mengetik enam
/// digit atau tujuh — dan satu digit kelebihan pada koordinat menggeser
/// titiknya sejauh satu kilometer, tanpa satu pun tanda di layar.
///
/// TITIK untuk ribuan, KOMA untuk desimal — sama dengan seluruh angka lain
/// di aplikasi ini (`formatMeters`). Jangan dibalik hanya di satu isian:
/// yang mengetik membaca layar yang sama sepanjang hari.
///
/// KURSORNYA DIJAGA menurut JUMLAH DIGIT di sebelah kirinya, bukan menurut
/// posisi hurufnya. Setiap titik ribuan yang muncul atau hilang menggeser
/// seluruh teks, dan kursor yang dipasang pada posisi lama akan melompat
/// satu huruf setiap tiga digit — cukup untuk membuat isian ini tidak dapat
/// dipakai dengan satu tangan di lapangan.
class KoordinatInputFormatter extends TextInputFormatter {
  KoordinatInputFormatter({this.decimals = 3, this.maxIntDigits = 9});

  final int decimals;
  final int maxIntDigits;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final mentah = newValue.text;
    final minus = mentah.startsWith('-');

    // Hanya digit dan SATU pemisah desimal yang dipertahankan. Titik yang
    // diketik sendiri oleh pemakainya diperlakukan sebagai pemisah ribuan
    // dan dibuang — yang menentukan desimal hanyalah koma.
    final angka = StringBuffer();
    var adaKoma = false;
    for (final c in mentah.split('')) {
      if (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) {
        angka.write(c);
      } else if (c == ',' && !adaKoma && decimals > 0) {
        adaKoma = true;
        angka.write(',');
      }
    }

    var teks = angka.toString();
    var bulat = adaKoma ? teks.split(',').first : teks;
    var pecahan = adaKoma ? teks.split(',').last : '';
    if (bulat.length > maxIntDigits) return oldValue;
    if (pecahan.length > decimals) {
      pecahan = pecahan.substring(0, decimals);
    }

    final dikelompokkan = _kelompok(bulat);
    final hasil = (minus ? '-' : '') +
        dikelompokkan +
        (adaKoma ? ',$pecahan' : '');

    // Digit (dan koma) di kiri kursor pada teks yang BARU diketik.
    var digitKiri = 0;
    for (var i = 0; i < newValue.selection.end && i < mentah.length; i++) {
      final c = mentah[i];
      if ((c.compareTo('0') >= 0 && c.compareTo('9') <= 0) || c == ',') {
        digitKiri++;
      }
    }
    var posisi = hasil.length;
    var hitung = 0;
    for (var i = 0; i < hasil.length; i++) {
      final c = hasil[i];
      if ((c.compareTo('0') >= 0 && c.compareTo('9') <= 0) || c == ',') {
        hitung++;
      }
      if (hitung == digitKiri) {
        posisi = i + 1;
        break;
      }
    }
    if (digitKiri == 0) posisi = minus ? 1 : 0;

    return TextEditingValue(
      text: hasil,
      selection: TextSelection.collapsed(offset: posisi.clamp(0, hasil.length)),
    );
  }

  static String _kelompok(String digit) {
    if (digit.length <= 3) return digit;
    final keluar = StringBuffer();
    final sisa = digit.length % 3;
    if (sisa > 0) keluar.write(digit.substring(0, sisa));
    for (var i = sisa; i < digit.length; i += 3) {
      if (keluar.isNotEmpty) keluar.write('.');
      keluar.write(digit.substring(i, i + 3));
    }
    return keluar.toString();
  }
}

/// Shorthand untuk isian koordinat.
List<TextInputFormatter> koordinatInput({int decimals = 3, int maxIntDigits = 9}) =>
    [KoordinatInputFormatter(decimals: decimals, maxIntDigits: maxIntDigits)];
