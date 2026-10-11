import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/db/app_database.dart';
import 'package:terrabot_field/core/providers.dart';
import 'package:terrabot_field/core/util/format.dart';
import 'package:terrabot_field/core/util/distance.dart';

void main() {
  test('isoWithOffset always writes the offset', () {
    final t = isoWithOffset(DateTime(2026, 10, 8, 7, 12, 3, 412));
    expect(t, matches(RegExp(r'^2026-10-08T07:12:03\.412[+-]\d\d:\d\d$')));
  });

  test('parseNumber accepts comma and period', () {
    expect(parseNumber('7,5'), 7.5);
    expect(parseNumber(' 7.5 '), 7.5);
    expect(parseNumber('abc'), isNull);
  });

  test('decimalText is sent as text with fixed decimals', () {
    expect(decimalText(7.1), '7.10');
    expect(decimalText(12.5, decimals: 1), '12.5');
  });

  test('distance: ±111 km per degree of latitude', () {
    expect(distanceMeters(-6.2, 106.8, -5.2, 106.8), closeTo(111195, 50));
    expect(distanceMeters(-6.2, 106.8, -6.2, 106.8), 0);
  });

  test('retry delay grows exponentially, maximum 30 minutes', () {
    expect(retryDelay(1), const Duration(seconds: 30));
    expect(retryDelay(2), const Duration(minutes: 1));
    expect(retryDelay(99), const Duration(minutes: 30));
  });

  group('isCastingProject', () {
    test('ongoing project with casting work is shown', () {
      expect(isCastingProject({'code': 'R501', 'isRetention': false, 'fieldCastingEnabled': true}), isTrue);
    });

    test('project switched off by the office is hidden (MCHP, PGDN)', () {
      expect(isCastingProject({'code': 'MCHP', 'isRetention': false, 'fieldCastingEnabled': false}), isFalse);
      expect(isCastingProject({'code': 'PGDN', 'fieldCastingEnabled': 0}), isFalse);
    });

    test('project in retention is hidden', () {
      expect(isCastingProject({'code': 'R35CH', 'isRetention': true, 'fieldCastingEnabled': true}), isFalse);
    });

    test('older server without the fields still shows the project', () {
      expect(isCastingProject({'code': 'R501'}), isTrue);
    });
  });
}
