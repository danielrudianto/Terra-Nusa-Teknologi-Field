import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/util/decimal_input.dart';

TextEditingValue _v(String t) => TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));

String _type(DecimalInputFormatter f, String from, String to) => f.formatEditUpdate(_v(from), _v(to)).text;

void main() {
  final depth = DecimalInputFormatter(maxIntDigits: 3, decimals: 2);
  final gs = DecimalInputFormatter(maxIntDigits: 4, decimals: 3, signed: true);

  test('limits integer digits', () {
    expect(_type(depth, '188', '1888'), '188');
    expect(_type(depth, '18', '188'), '188');
  });

  test('accepts comma or dot, limits decimals, one mark only', () {
    expect(_type(depth, '21', '21,'), '21,');
    expect(_type(depth, '21,6', '21,64'), '21,64');
    expect(_type(depth, '21,64', '21,645'), '21,64');
    expect(_type(depth, '21.6', '21.64'), '21.64');
    expect(_type(depth, '21,6', '21,6,'), '21,6');
  });

  test('rejects letters and minus unless signed', () {
    expect(_type(depth, '2', '2a'), '2');
    expect(_type(depth, '', '-'), '');
    expect(_type(gs, '', '-'), '-');
    expect(_type(gs, '-1', '-12,345'), '-12,345');
    expect(_type(gs, '1', '1-'), '1');
  });

  test('empty is allowed', () {
    expect(_type(depth, '5', ''), '');
  });
}
