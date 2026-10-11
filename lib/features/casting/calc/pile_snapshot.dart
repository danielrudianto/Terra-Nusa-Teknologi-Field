import 'casting_state.dart';

/// What the live cross-section draws, all as DEPTH from GS in metres.
///
/// While a truck is pouring, nobody can measure the concrete level, so the
/// "now" level is an estimate: the level before the truck moved toward the
/// level its full volume should reach, in proportion to how long it has
/// been pouring compared with a typical truck. It is always marked as an
/// estimate on screen; a sounding replaces it.
class PileSnapshot {
  const PileSnapshot({
    required this.bottomDepthM,
    required this.cutOffDepthM,
    required this.concreteNowM,
    required this.concreteMeasured,
    required this.concreteTargetM,
    required this.tremieBottomM,
    required this.tremieSegmentsM,
    required this.hasBottomPiece,
  });

  /// Hole bottom (actual drilled depth if marked, else planned).
  final double bottomDepthM;
  final double cutOffDepthM;

  /// Concrete level now. Equal to [bottomDepthM] before any concrete.
  final double concreteNowM;
  final bool concreteMeasured;

  /// Where the truck being poured should bring the level when emptied.
  /// Null when no truck is pouring.
  final double? concreteTargetM;

  /// Tremie bottom end, and the installed segments from the TOP down.
  final double tremieBottomM;
  final List<double> tremieSegmentsM;
  final bool hasBottomPiece;

  /// Tremie inside fresh concrete. Negative = the end is above the concrete.
  double get embedmentM => tremieBottomM - concreteNowM;

  bool get cutOffReached => concreteNowM <= cutOffDepthM + 0.005;
}

/// Snapshot of [k] right now.
///
/// [pouringSeq] is the truck being poured (null when none), [poured] how long
/// it has poured (pauses not counted) and [typicalPour] how long a truck
/// usually takes on this pile.
PileSnapshot pileSnapshot(
  CastingState k, {
  int? pouringSeq,
  Duration poured = Duration.zero,
  Duration typicalPour = const Duration(minutes: 12),
}) {
  final last = k.lastSeq;
  // The last truck whose concrete is fully in.
  final doneSeq = pouringSeq == null ? last : pouringSeq - 1;
  final before = k.concreteAfter(doneSeq);

  double now = before.depthM;
  bool measured = before.measured;
  double? target;
  if (pouringSeq != null) {
    final truck = k.trucks.where((t) => t.seq == pouringSeq).firstOrNull;
    final start = truck?.concreteBeforeM ?? before.depthM;
    // Full volume in: the estimate the plan also uses (never past cut-off).
    target = k.concreteAfter(pouringSeq).depthM;
    final share = typicalPour.inSeconds <= 0 ? 1.0 : (poured.inSeconds / typicalPour.inSeconds).clamp(0.0, 1.0);
    now = start + (target - start) * share;
    measured = false;
  }

  final tremieSeq = pouringSeq ?? last;
  final installed = k.installedAfter(tremieSeq);
  return PileSnapshot(
    bottomDepthM: k.geometry.bottomDepthM,
    cutOffDepthM: k.geometry.cutOffDepthM,
    concreteNowM: now,
    concreteMeasured: measured,
    concreteTargetM: target,
    tremieBottomM: k.tremieBottomAfter(tremieSeq),
    tremieSegmentsM: [for (final s in installed.reversed) s.lengthM],
    hasBottomPiece: installed.any((s) => s.isBottom),
  );
}
