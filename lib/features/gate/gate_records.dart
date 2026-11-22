import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'truck_key.dart';

/// Gate records of ONE pile point on this phone, live.
///
/// Watched, not read once: the list changes the moment a pull brings a new
/// gate record, so the person at the hole sees it arrive without leaving
/// the screen. Rejected trucks are left out — they were never poured.
///
/// Reported by Daniel, 22 Nov 2026: "Data gerbang suka ga masuk ke orang
/// lubang cor. Terus tiap kali ga masuk orang di lubang isiin dari awal".
/// The hole screen used to read this list once, when a sheet opened; a
/// record that arrived a minute later was invisible until the screen was
/// reopened, and the truck card never showed what the gate had recorded.
final gateTicketsOfPileProvider =
    StreamProvider.autoDispose.family<List<Map<String, Object?>>, String>(
  (ref, pileUuid) => ref.watch(dbProvider).watchMaster('gate_ticket').map(
        (all) => [
          for (final g in all)
            if ('${g['pilePointUuid']}' == pileUuid && g['rejected'] != true) g,
        ],
      ),
);

/// The gate records above, keyed by [truckKey] — the same pairing the
/// server makes (`truck_key` in `field_controller.py`). Records without a
/// readable number pair with nothing and are left out.
Map<String, Map<String, Object?>> gateByTruckKey(List<Map<String, Object?>> tickets) => {
      for (final g in tickets)
        if (truckKey(g['truckNo']?.toString()).isNotEmpty) truckKey(g['truckNo']?.toString()): g,
    };

/// Truck numbers the gate recorded and the log has not used yet, oldest
/// arrival first — the order the trucks stand in at the hole.
List<String> unusedGateNumbers(List<Map<String, Object?>> tickets, Set<String> usedKeys) {
  final sorted = [...tickets]..sort((a, b) => '${a['arrivedAt'] ?? ''}'.compareTo('${b['arrivedAt'] ?? ''}'));
  final seen = {...usedKeys};
  final out = <String>[];
  for (final g in sorted) {
    final number = '${g['truckNo'] ?? ''}'.trim();
    final key = truckKey(number);
    if (key.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    out.add(number);
  }
  return out;
}
