/// Pile points a truck recorded at the gate may ALSO pour into.
///
/// One truck is sometimes split between two holes. After its gate record is
/// saved the person is offered the other pile points of the same project;
/// this is the rule for which ones.
///
/// Left out:
///  * the pile point just recorded — the server refuses the same truck
///    number twice on one pile point;
///  * a pile point of another project;
///  * a deleted one;
///  * a CONFIRMED one, and one already cast — the server refuses any new
///    record for them, and offering a choice that will be refused is worse
///    than not offering it.
///
/// Ordered like the pile point list: by `sortOrder`, then by code.
List<Map<String, Object?>> pilesForSameTruck(
  List<Map<String, Object?>> all, {
  required Object? projectId,
  required String? currentUuid,
}) {
  final piles = [
    for (final p in all)
      if ('${p['projectID']}' == '$projectId' &&
          p['isDelete'] != true &&
          '${p['uuid']}' != currentUuid &&
          p['checkedAt'] == null &&
          '${p['status']}' != 'sudah_cor')
        p,
  ];
  piles.sort((a, b) {
    final order = ((a['sortOrder'] as num?) ?? 0).compareTo((b['sortOrder'] as num?) ?? 0);
    return order != 0 ? order : '${a['code']}'.compareTo('${b['code']}');
  });
  return piles;
}
