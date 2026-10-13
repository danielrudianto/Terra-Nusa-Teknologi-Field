import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_snack.dart';
import '../../core/db/app_database.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/util/reasons.dart';
import '../../core/util/format.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/view_states.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/status_badge.dart';
import '../home/status_banners.dart';
import '../../core/i18n.dart';

final _queueProvider = StreamProvider<List<DocumentRow>>((ref) {
  final p = ref.watch(userProvider);
  if (p == null) return Stream.value(const []);
  return ref.watch(dbProvider).watchQueue(p.id);
});

final _photoQueueProvider = StreamProvider<List<PhotoRow>>((ref) {
  final p = ref.watch(userProvider);
  if (p == null) return Stream.value(const []);
  return ref.watch(dbProvider).watchPendingPhotos(p.id);
});

/// Items whose business with the server is not finished yet.
class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final doc = ref.watch(_queueProvider);
    final photos = ref.watch(_photoQueueProvider).value ?? const [];
    final syncState = ref.watch(syncProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t(context).queueTitle)),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncProvider.notifier).run(diminta: true),
        child: doc.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorState(title: t(context).queueLoadError, message: '$e'),
          data: (items) => ListView(
            padding: const EdgeInsets.all(Dimens.pagePadding),
            children: [
              const StatusBanners(),
              if (syncState.last?.error != null)
                TerraBanner(kind: BannerKind.danger, title: t(context).lastSendFailed, body: syncState.last!.error),
              PageHeader(
                title: t(context).queueCount(items.length, photos.length),
                description: syncState.lastRunAt == null
                    ? t(context).notSentSinceOpen
                    : t(context).lastTriedAt(formatTime(syncState.lastRunAt!)),
              ),
              if (items.isEmpty && photos.isEmpty)
                EmptyState(message: t(context).allSent, icon: Icons.cloud_done_outlined),
              for (final d in items) _DocumentCard(d: d),
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(t(context).photosSection, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
                const SizedBox(height: 6),
                for (final f in photos)
                  ListCard(
                    edgeColor: f.sendStatus == 'rejected' ? w.badFg : null,
                    child: Row(
                      children: [
                        Icon(Icons.image_outlined, color: w.muted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${t(context).photoLine(_photoKindLabel(context, f.kind), '${(f.sizeBytes / 1024).round()}', formatTime(f.takenAt))}'
                            '${f.reason == null ? '' : '\n${reasonText(context, f.reason)}'}',
                            style: TextStyle(color: w.ink, fontSize: 13),
                          ),
                        ),
                        StatusBadge.sendStatus(context, f.sendStatus == 'pending' ? (f.attempts > 0 ? 'failed' : 'pending') : f.sendStatus),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _photoKindLabel(BuildContext context, String kind) => switch (kind) {
        'wajah' => t(context).photoFace,
        'absen_masuk' => t(context).photoCheckIn,
        'absen_pulang' => t(context).photoCheckOut,
        'tiket_tm' => t(context).photoTicketKind,
        'slump_tm' => t(context).photoSlumpKind,
        _ => kind,
      };
}

class _DocumentCard extends ConsumerWidget {
  const _DocumentCard({required this.d});

  final DocumentRow d;

  String? get _route => switch (d.entity) {
        'attendance' => '/attendance/${d.uuid}',
        'casting' => '/casting/log/${d.uuid}',
        'drill_log' => '/drilling/log/${d.uuid}',
        'worker' => '/workers/${d.uuid}',
        _ => null,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final rejected = d.sendStatus == 'rejected';
    return ListCard(
      edgeColor: rejected ? w.badFg : null,
      onTap: _route == null ? null : () => context.push(_route!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${entityLabel(context, d.entity)} · v${d.version}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
              ),
              StatusBadge.sendStatus(context, d.sendStatus),
            ],
          ),
          Text(t(context).changedAt(formatTime(d.updatedAt), d.uuid.substring(0, 8)), style: TextStyle(color: w.muted, fontSize: 12)),
          if (d.reason != null) ...[
            const SizedBox(height: 6),
            Text(reasonText(context, d.reason, d.detail), style: TextStyle(color: rejected ? w.badFg : w.warnFg, fontSize: 13)),
          ],
          if (d.retryAfter != null && !rejected)
            Text(t(context).retryAt(formatTime(d.retryAfter!)), style: TextStyle(color: w.muted, fontSize: 12)),
          if (rejected)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text(t(c).discardTitle),
                        content: Text(t(c).discardBody),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t(c).cancel)),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t(c).discard)),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await ref.read(dbProvider).discardDocument(d.uuid);
                      if (context.mounted) showSnack(context, t(context).discarded, icon: Icons.delete_outline);
                    }
                  },
                  child: Text(t(context).discard),
                ),
                TextButton(
                  onPressed: () async {
                    await ref.read(dbProvider).retryDocument(d.uuid);
                    ref.read(syncProvider.notifier).afterSave();
                    if (context.mounted) showSnack(context, t(context).queuedResend, icon: Icons.cloud_upload_outlined);
                  },
                  child: Text(t(context).resend),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
