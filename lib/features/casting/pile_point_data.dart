import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/providers.dart';
import '../../core/util/format.dart';
import '../drilling/drill_readings.dart';
import 'calc/volume.dart';

/// One pile point as SEEN by the QS: server data + what has been
/// recorded on this phone but is not necessarily pushed yet.
class FieldPilePoint {
  const FieldPilePoint({
    required this.server,
    this.localDrillDepthM,
    this.localGroundLevel,
    this.casting,
    this.drillLog,
  });

  final Map<String, Object?> server;

  /// Drill depth from the drill mark on the phone (latest), if any.
  final double? localDrillDepthM;

  /// Ground level sent with the latest drill mark on the phone, if any.
  final double? localGroundLevel;

  /// Casting log on this phone for this point.
  final DocumentRow? casting;

  /// Drill log on this phone for this point.
  final DocumentRow? drillLog;

  Map<String, Object?>? get drillLogBody => drillLog == null ? null : (jsonDecode(drillLog!.body) as Map).cast<String, Object?>();

  /// The drill log the SERVER holds for this point, from any phone.
  String? get serverDrillLogUuid => server['drillLogUuid'] == null ? null : '${server['drillLogUuid']}';
  String? get serverDrillLogBy => server['drillLogByName']?.toString();

  /// Another phone holds this point's drill log: a second one is refused
  /// (LOG_BOR_SUDAH_ADA), so "Mulai log bor" is closed here.
  bool get drillLoggedElsewhere => drillLog == null && serverDrillLogUuid != null;

  String get uuid => '${server['uuid']}';
  String get code => '${server['code']}';
  int get diameterMm => toIntOrNull(server['diameterMm']) ?? 0;

  /// The casting log the SERVER holds for this point, from any phone.
  String? get serverCastingUuid => server['castingUuid'] == null ? null : '${server['castingUuid']}';
  String? get serverCastingBy => server['castingByName']?.toString();

  /// Someone already logs (or logged) this point elsewhere — another phone,
  /// or this phone before a reinstall. A second log is always rejected
  /// (COR_SUDAH_ADA), so "Mulai log cor" is closed.
  bool get castedElsewhere => casting == null && serverCastingUuid != null;

  double? get drillDepthM => localDrillDepthM ?? toDoubleOrNull(server['drilledDepthM']);

  /// Ground level (GS). May be unknown: it is an as-drilled figure, filled by
  /// the QS when marking the point drilled. A casting cannot start without it.
  double? get groundLevel => localGroundLevel ?? toDoubleOrNull(server['groundLevel']);
  double get cutOffLevel => toDoubleOrNull(server['cutOffLevel']) ?? 0;
  double get tipLevel => toDoubleOrNull(server['tipLevel']) ?? 0;

  /// Needs no GS: cut-off − tip.
  double get plannedEffectiveLengthM => cutOffLevel - tipLevel;
  double get plannedTheoreticalVolumeM3 => crossSectionAreaM2(diameterMm) * plannedEffectiveLengthM;

  /// Everything measured from GS. Null while GS is unknown — never computed
  /// from a made-up 0, which would put every depth metres off.
  PileGeometry? get geometry => groundLevel == null
      ? null
      : PileGeometry(
          diameterMm: diameterMm,
          groundLevel: groundLevel!,
          cutOffLevel: cutOffLevel,
          tipLevel: tipLevel,
          drilledDepthM: drillDepthM,
        );

  Map<String, Object?>? get castingBody => casting == null ? null : (jsonDecode(casting!.body) as Map).cast<String, Object?>();

