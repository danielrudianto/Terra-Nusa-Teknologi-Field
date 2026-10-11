import 'dart:math' as math;

/// Bored pile geometry calculation — the SAME as `hitung_cor` on the server
/// (`utils/field_hitung.py`). On the phone it is for display while casting; the
/// recorded figures remain the server's calculation.
///
/// ELEVATION vs DEPTH
///
/// The working drawings give ELEVATION (m, increasing upward): GS (ground surface at
/// that point), cut-off (how high the concrete is cast), tip (planned bottom). In the
/// hole, the QS measures DEPTH from GS (m, increasing downward): drill depth,
/// depth of the concrete surface (sounding). All calculations below use
/// depth from GS; elevation is converted once in [PileGeometry].

double crossSectionAreaM2(int diameterMm) {
  final d = diameterMm / 1000.0;
  return math.pi / 4 * d * d;
}

class PileGeometry {
  const PileGeometry({
    required this.diameterMm,
    required this.groundLevel,
    required this.cutOffLevel,
    required this.tipLevel,
    this.drilledDepthM,
  });

  final int diameterMm;
  final double groundLevel;
  final double cutOffLevel;
  final double tipLevel;

  /// ACTUAL drill depth from GS (marked by the QS). Null = not drilled yet.
  final double? drilledDepthM;

  double get areaM2 => crossSectionAreaM2(diameterMm);

  /// Cut-off depth from GS — the concrete surface stops here.
  double get cutOffDepthM => groundLevel - cutOffLevel;

  /// Planned drill length = GS − tip.
  double get plannedDrillLengthM => groundLevel - tipLevel;

  /// Planned effective length = cut-off − tip.
  double get plannedEffectiveLengthM => cutOffLevel - tipLevel;

  /// Actual effective length = actual drill depth − cut-off depth.
  double? get actualEffectiveLengthM => drilledDepthM == null ? null : drilledDepthM! - cutOffDepthM;

  double get plannedTheoreticalVolumeM3 => areaM2 * plannedEffectiveLengthM;

  double? get actualTheoreticalVolumeM3 {
    final p = actualEffectiveLengthM;
    return p == null ? null : areaM2 * p;
  }

  /// Hole bottom depth used for calculation: actual if already
  /// marked, planned if not.
  double get bottomDepthM => drilledDepthM ?? plannedDrillLengthM;
}

/// Theoretical rise of the concrete surface per m³ (m/m³), with the overbreak ratio.
///
/// Ratio 1.15 = hole 15% larger than the nominal diameter (collapsed
/// wall / soft soil): the concrete rises more slowly than in theory.
double risePerM3(int diameterMm, {double ratio = 1.0}) =>
    1.0 / (crossSectionAreaM2(diameterMm) * math.max(ratio, 0.2));

/// Overbreak ratio of one TM from the soundings before & after it.
/// Null if not measurable (empty sounding or no rise).
double? overbreakRatio({
  required int diameterMm,
  required double volumeM3,
  required double? depthBeforeM,
  required double? depthAfterM,
}) {
  if (depthBeforeM == null || depthAfterM == null) return null;
  final rise = depthBeforeM - depthAfterM;
  if (rise <= 0.01) return null;
  return volumeM3 / (crossSectionAreaM2(diameterMm) * rise);
}
