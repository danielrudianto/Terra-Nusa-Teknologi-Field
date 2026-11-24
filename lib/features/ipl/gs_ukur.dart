import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/providers.dart';
import '../../core/util/format.dart';

/// GS MEASURED BY THE SURVEYOR, apart from any IPL (Daniel, 24 Nov 2026:
/// "jadi bisa tuh orangnya kasih GS, tapi udah gitu belum tentu dikerjain
/// besok").
///
/// The surveyor shoots ground levels well before a point is scheduled. Each
/// one is a `gs_ukur` document — one per point per surveyor; measuring again
/// raises its version — sent like every other document. It is NOT the
/// point's GS yet: that still only changes when the office confirms an IPL
/// carrying it ("tetap lewat IPL"). The office sees these under Pekerjaan
/// persiapan on Live.
///
/// The body is exactly the server's `DataGsUkur`.

/// This user's measurements, pile uuid → latest document.
final gsUkurByPileProvider = Provider<Map<String, DocumentRow>>((ref) {
  final docs = ref.watch(documentsProvider('gs_ukur')).value ?? const <DocumentRow>[];
  final out = <String, DocumentRow>{};
  for (final d in docs) {
    final pile = '${(jsonDecode(d.body) as Map)['pilePointUuid']}';
    final had = out[pile];
    if (had == null || d.updatedAt.isAfter(had.updatedAt)) out[pile] = d;
  }
  return out;
});

/// The measured GS in a document, or `null`.
double? gsUkurValue(DocumentRow d) => toDoubleOrNull((jsonDecode(d.body) as Map)['groundLevel']);

/// Save one measurement under [uuid] — the uuid of this user's document for
/// the point when there is one, so measuring again updates it instead of
/// adding another.
Future<void> saveGsUkur(
  AppDatabase db, {
  required String uuid,
  required int userId,
  required int projectId,
  required String pileUuid,
  required double gs,
}) {
  return db.saveDocument(
    uuid: uuid,
    entity: 'gs_ukur',
    userId: userId,
    body: {
      'projectID': projectId,
      'pilePointUuid': pileUuid,
      'groundLevel': decimalText(gs, decimals: 3),
      'measuredAt': isoWithOffset(DateTime.now()),
    },
  );
}
