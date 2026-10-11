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
