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

/// KOORDINAT — angka polos sambil diketik, TANPA pemisah ribuan.
///
/// DIMINTA DANIEL, 22 Oktober 2026: "mending untuk yang input kalau emang
/// lu gabisa, mending gausah pakai thousand separator deh bang".
///
/// Versi sebelumnya mengelompokkan ribuan sambil diketik, dan itulah yang
/// melahirkan kekeliruannya: dengan titik dipakai sebagai pemisah ribuan,
/// titik yang DIKETIK orang tidak dapat lagi dibedakan dari titik yang
/// dipasang formatter ini sendiri — isian ini membaca ulang keluarannya
/// sendiri pada tiap ketukan. Royan mengetik `770874.052`, titiknya dibuang
/// sebagai pemisah ribuan, dan yang tersimpan `770874052`: seribu kali
/// lipat, sembilan digit penuh, isian mati.
///
/// Tanpa pengelompokan, keduanya tidak dapat lagi tertukar: titik mana pun
/// yang muncul di isian ini pasti diketik orang, jadi ia pemisah desimal.
/// Koma diterima sama persis — papan tombol angka Android menaruh keduanya
/// berdampingan, dan yang memegang HP di lapangan tidak boleh perlu tahu
/// yang mana yang "benar".
///
/// Yang DIBACA tetap dikelompokkan (`formatKoordinat`). Mengetik dan
/// membaca memang dua hal yang berbeda: saat membaca, kelompok ribuan
/// menolong mata memeriksa jumlah digit; saat mengetik, ia justru
/// memasukkan huruf yang tidak diketik siapa pun ke dalam teks yang sedang
/// dibaca ulang mesin.
class KoordinatInputFormatter extends TextInputFormatter {
  KoordinatInputFormatter({this.decimals = 3, this.maxIntDigits = 9});

  final int decimals;
  final int maxIntDigits;

  static bool _digit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final mentah = newValue.text;
    final minus = mentah.startsWith('-');

    // Titik MAUPUN koma diterima sebagai pemisah desimal; yang disimpan
    // selalu koma, supaya `parseKoordinat` dan seluruh tampilan lain
    // membaca bentuk yang sama.
    final angka = StringBuffer();
    var adaKoma = false;
    for (final c in mentah.split('')) {
      if (_digit(c)) {
        angka.write(c);
      } else if ((c == ',' || c == '.') && !adaKoma && decimals > 0) {
        adaKoma = true;
        angka.write(',');
      }
    }

    final teks = angka.toString();
    final bulat = adaKoma ? teks.split(',').first : teks;
    if (bulat.length > maxIntDigits) return oldValue;
    final diketik = adaKoma ? teks.split(',').last : '';
    final pecahan =
        diketik.length > decimals ? diketik.substring(0, decimals) : diketik;

    final hasil = (minus ? '-' : '') + bulat + (adaKoma ? ',$pecahan' : '');

    // Kursor dihitung dari BANYAKNYA huruf yang dipertahankan di sebelah
    // kirinya. Tanpa pengelompokan, tidak ada lagi huruf yang muncul atau
    // hilang di tengah teks, jadi ini sudah cukup — dan `clamp` menangani
    // satu-satunya penyusutan yang tersisa, yaitu desimal yang dipangkas.
    var jaga = 0;
    var komaDipakai = false;
    for (var i = 0; i < newValue.selection.end && i < mentah.length; i++) {
      final c = mentah[i];
      if (i == 0 && c == '-' && minus) {
        jaga++;
      } else if (_digit(c)) {
        jaga++;
      } else if ((c == ',' || c == '.') && !komaDipakai && decimals > 0) {
        komaDipakai = true;
        jaga++;
      }
    }

    return TextEditingValue(
      text: hasil,
      selection: TextSelection.collapsed(offset: jaga.clamp(0, hasil.length)),
    );
  }
}

/// Shorthand untuk isian koordinat.
List<TextInputFormatter> koordinatInput({int decimals = 3, int maxIntDigits = 9}) =>
    [KoordinatInputFormatter(decimals: decimals, maxIntDigits: maxIntDigits)];
