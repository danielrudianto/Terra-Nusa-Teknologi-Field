import '../../core/util/format.dart';

/// The concrete suppliers to offer in a casting log.
///
/// Every supplier marked "Pemasok beton" in the ERP comes down with the
/// projects that have a purchase order to it (`projectIDs`). A casting only
/// offers the ones with a PO in ITS project, so the list stays short. When
/// the project has no PO to any of them (or the data predates `projectIDs`),
/// all of them are offered instead — the foreman must still be able to pick.
///
/// [keepId], the supplier already chosen in this log, is always kept, so a
/// choice made before the filter (or before a PO was cancelled) still shows.
({List<Map<String, Object?>> suppliers, bool narrowed}) suppliersForProject(
  List<Map<String, Object?>> all,
  int? projectId, {
  int? keepId,
}) {
  if (projectId == null) return (suppliers: all, narrowed: false);
  bool hasPo(Map<String, Object?> s) {
    final ids = s['projectIDs'];
    return ids is List && ids.any((id) => toIntOrNull(id) == projectId);
  }

  final withPo = [for (final s in all) if (hasPo(s) || (keepId != null && toIntOrNull(s['id']) == keepId)) s];
  if (!withPo.any(hasPo)) return (suppliers: all, narrowed: false);
  return (suppliers: withPo, narrowed: true);
}
