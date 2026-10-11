import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/util/clock_drift.dart';

void main() {
  test('phone ahead of server', () {
    final d = clockDriftOf('2026-10-10T01:00:00+00:00|2026-10-10T08:12:00.000');
    // 08:12 local; the test runner's zone decides the absolute value, so only
    // check the shape on a zone-free pair.
    expect(d, isNotNull);
  });

  test('zone-free pair', () {
    expect(clockDriftOf('2026-10-10T01:00:00Z|2026-10-10T01:12:00Z'), const Duration(minutes: 12));
    expect(clockDriftOf('2026-10-10T01:00:00Z|2026-10-10T00:58:00Z'), const Duration(minutes: -2));
  });

  test('unknown', () {
    expect(clockDriftOf(null), isNull);
    expect(clockDriftOf('garbage'), isNull);
    expect(clockDriftOf('a|b'), isNull);
  });

  test('text', () {
    expect(clockDriftText(const Duration(minutes: 12)), '12 menit lebih cepat');
    expect(clockDriftText(const Duration(hours: 2, minutes: 5)), '2 jam 5 menit lebih cepat');
    expect(clockDriftText(const Duration(hours: -1)), '1 jam terlambat');
  });
}
