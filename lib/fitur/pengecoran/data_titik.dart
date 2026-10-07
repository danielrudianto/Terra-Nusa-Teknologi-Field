import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../inti/db/database.dart';
import '../../inti/penyedia.dart';
import '../../inti/util/format.dart';
import 'hitung/volume.dart';

/// Satu titik bor sebagaimana DILIHAT QS: data server + apa yang sudah
/// dicatat di HP ini tetapi belum tentu terkirim.
class TitikLapangan {
  const TitikLapangan({required this.server, this.tandaBorLokal, this.cor});

  final Map<String, Object?> server;

  /// Kedalaman bor dari tanda bor di HP (terbaru), bila ada.
  final double? tandaBorLokal;

  /// Log cor di HP ini untuk titik ini.
  final BarisDokumen? cor;

  String get uuid => '${server['uuid']}';
  String get kode => '${server['code']}';
  int get diameterMm => keInt(server['diameterMm']) ?? 0;

  double? get kedalamanBorM => tandaBorLokal ?? keDouble(server['drilledDepthM']);

  GeometriTitik get geometri => GeometriTitik(
        diameterMm: diameterMm,
        groundLevel: keDouble(server['groundLevel']) ?? 0,
        cutOffLevel: keDouble(server['cutOffLevel']) ?? 0,
        tipLevel: keDouble(server['tipLevel']) ?? 0,
        drilledDepthM: kedalamanBorM,
      );

  Map<String, Object?>? get isiCor => cor == null ? null : (jsonDecode(cor!.isi) as Map).cast<String, Object?>();

  /// belum_bor | sudah_bor | berjalan | selesai | sudah_cor
  String get keadaan {
    final c = isiCor;
    if (c != null) return c['status'] == 'selesai' ? 'selesai' : 'berjalan';
    final s = '${server['status']}';
    if (s == 'sudah_cor') return 'sudah_cor';
    if (s == 'sudah_bor' || tandaBorLokal != null) return 'sudah_bor';
    return 'belum_bor';
  }
}

final titikLapanganProvider = Provider.family<AsyncValue<List<TitikLapangan>>, int>((ref, proyekId) {
  final titik = ref.watch(titikProvider(proyekId));
  final tanda = ref.watch(dokumenProvider('drill_mark'));
  final cor = ref.watch(dokumenProvider('casting'));
  if (titik case AsyncError(:final error, :final stackTrace)) return AsyncError(error, stackTrace);
  if (!titik.hasValue || !tanda.hasValue || !cor.hasValue) return const AsyncLoading();

  // Tanda bor TERBARU per titik (dokumen urut diubah terbaru dulu).
  final borPerTitik = <String, double>{};
  for (final d in tanda.value!) {
    if (d.statusKirim == 'ditolak') continue;
    final isi = (jsonDecode(d.isi) as Map).cast<String, Object?>();
    borPerTitik.putIfAbsent('${isi['pilePointUuid']}', () => keDouble(isi['drilledDepthM']) ?? 0);
  }
  final corPerTitik = <String, BarisDokumen>{};
  for (final d in cor.value!) {
    final isi = (jsonDecode(d.isi) as Map).cast<String, Object?>();
    corPerTitik.putIfAbsent('${isi['pilePointUuid']}', () => d);
  }
  return AsyncData([
    for (final t in titik.value!)
      TitikLapangan(server: t, tandaBorLokal: borPerTitik['${t['uuid']}'], cor: corPerTitik['${t['uuid']}']),
  ]);
});

/// Satu titik (untuk layar cor) — dicari di semua proyek.
final satuTitikProvider = FutureProvider.family<Map<String, Object?>?, String>(
  (ref, uuid) => ref.watch(dbProvider).satuInduk('titik', uuid),
);
