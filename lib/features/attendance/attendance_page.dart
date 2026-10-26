import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/view_states.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/status_badge.dart';
import '../home/status_banners.dart';
import 'review_badge.dart';
import '../../core/i18n.dart';

class AttendancePage extends ConsumerWidget {
  const AttendancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final doc = ref.watch(documentsProvider('attendance'));
    final projects = {for (final p in ref.watch(projectsProvider).value ?? const []) '${p['id']}': p};
    final allows = ref.watch(sessionProvider).value?.allows('field_attendance', 'create') ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(t(context).attendanceTitle)),
      floatingActionButton: allows
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/attendance/new'),
              icon: const Icon(Icons.add),
              label: Text(t(context).attendToday),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncProvider.notifier).run(diminta: true),
        child: doc.when(
        loading: () => const SkeletonCards(),
        error: (e, _) => ErrorState(title: t(context).attendanceLoadError, message: '$e'),
        // DIBANGUN MALAS, bukan sekaligus.
        //
        // Riwayat absensi TIDAK DIBATASI — `watchDocuments` memulangkan
        // seluruh dokumen absensi pengguna ini, dan seorang mandor menambah
        // satu setiap hari kerja tanpa pernah berkurang. Dengan
        // `ListView(children: [...])` setiap kartu dirakit sebelum satu pun
        // terlihat, dan tiap kartu menjalankan `jsonDecode` atas isinya.
        // Artinya seluruh riwayat diurai ulang setiap kali layar ini
        // digambar ulang, dan biayanya bertambah tiap hari tanpa ada
        // kejadian yang dapat ditunjuk sebagai penyebabnya.
        //
        // `.builder` merakit — dan mengurai — yang terlihat saja.
        data: (items) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, Dimens.pagePadding, Dimens.pagePadding, 96),
          // Dua butir kepala selalu ada. Daftar kosong menambah satu lagi
          // untuk keterangannya, bukan membiarkan layar kosong tanpa kata.
          itemCount: items.isEmpty ? 3 : items.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) return const StatusBanners(showPending: false);
            if (i == 1) {
              return PageHeader(title: t(context).attendanceHistory, description: t(context).attendanceHistoryBody);
            }
            if (items.isEmpty) {
              return EmptyState(message: t(context).noAttendanceYet, icon: Icons.how_to_reg_outlined);
            }
            final d = items[i - 2];
            final body = (jsonDecode(d.body) as Map).cast<String, Object?>();
            final p = projects['${body['projectID']}'];
            final rows = (body['lines'] as List?)?.length ?? 0;
            final hasCheckIn = body['checkIn'] != null;
            final hasCheckOut = body['checkOut'] != null;
            return ListCard(
              edgeColor: d.sendStatus == 'rejected' ? w.badFg : null,
              onTap: () => context.push('/attendance/${d.uuid}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p == null ? 'Proyek #${body['projectID']}' : '${p['code']} · ${p['name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, color: w.ink),
                        ),
                      ),
                      StatusBadge.sendStatus(context, d.sendStatus),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${body['date']} · $rows kru · ${hasCheckIn ? 'masuk ✓' : 'belum masuk'} · ${hasCheckOut ? 'pulang ✓' : 'belum pulang'}',
                      style: TextStyle(color: w.muted, fontSize: 13)),
                  if (d.serverStatus != null) ...[
                    const SizedBox(height: 6),
                    ReviewBadge(status: d.serverStatus!),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      ),
    );
  }
}
