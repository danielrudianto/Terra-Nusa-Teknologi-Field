import 'dart:math' as math;

import 'volume.dart';

/// TREMIE CUT RECOMMENDATION
///
/// The tremie's bottom end must always be EMBEDDED in fresh concrete: at least
/// 1 m (less than that, new concrete can break through the concrete level and mix with
/// mud), at most 6 m (more than that, the concrete no longer flows
/// out and the tremie can get jammed). Safe target: leave ±2 m after
/// each cut.
///
/// What gets removed is always the TOP segment (the one attached to the hopper), and the
/// bottom-most segment is never removed — it is the one that is embedded.
///
/// Each time a segment of length L is removed, the whole tremie rises by L: its bottom
/// end rises L, and its embedment decreases by L.
///
/// This algorithm is a SUGGESTION. The QS is still the one who ticks which segment is
/// actually removed; the app never treats a suggestion as an event.
/// Its Python prototype is in the design notes; the test numbers in
/// `test/cut_plan_test.dart` were taken from that prototype.

class EmbedmentLimits {
  const EmbedmentLimits({this.minimumM = 1.0, this.maximumM = 6.0, this.targetM = 2.0});

  final double minimumM;
  final double maximumM;
  final double targetM;
}

class Segment {
  const Segment({required this.key, required this.lengthM});

  /// segment uuid (or index in tests).
  final String key;
  final double lengthM;
}

class CutSuggestion {
  const CutSuggestion({
    required this.afterM3,
    required this.toRemove,
    required this.embedmentBeforeM,
    required this.embedmentAfterM,
  });

  /// Remove after this many m³ from this truck have gone in.
  final double afterM3;

  /// Ordered from the TOP — the order in which they are removed.
  final List<Segment> toRemove;
  final double embedmentBeforeM;
  final double embedmentAfterM;

  double get lengthM => toRemove.fold(0.0, (a, s) => a + s.lengthM);
}

enum WarningKind {
  /// Embedment will exceed the maximum and no segment can be
  /// removed without bringing embedment below the minimum.
  cannotRemove,

  /// Embedment is already below the minimum BEFORE this truck — check the sounding.
  embedmentTooShort,
}

class CastingWarning {
  const CastingWarning(this.kind, {required this.afterM3, required this.embedmentM});

  final WarningKind kind;
  final double afterM3;
  final double embedmentM;
}

class TruckPlan {
  const TruckPlan({
    required this.cuts,
    required this.warnings,
    required this.finalEmbedmentM,
    required this.finalConcreteDepthM,
    required this.remainingSegments,
    required this.cutOffReached,
  });

  final List<CutSuggestion> cuts;
  final List<CastingWarning> warnings;
  final double finalEmbedmentM;
  final double finalConcreteDepthM;

  /// Bottom → top.
  final List<Segment> remainingSegments;
  final bool cutOffReached;
}

/// Plan for ONE truck about to be cast.
///
/// * [tremieBottomM] — depth of the tremie's bottom end from the CURRENT GS.
/// * [segments] — installed segments, ordered BOTTOM → TOP.
/// * [concreteDepthM] — concrete level depth before this truck (hole bottom
///   if it is the first truck).
/// * [ratio] — overbreak ratio (1.0 = theoretical); use the average of trucks that
///   have already been sounded, if any.
/// * [isFirstTruck] — first truck: no concrete in the hole yet, the tremie's end
///   is still ABOVE the bottom (bottom gap). Negative embedment here is a
///   normal starting state, not a danger sign.
///
/// The [WarningKind.embedmentTooShort] warning is only for the second truck and
/// onward: in the middle of casting, a tremie embedded less than 1 m
/// means new concrete can break through the concrete level and mix with mud.
TruckPlan planTruck({
  required int diameterMm,
  required double tremieBottomM,
  required List<Segment> segments,
  required double concreteDepthM,
  required double cutOffDepthM,
  required double volumeM3,
  double ratio = 1.0,
  bool isFirstTruck = false,
  EmbedmentLimits limits = const EmbedmentLimits(),
  double stepM3 = 0.05,
}) {
  final rise = risePerM3(diameterMm, ratio: ratio);
  var segs = List<Segment>.of(segments);
  var bottom = tremieBottomM;
  final cuts = <CutSuggestion>[];
  final warnings = <CastingWarning>[];

  double concreteAt(double v) => math.max(cutOffDepthM, concreteDepthM - v * rise);

  final initial = bottom - concreteAt(0);
  if (!isFirstTruck && initial < limits.minimumM - 1e-9) {
    warnings.add(CastingWarning(WarningKind.embedmentTooShort, afterM3: 0, embedmentM: _round2(initial)));
  }

  var v = 0.0;
  var stuck = false;
  while (v < volumeM3 - 1e-9) {
    final v2 = math.min(volumeM3, v + stepM3);
    final t2 = bottom - concreteAt(v2);
    if (t2 > limits.maximumM + 1e-9 && !stuck) {
      final tNow = bottom - concreteAt(v);
      final chosen = chooseSegmentsToRemove(segs, tNow, limits);
      if (chosen.isEmpty) {
        warnings.add(CastingWarning(WarningKind.cannotRemove, afterM3: _round2(v), embedmentM: _round2(tNow)));
        stuck = true; // one warning is enough; continue without removing
      } else {
        final total = chosen.fold(0.0, (a, s) => a + s.lengthM);
        cuts.add(CutSuggestion(
          afterM3: _round2(v),
          toRemove: chosen,
          embedmentBeforeM: _round2(tNow),
          embedmentAfterM: _round2(tNow - total),
        ));
        segs = segs.sublist(0, segs.length - chosen.length);
        bottom -= total;
        continue;
      }
    }
    v = v2;
    if (concreteAt(v) <= cutOffDepthM + 1e-9) break;
  }

  final finalDepth = concreteAt(volumeM3);
  return TruckPlan(
    cuts: cuts,
    warnings: warnings,
    finalEmbedmentM: _round2(bottom - finalDepth),
    finalConcreteDepthM: _round2(finalDepth),
    remainingSegments: segs,
    cutOffReached: finalDepth <= cutOffDepthM + 1e-9,
  );
}

/// Segments suggested to be removed NOW, from the measured [embedmentM].
///
/// From the TOP, as many as possible while the embedment afterwards is ≥ the target;
/// if the target cannot be met with even one segment, ≥ the minimum. The bottom-most
/// segment is never removed. Empty = do not remove anything.
List<Segment> chooseSegmentsToRemove(List<Segment> segments, double embedmentM, EmbedmentLimits limits) {
  for (final threshold in [limits.targetM, limits.minimumM]) {
    var total = 0.0;
    final chosen = <Segment>[];
    for (final s in segments.skip(1).toList().reversed) {
      if (embedmentM - (total + s.lengthM) < threshold - 1e-9) break;
      total += s.lengthM;
      chosen.add(s);
    }
    if (chosen.isNotEmpty) return chosen;
  }
  return const [];
}

double _round2(double x) => (x * 100).roundToDouble() / 100;
