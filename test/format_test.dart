import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/inti/db/database.dart';
import 'package:terrabot_field/inti/util/format.dart';
import 'package:terrabot_field/inti/util/jarak.dart';

void main() {
  test('isoBerzona selalu menulis offset', () {
    final t = isoBerzona(DateTime(2026, 10, 8, 7, 12, 3, 412));
    expect(t, matches(RegExp(r'^2026-10-08T07:12:03\.412[+-]\d\d:\d\d$')));
  });

  test('bacaAngka menerima koma dan titik', () {
    expect(bacaAngka('7,5'), 7.5);
    expect(bacaAngka(' 7.5 '), 7.5);
    expect(bacaAngka('abc'), isNull);
  });

  test('angkaTeks dikirim sebagai teks berdesimal tetap', () {
    expect(angkaTeks(7.1), '7.10');
    expect(angkaTeks(12.5, desimal: 1), '12.5');
  });

  test('jarak: ±111 km per derajat lintang', () {
    expect(jarakMeter(-6.2, 106.8, -5.2, 106.8), closeTo(111195, 50));
    expect(jarakMeter(-6.2, 106.8, -6.2, 106.8), 0);
  });

  test('jeda ulang naik berlipat, maksimum 30 menit', () {
    expect(jedaUlang(1), const Duration(seconds: 30));
    expect(jedaUlang(2), const Duration(minutes: 1));
    expect(jedaUlang(99), const Duration(minutes: 30));
  });
}
