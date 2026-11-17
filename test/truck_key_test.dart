import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/gate/truck_key.dart';

void main() {
  test('the same number typed differently gives the same key', () {
    expect(truckKey('TM 1000'), truckKey('1000'));
    expect(truckKey('tm-a984'), truckKey('TM A984'));
    expect(truckKey(' k9221 '), truckKey('TM.K9221'));
  });

  test('different numbers give different keys', () {
    expect(truckKey('TM 1000') == truckKey('TM 1001'), isFalse);
  });

  test('nothing to compare gives an empty key', () {
    expect(truckKey(null), '');
    expect(truckKey('  '), '');
    expect(truckKey('--'), '');
  });

  test('"TM" alone is not trimmed down to nothing', () {
    expect(truckKey('TM'), 'TM');
  });
}
