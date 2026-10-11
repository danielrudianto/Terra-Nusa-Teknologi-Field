import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/view_states.dart';
import '../../core/widgets/page_header.dart';
import '../home/status_banners.dart';

/// Choose a project → list of pile points.
class CastingPage extends ConsumerWidget {
  const CastingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final projects = ref.watch(castingProjectsProvider);
    final mine = ref.watch(myProjectProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Log pengecoran')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncProvider.notifier).run(),
        child: projects.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorState(title: 'Proyek gagal dibaca', message: '$e'),
          data: (all) {
            // The user's own project on top, marked.
            final items = [
              ...all.where((p) => '${p['id']}' == '$mine'),
              ...all.where((p) => '${p['id']}' != '$mine'),
            ];
            return ListView(
            padding: const EdgeInsets.all(Dimens.pagePadding),
            children: [
              const StatusBanners(showPending: false),
              const PageHeader(title: 'Pilih proyek', description: 'Titik bor diisi kantor dari gambar kerja'),
              if (items.isEmpty)
                const EmptyState(
                  message: 'Belum ada proyek cor di HP. Tarik ke bawah saat ada sinyal.',
                  icon: Icons.domain_disabled,
                ),
              for (final p in items)
                Consumer(builder: (context, ref, _) {
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
                                  child: Text('PROYEK SAYA',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: w.brand)),
                                ),
                              Text('${p['code']}', style: TextStyle(fontWeight: FontWeight.w800, color: w.brandStrong)),
                              Text('${p['name']}', style: TextStyle(color: w.ink)),
                            ],
                          ),
                        ),
                        Text(count == null ? '' : '$count titik', style: TextStyle(color: w.muted)),
                        Icon(Icons.chevron_right, color: w.muted),
                      ],
                    ),
                  );
                }),
            ],
          );
          },
        ),
      ),
    );
  }
}
