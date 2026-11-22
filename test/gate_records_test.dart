import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/gate/gate_records.dart';

Map<String, Object?> gate(String no, {String at = '2026-11-22T10:00:00+07:00', String vol = '6.00'}) =>
    {'truckNo': no, 'arrivedAt': at, 'volumeM3': vol, 'pilePointUuid': 'p1'};

void main() {
  test('gate records pair by truck key, the way the server pairs them', () {
    final byKey = gateByTruckKey([gate('TM 930'), gate('')]);
    expect(byKey.keys, ['930']);
    expect(byKey['930']!['volumeM3'], '6.00');
  });

  test('numbers offered at the hole: oldest arrival first, used ones left out', () {
    final numbers = unusedGateNumbers([
      gate('969', at: '2026-11-22T10:20:00+07:00'),
      gate('930', at: '2026-11-22T10:00:00+07:00'),
      gate('893', at: '2026-11-22T10:10:00+07:00'),
    ], {'893'});
    expect(numbers, ['930', '969']);
  });

  test('the same truck typed two ways is offered once', () {
    expect(unusedGateNumbers([gate('TM-930'), gate('930')], {}), ['TM-930']);
  });
}
