import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/drilling/drill_readings.dart';

void main() {
  DateTime at(int h, int m) => DateTime(2026, 10, 9, h, m);
  final readings = [
    DrillReading(uuid: 'a', at: at(8, 0), depthM: 3),
    DrillReading(uuid: 'b', at: at(8, 45), depthM: 7.5),
    DrillReading(uuid: 'c', at: at(9, 30), depthM: 12),
  ];

  test('readings come back oldest first, whatever order they were saved in', () {
    final r = readingsOf({
      'entries': [
        {'uuid': 'c', 'at': at(9, 30).toIso8601String(), 'depthM': '12.00'},
        {'uuid': 'a', 'at': at(8, 0).toIso8601String(), 'depthM': '3.00', 'note': ''},
      ],
    });
    expect(r.map((x) => x.uuid), ['a', 'c']);
    expect(r.first.note, isNull);
    expect(deepestM(r), 12);
  });

  test('a new reading deeper than the last one is fine', () {
    expect(readingProblem(readings, at(10, 0), 15), isNull);
  });

  test('a new reading shallower than an earlier one is stopped', () {
    expect(readingProblem(readings, at(10, 0), 10), contains('09:30'));
  });

  test('a back-dated reading deeper than a later one is stopped', () {
    expect(readingProblem(readings, at(8, 30), 9), contains('Periksa jamnya'));
  });

  test('editing a reading leaves itself out of the check', () {
    expect(readingProblem(readings, at(9, 30), 11, replacing: 'c'), isNull);
    expect(readingProblem(readings, at(9, 30), 7, replacing: 'c'), isNotNull);
  });

  test('no readings: no deepest', () {
    expect(deepestM(const []), isNull);
  });

  test('beyond plan only past the 1,5 m tolerance', () {
    expect(beyondPlanM(22.5, 21.16), isNull);
    expect(beyondPlanM(22.66, 21.16), isNull);
    expect(beyondPlanM(23, 21.16), closeTo(1.84, 1e-9));
    expect(beyondPlanM(30, null), isNull);
  });

  test('far beyond plan: more than 5 m past it', () {
    expect(farBeyondPlan(25, 20), isFalse);
    expect(farBeyondPlan(25.01, 20), isTrue);
    expect(farBeyondPlan(50, 20), isTrue);
    expect(farBeyondPlan(13, 8), isFalse);
    expect(farBeyondPlan(13.5, 8), isTrue);
    expect(farBeyondPlan(500, null), isFalse);
  });
}
