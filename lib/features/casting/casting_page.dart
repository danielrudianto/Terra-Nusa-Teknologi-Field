import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';
import '../../core/util/format.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/view_states.dart';
import '../../core/widgets/page_header.dart';
import '../home/status_banners.dart';
import 'pile_points_page.dart';
import '../../core/i18n.dart';

/// Choose a project → list of pile points.
class CastingPage extends ConsumerWidget {
  const CastingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final projects = ref.watch(castingProjectsProvider);
    final mine = ref.watch(myProjectProvider).value;
    // ONE project: straight into its points, no list of one to tap through
    // (Daniel, 24 Nov 2026: "kita bikin simple untuk orang orang itu").
    final only = projects.value;
    if (only != null && only.length == 1) {
      final id = toIntOrNull(only.first['id']);
      if (id != null) return PilePointsPage(projectId: id);
    }
    return Scaffold(
      appBar: AppBar(title: Text(t(context).castingTitle)),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncProvider.notifier).run(diminta: true),
        child: projects.when(
          loading: () => const SkeletonCards(leading: false),
          error: (e, _) => ErrorState(title: t(context).projectsLoadError, message: '$e'),
          data: (all) {
            // The user's own project on top, marked.
            final items = [
              ...all.where((p) => '${p['id']}' == '$mine'),
              ...all.where((p) => '${p['id']}' != '$mine'),
            ];
            return ListView(
            padding: pagePaddingAman(context),
            children: [
              const StatusBanners(showPending: false),
              PageHeader(title: t(context).pickProject, description: t(context).pickProjectBody),
              // No project at all: below level 5 that means the office has
              // not added this person to any project's field team yet.
              if (items.isEmpty)
                TerraBanner(
                  kind: BannerKind.info,
                  icon: Icons.group_off_outlined,
                  title: t(context).noProjectAssignedTitle,
                  body: t(context).noProjectAssignedBody,
                ),
              for (final (i, p) in items.indexed)
                AppearIn(
                  order: i,
                  child: Consumer(builder: (context, ref, _) {
                  final count = ref.watch(pilePointsProvider((p['id'] as num).toInt())).value?.length;
                  final isMine = '${p['id']}' == '$mine';
                  return ListCard(
                    onTap: () => context.push('/casting/project/${p['id']}'),
                    edgeColor: isMine ? w.brand : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isMine)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(t(context).myProjectTag,
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: w.brand)),
                                ),
                              Text('${p['code']}', style: TextStyle(fontWeight: FontWeight.w800, color: w.brandStrong)),
                              Text('${p['name']}', style: TextStyle(color: w.ink)),
                            ],
                          ),
                        ),
                        Text(count == null ? '' : t(context).pointCount(count), style: TextStyle(color: w.muted)),
                        Icon(Icons.chevron_right, color: w.muted),
                      ],
                    ),
                  );
                  }),
                ),
            ],
          );
          },
        ),
      ),
    );
  }
}
