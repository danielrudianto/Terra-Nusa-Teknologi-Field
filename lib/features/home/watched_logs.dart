import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/providers.dart';
import '../../core/util/format.dart';

/// One running log this user HOLDS right now — for the "Sedang dipantau"
/// card on Home. Gone from the list once it is finished, handed over (Oper),
/// or deleted by the office.
class WatchedLog {
  const WatchedLog({
    required this.uuid,
    required this.entity,
    required this.pointCode,
    required this.projectCode,
    required this.updatedAt,
  });

  /// Document uuid — also the route parameter.
  final String uuid;

  /// 'drill_log' | 'casting'.
  final String entity;

  final String pointCode;
  final String? projectCode;
  final DateTime updatedAt;

  String get route => entity == 'drill_log' ? '/drilling/log/$uuid' : '/casting/log/$uuid';
}

final _allPointsProvider = StreamProvider<List<Map<String, Object?>>>(
  (ref) => ref.watch(dbProvider).watchMaster('pile_point'),
);

/// The running drill and casting logs held on this phone by this user.
final watchedLogsProvider = Provider<List<WatchedLog>>((ref) {
  final me = ref.watch(userProvider)?.id;
  if (me == null) return const [];
  final points = {
    for (final t in ref.watch(_allPointsProvider).value ?? const <Map<String, Object?>>[]) '${t['uuid']}': t,
  };
  final projects = {
    for (final p in ref.watch(projectsProvider).value ?? const <Map<String, Object?>>[]) '${p['id']}': p,
  };

  WatchedLog? of(DocumentRow d, String holderKey) {
    if (d.sendStatus == 'rejected') return null;
    final body = (jsonDecode(d.body) as Map).cast<String, Object?>();
    if (body['status'] != 'berjalan') return null;
    final point = points['${body['pilePointUuid']}'];
    if (point == null || point['isDelete'] == true) return null;
    // Handed over to a colleague (Oper): their phone watches it now.
    final holder = toIntOrNull(point[holderKey]);
    if (holder != null && holder != me) return null;
    return WatchedLog(
      uuid: d.uuid,
      entity: d.entity,
      pointCode: '${point['code']}',
      projectCode: projects['${point['projectID']}']?['code']?.toString(),
      updatedAt: d.updatedAt,
    );
  }

  final items = <WatchedLog>[
    for (final d in ref.watch(documentsProvider('drill_log')).value ?? const <DocumentRow>[])
      ?of(d, 'drillLogHolderID'),
    for (final d in ref.watch(documentsProvider('casting')).value ?? const <DocumentRow>[])
      ?of(d, 'castingHolderID'),
  ];
  items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return items;
});