  /// belum_bor | sedang_bor | sudah_bor | berjalan | selesai | sudah_cor
  ///
  /// `sedang_bor`: a drill log is open (here, or on another phone) and the
  /// point is not drilled yet. It counts as NOT drilled: no casting log.
  String get stage {
    final c = castingBody;
    if (c != null) return c['status'] == 'selesai' ? 'selesai' : 'berjalan';
    final s = '${server['status']}';
    if (s == 'sudah_cor') return 'sudah_cor';
    if (castedElsewhere) return 'berjalan';
    if (s == 'sudah_bor' || localDrillDepthM != null) return 'sudah_bor';
    final log = drillLogBody;
    if (log != null && log['status'] != 'selesai') return 'sedang_bor';
    if (drillLoggedElsewhere && server['drillLogStatus'] != 'selesai') return 'sedang_bor';
    return 'belum_bor';
  }

  /// Drilled: the casting log has its hole bottom.
  bool get isDrilled => stage != 'belum_bor' && stage != 'sedang_bor';
}

final fieldPilePointsProvider = Provider.family<AsyncValue<List<FieldPilePoint>>, int>((ref, projectId) {
  final pilePoint = ref.watch(pilePointsProvider(projectId));
  final drillMarks = ref.watch(documentsProvider('drill_mark'));
  final drillLogs = ref.watch(documentsProvider('drill_log'));
  final casting = ref.watch(documentsProvider('casting'));
  if (pilePoint case AsyncError(:final error, :final stackTrace)) return AsyncError(error, stackTrace);
  if (!pilePoint.hasValue || !drillMarks.hasValue || !drillLogs.hasValue || !casting.hasValue) return const AsyncLoading();

  // Drilled depth per point, from whichever was saved LAST: a drill mark
  // (also a correction) or a FINISHED drill log (its deepest reading).
  final drillByPoint = <String, ({double depth, double? groundLevel, DateTime at})>{};
  void offer(String point, double depth, double? groundLevel, DateTime at) {
    final had = drillByPoint[point];
    if (had == null || at.isAfter(had.at)) drillByPoint[point] = (depth: depth, groundLevel: groundLevel, at: at);
  }

  for (final d in drillMarks.value!) {
    if (d.sendStatus == 'rejected') continue;
    final body = (jsonDecode(d.body) as Map).cast<String, Object?>();
    offer('${body['pilePointUuid']}', toDoubleOrNull(body['drilledDepthM']) ?? 0, toDoubleOrNull(body['groundLevel']), d.updatedAt);
  }
  final drillLogByPoint = <String, DocumentRow>{};
  for (final d in drillLogs.value!) {
    if (d.sendStatus == 'rejected' && d.reason == 'LOG_BOR_SUDAH_ADA') continue;
    final body = (jsonDecode(d.body) as Map).cast<String, Object?>();
    final point = '${body['pilePointUuid']}';
    drillLogByPoint.putIfAbsent(point, () => d);
    if (body['status'] == 'selesai' && d.sendStatus != 'rejected') {
      final deepest = deepestM(readingsOf(body));
      if (deepest != null) offer(point, deepest, toDoubleOrNull(body['groundLevel']), d.updatedAt);
    }
  }
  final castingByPoint = <String, DocumentRow>{};
  for (final d in casting.value!) {
    // A log the server refused because the point already has one is dead:
    // it must not stand in for the real one.
    if (d.sendStatus == 'rejected' && d.reason == 'COR_SUDAH_ADA') continue;
    final body = (jsonDecode(d.body) as Map).cast<String, Object?>();
    castingByPoint.putIfAbsent('${body['pilePointUuid']}', () => d);
  }
  return AsyncData([
    for (final t in pilePoint.value!)
      FieldPilePoint(
        server: t,
        localDrillDepthM: drillByPoint['${t['uuid']}']?.depth,
        localGroundLevel: drillByPoint['${t['uuid']}']?.groundLevel,
        casting: castingByPoint['${t['uuid']}'],
        drillLog: drillLogByPoint['${t['uuid']}'],
      ),
  ]);
});

/// One point (for the casting screen) — looked up across all projects.
final pilePointProvider = FutureProvider.family<Map<String, Object?>?, String>(
  (ref, uuid) => ref.watch(dbProvider).getMaster('pile_point', uuid),
);
