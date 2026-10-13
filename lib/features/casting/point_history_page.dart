import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/view_states.dart';
import '../../core/i18n.dart';

/// Riwayat satu titik, dibaca LANGSUNG dari server.
///
/// Alasan layar ini ada: satu titik hanya boleh punya satu log cor, dan log
/// itu hidup di HP yang membuatnya. Siapa pun yang membuka titik tersebut
/// dari HP lain — termasuk yang sudah selesai dicor kemarin — tidak dapat
/// melihat satu angka pun hasilnya. Yang tampil hanya angka RENCANA, dan
/// orang menyimpulkan datanya hilang.
///
/// Karena itu tidak ada apa pun di sini yang diambil dari basis data HP:
/// seluruhnya dari `/field/pile-points/{id}/riwayat`, dan tanpa sinyal
/// layar ini memang tidak bisa dibuka. Itu jujur, dan lebih baik daripada
/// menampilkan sebagian yang kebetulan ada.
final _historyProvider = FutureProvider.autoDispose.family<Map<String, Object?>, int>(
  (ref, pileId) => ref.read(apiProvider).pointHistory(pileId),
);

class PointHistoryPage extends ConsumerWidget {
  const PointHistoryPage({super.key, required this.pileId, required this.code});

  final int pileId;
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_historyProvider(pileId));
    return Scaffold(
      appBar: AppBar(title: Text(t(context).pointHistoryTitle(code))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_historyProvider(pileId)),
        child: data.when(
          loading: () => const LoadingState(),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(Dimens.pagePadding),
            children: [
              TerraBanner(
                kind: BannerKind.danger,
                icon: Icons.cloud_off,
                title: t(context).pointHistoryErrorTitle,
                body: t(context).pointHistoryErrorBody,
              ),
            ],
          ),
          data: (d) => _isi(context, d),
        ),
      ),
    );
  }

  Widget _isi(BuildContext context, Map<String, Object?> d) {
    final w = context.colors;
    final castings = (d['castings'] as List?) ?? const [];
    final jejak = (d['jejak'] as List?) ?? const [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, Dimens.pagePadding, Dimens.pagePadding, 40),
      children: [
        if (castings.isEmpty)
          EmptyState(message: t(context).pointHistoryNoCasting)
        else
          for (final c in castings) _KartuCor(cor: (c as Map).cast<String, Object?>()),
        if (jejak.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 8),
            child: Text(t(context).pointHistoryTrail,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: w.ink)),
          ),
          for (final j in jejak) _BarisJejak(jejak: (j as Map).cast<String, Object?>()),
        ],
      ],
    );
  }
}

/// Satu log cor beserta TM-nya.
class _KartuCor extends StatelessWidget {
  const _KartuCor({required this.cor});

  final Map<String, Object?> cor;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final h = ((cor['hitungan'] as Map?) ?? const {}).cast<String, Object?>();
    final tm = ((cor['trucks'] as List?) ?? const []).map((x) => (x as Map).cast<String, Object?>()).toList()
      ..sort((a, b) => (toIntOrNull(a['seq']) ?? 0).compareTo(toIntOrNull(b['seq']) ?? 0));
    final dihapus = cor['isDelete'] == true || cor['isDelete'] == 1;
    final dariKantor = '${cor['source']}' == 'kantor';
    final volume = toDoubleOrNull(h['volumeAktualM3']);
    final teoritis = toDoubleOrNull(h['volumeTeoritisAktualM3']) ?? toDoubleOrNull(h['volumeTeoritisRencanaM3']);
    final lebih = toDoubleOrNull(h['lebihPakaiPersen']);

