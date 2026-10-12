import '../../core/util/format.dart';
import '../../core/i18n.dart';

/// One drilling reading: at [at] the hole was [depthM] deep (from GS).
class DrillReading {
  const DrillReading({required this.uuid, required this.at, required this.depthM, this.note});

  final String uuid;
  final DateTime at;
  final double depthM;
  final String? note;

  static DrillReading? fromJson(Map<String, Object?> j) {
    final at = DateTime.tryParse('${j['at']}');
    final depth = toDoubleOrNull(j['depthM']);
    if (at == null || depth == null) return null;
    final note = j['note']?.toString();
    return DrillReading(uuid: '${j['uuid']}', at: at, depthM: depth, note: note == null || note.isEmpty ? null : note);
  }
}

/// The readings of a drill log body, oldest first.
List<DrillReading> readingsOf(Map<String, Object?>? body) {
  final list = [
    for (final e in (body?['entries'] as List?) ?? const [])
      ?DrillReading.fromJson((e as Map).cast<String, Object?>()),
  ];
  list.sort((a, b) => a.at.compareTo(b.at));
  return list;
}

/// Deepest reading so far; null with none.
double? deepestM(List<DrillReading> readings) =>
    readings.isEmpty ? null : readings.map((r) => r.depthM).reduce((a, b) => a > b ? a : b);

/// Why a reading of [depthM] at [at] cannot go in among [readings], or null.
///
/// A hole never gets shallower: a reading must be at least as deep as every
/// earlier one and no deeper than any later one. [replacing] is the reading
/// being edited, left out of the comparison. The server checks the same
/// (KEDALAMAN_MUNDUR); stopping it here saves a rejected send.
String? readingProblem(List<DrillReading> readings, DateTime at, double depthM, {String? replacing}) {
  for (final r in readings) {
    if (r.uuid == replacing) continue;
    // The RULE never depends on the language; only its sentence does, and
    // that falls back to Indonesian when there is no screen (tests).
    if (!r.at.isAfter(at) && r.depthM > depthM + 0.0005) {
      return L10n.current?.readingShallower(formatTime(r.at), formatMeters(r.depthM)) ??
          'Lebih dangkal dari bacaan jam ${formatTime(r.at)} (${formatMeters(r.depthM)}). Lubang tidak bisa makin dangkal.';
    }
    if (r.at.isAfter(at) && r.depthM < depthM - 0.0005) {
      return L10n.current?.readingDeeperThanNext(formatTime(r.at), formatMeters(r.depthM)) ??
          'Lebih dalam dari bacaan berikutnya jam ${formatTime(r.at)} (${formatMeters(r.depthM)}). Periksa jamnya.';
    }
  }
  return null;
}

/// Hard limit of a drill depth reading, the same as the server's.
const maxDrillDepthM = 200.0;

/// Over-drilling up to this far past the planned length is normal: operators
/// drill a little deeper on purpose so the hole, while it waits for the cage
/// and the concrete, does not silt up to less than the planned length. It
/// passes without a word.
const overPlanToleranceM = 1.5;

/// Past this the number is refused outright: more than 5 m past the plan is
/// a typo, a wrong point or a wrong GS, never a real reading.
const overPlanLimitMeters = 5.0;

double overPlanLimitM(double plannedM) => overPlanLimitMeters;

/// Metres a depth goes past the plan when that is more than the tolerance,
/// or null when it is within it (or there is no plan). Only a warning on
/// screen ("sudah lewat sedikit"); saving is not blocked.
double? beyondPlanM(double depthM, double? plannedM) {
  if (plannedM == null || plannedM <= 0) return null;
  final over = depthM - plannedM;
  return over > overPlanToleranceM ? over : null;
}

/// Whether a depth is too far past the plan to be accepted at all.
bool farBeyondPlan(double depthM, double? plannedM) =>
    plannedM != null && plannedM > 0 && depthM - plannedM > overPlanLimitM(plannedM);

/// The sentence for a refused depth.
String farBeyondPlanText(double depthM, double plannedM) {
  String two(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
  final max = two(plannedM + overPlanLimitM(plannedM));
  return L10n.current?.depthFarFromPlan(two(depthM), two(plannedM), max) ??
      '${two(depthM)} m terlalu jauh dari rencana ${two(plannedM)} m '
          '(paling dalam $max m). Periksa angkanya, titiknya, atau elevasi GS.';
}

/// Why a typed depth can never be saved, or null. Checked while typing so the
/// save button can be disabled with the reason shown.
String? depthRefusal(double? depthM, double? plannedM) {
  if (depthM == null) return null;
  if (depthM > maxDrillDepthM) {
    return L10n.current?.drillDepthTooDeep(formatMeters(maxDrillDepthM, decimals: 0)) ??
        'Kedalaman paling dalam ${formatMeters(maxDrillDepthM, decimals: 0)}. Periksa angkanya.';
  }
  if (plannedM != null && farBeyondPlan(depthM, plannedM)) return farBeyondPlanText(depthM, plannedM);
  return null;
}
