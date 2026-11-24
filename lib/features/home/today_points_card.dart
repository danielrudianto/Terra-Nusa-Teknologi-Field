import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/widgets/list_card.dart';
import '../casting/pile_point_data.dart';

/// TODAY'S POINTS on the home page — what the rig crew works on today, per
/// project, one tap into the list (Daniel, 24 Nov 2026: "beranda mandor
/// mau sih bang, titik hari ini apa aja gitu ya").
///
/// "Today's points" = points in an IPL confirmed for today: the same set the
/// crew's point list is narrowed to, so the home page and the list never
/// disagree. Each point is a chip coloured by where its work stands.
class TodayPointsCard extends ConsumerWidget {
  const TodayPointsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(castingProjectsProvider).value ?? const [];
    final blocks = <Widget>[];
    for (final p in projects) {
      final id = int.tryParse('${p['id']}');
      if (id == null) continue;
      final all = ref.watch(fieldPilePointsProvider(id)).value ?? const <FieldPilePoint>[];
      // A server older than IPL sends no date at all: nothing to show then,
      // rather than every point of the project.
      final today = [
        for (final pt in all)
          if (pt.server.containsKey('iplDate') && pt.iplReady) pt,
      ];
      if (today.isEmpty) continue;
      blocks.add(_ProjectToday(projectId: id, code: '${p['code'] ?? ''}', points: today));
    }
    if (blocks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in blocks) ...[b, const SizedBox(height: 12)],
      ],
    );
  }
}

class _ProjectToday extends StatelessWidget {
  const _ProjectToday({required this.projectId, required this.code, required this.points});

  final int projectId;
  final String code;
  final List<FieldPilePoint> points;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final l = t(context);
    bool cast(FieldPilePoint p) => p.stage == 'sudah_cor' || p.stage == 'selesai';
    final castCount = points.where(cast).length;
    final drilledCount = points.where((p) => p.isDrilled).length;
    return ListCard(
      onTap: () => context.push('/casting/project/$projectId'),
      edgeColor: w.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.today, color: w.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.todayPointsTitle(code, '${points.length}'),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: w.ink),
                ),
              ),
              Icon(Icons.chevron_right, color: w.muted),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l.todayPointsProgress('$drilledCount', '$castCount'),
            style: TextStyle(color: w.muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final p in points) _Chip(point: p)],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.point});

  final FieldPilePoint point;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    // The same colours as the point list: grey → amber → blue → purple → green.
    final (bg, fg) = switch (point.stage) {
      'berjalan' => (w.checkedBg, w.checkedFg),
      'selesai' || 'sudah_cor' => (w.okBg, w.okFg),
      'sudah_bor' => (w.infoBg, w.infoFg),
      'sedang_bor' => (w.warnBg, w.warnFg),
      _ => (w.surface2, w.ink),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(point.code, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}