    return ListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cor['date'] == null ? '–' : longDate(DateTime.parse('${cor['date']}')),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: w.ink),
                ),
              ),
              // Log yang DIHAPUS tetap ditampilkan, dan ditandai. Riwayat yang
              // hanya memuat baris hidup tidak dapat menjawab "kemarin
              // volumenya 12 m³, kok sekarang kosong" — dan pertanyaan itulah
              // yang dibawa ke rapat.
              if (dihapus) StatusBadge(text: t(context).deletedLabel, bg: w.badBg, fg: w.badFg),
              if (!dihapus && dariKantor)
                StatusBadge(text: t(context).fromOffice, bg: w.infoBg, fg: w.infoFg),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (cor['concreteGrade'] != null) '${cor['concreteGrade']}',
              if (cor['supplierName'] != null) '${cor['supplierName']}',
              t(context).trucksCount(tm.length),
            ].join(' · '),
            style: TextStyle(color: w.muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          _Baris(t(context).volumeUsed,
              volume == null ? '–' : '${_angka(volume)} m³'),
          _Baris(t(context).volumeTheoretical,
              teoritis == null ? '–' : '${_angka(teoritis)} m³'),
          if (lebih != null)
            _Baris(t(context).overusePercent, '${_angka(lebih, 1)}%',
                warna: lebih > 25 ? w.badFg : (lebih > 10 ? w.warnFg : null)),
          if (h['mulaiCor'] != null)
            _Baris(t(context).castStartEnd,
                '${formatTime(DateTime.parse('${h['mulaiCor']}'))} – '
                '${h['selesaiCor'] == null ? '…' : formatTime(DateTime.parse('${h['selesaiCor']}'))}'),
          if (tm.isNotEmpty) ...[
            const Divider(height: 22),
            for (final t0 in tm) _BarisTm(tm: t0),
          ],
          if (cor['note'] != null && '${cor['note']}'.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('${cor['note']}', style: TextStyle(color: w.muted, fontSize: 13, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

/// Satu TM di dalam kartu log cor.
class _BarisTm extends StatelessWidget {
  const _BarisTm({required this.tm});

  final Map<String, Object?> tm;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final mulai = tm['startAt'] == null ? null : DateTime.tryParse('${tm['startAt']}');
    final selesai = tm['endAt'] == null ? null : DateTime.tryParse('${tm['endAt']}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Text('TM ${tm['seq']}',
                style: TextStyle(fontWeight: FontWeight.w700, color: w.brandStrong, fontSize: 13)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (tm['volumeM3'] != null) '${_angka(toDoubleOrNull(tm['volumeM3']) ?? 0, 2)} m³',
                    if (tm['slumpCm'] != null) t(context).slumpOf(_angka(toDoubleOrNull(tm['slumpCm']) ?? 0, 1)),
                    if (tm['truckNo'] != null) '${tm['truckNo']}',
                  ].join(' · '),
                  style: TextStyle(color: w.ink, fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                if (mulai != null)
                  Text(
                    '${formatTime(mulai)} – ${selesai == null ? '…' : formatTime(selesai)}',
                    style: TextStyle(color: w.muted, fontSize: 12.5),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu baris jejak audit.
class _BarisJejak extends StatelessWidget {
  const _BarisJejak({required this.jejak});

  final Map<String, Object?> jejak;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final kapan = jejak['createdAt'] == null ? null : DateTime.tryParse('${jejak['createdAt']}');
    final siapa = jejak['actorName']?.toString() ?? jejak['userName']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history, size: 15, color: w.faint),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (siapa != null) siapa,
                    if (kapan != null) '${longDate(kapan)} ${formatTime(kapan)}',
                  ].join(' · '),
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: w.ink),
                ),
                if (jejak['note'] != null)
                  Text('${jejak['note']}', style: TextStyle(color: w.muted, fontSize: 12.5, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Baris extends StatelessWidget {
  const _Baris(this.label, this.value, {this.warna});

  final String label;
  final String value;
  final Color? warna;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: w.muted, fontSize: 13))),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: warna ?? w.ink)),
        ],
      ),
    );
  }
}

String _angka(double v, [int d = 2]) => v.toStringAsFixed(d).replaceAll('.', ',');
