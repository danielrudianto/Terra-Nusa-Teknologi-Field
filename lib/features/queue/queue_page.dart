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
      appBar: AppBar(title: const Text('Antrean kirim')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncProvider.notifier).run(),
        child: doc.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorState(title: 'Antrean gagal dibaca', message: '$e'),
          data: (items) => ListView(
            padding: const EdgeInsets.all(Dimens.pagePadding),
            children: [
              const StatusBanners(),
              if (syncState.last?.error != null)
                TerraBanner(kind: BannerKind.danger, title: 'Kiriman terakhir gagal', body: syncState.last!.error),
              PageHeader(
                title: '${items.length} data · ${photos.length} foto',
                description: syncState.lastRunAt == null ? 'Belum dikirim sejak aplikasi dibuka' : 'Terakhir dicoba pukul ${formatTime(syncState.lastRunAt!)}',
              ),
              if (items.isEmpty && photos.isEmpty)
                const EmptyState(message: 'Semua sudah terkirim.', icon: Icons.cloud_done_outlined),
              for (final d in items) _DocumentCard(d: d),
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Foto', style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
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
                            '${_photoKindLabel(f.kind)} · ${(f.sizeBytes / 1024).round()} kB · ${formatTime(f.takenAt)}'
                            '${f.reason == null ? '' : '\n${reasonText(f.reason)}'}',
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

  static String _photoKindLabel(String kind) => switch (kind) {
        'wajah' => 'Wajah pekerja',
        'absen_masuk' => 'Absen masuk',
        'absen_pulang' => 'Absen pulang',
        'tiket_tm' => 'Surat jalan TM',
        'slump_tm' => 'Uji slump TM',
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
                child: Text('${entityLabel(d.entity)} · v${d.version}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
              ),
              StatusBadge.sendStatus(context, d.sendStatus),
            ],
          ),
          Text('Diubah ${formatTime(d.updatedAt)} · ${d.uuid.substring(0, 8)}', style: TextStyle(color: w.muted, fontSize: 12)),
          if (d.reason != null) ...[
            const SizedBox(height: 6),
            Text(reasonText(d.reason, d.detail), style: TextStyle(color: rejected ? w.badFg : w.warnFg, fontSize: 13)),
          ],
          if (d.retryAfter != null && !rejected)
            Text('Dicoba lagi pukul ${formatTime(d.retryAfter!)}', style: TextStyle(color: w.muted, fontSize: 12)),
          if (rejected)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Buang dari HP?'),
                        content: const Text('Data ini tidak akan dikirim lagi. Tidak dapat dibatalkan.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Buang')),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await ref.read(dbProvider).discardDocument(d.uuid);
                      if (context.mounted) showSnack(context, 'Dibuang dari HP.', icon: Icons.delete_outline);
                    }
                  },
                  child: const Text('Buang'),
                ),
                TextButton(
                  onPressed: () async {
                    await ref.read(dbProvider).retryDocument(d.uuid);
                    ref.read(syncProvider.notifier).afterSave();
                    if (context.mounted) showSnack(context, 'Masuk antrean, dikirim ulang sekarang.', icon: Icons.cloud_upload_outlined);
                  },
                  child: const Text('Kirim ulang'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
