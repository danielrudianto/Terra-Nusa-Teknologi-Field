import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/util/clock_drift.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/util/format.dart';

/// Status banners shown at the TOP of every main page.
///
/// Ordered by severity: session expired (the queue cannot be pushed at all),
/// rejected (something the foreman must fix), then not yet pushed (just
/// good to know).
class StatusBanners extends ConsumerWidget {
  const StatusBanners({super.key, this.showPending = true});

  final bool showPending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final lock = ref.watch(deviceLockProvider).value;
    final rejected = ref.watch(rejectedCountProvider).value ?? 0;
    final pending = ref.watch(pendingCountProvider).value ?? 0;
    final pendingPhotos = ref.watch(pendingPhotoCountProvider).value ?? 0;
    final syncState = ref.watch(syncProvider);
    final oldest = ref.watch(oldestPendingProvider).value;
    final drift = ref.watch(clockDriftProvider).value;
    final clockOff = drift != null && drift.abs() > clockDriftWarn;
    // Waiting more than a day: something is wrong (no signal for days, an
    // app killed by battery saving) and someone has to act on it.
    final stale = oldest != null && DateTime.now().difference(oldest) > const Duration(hours: 24);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Satu akun, satu HP. Paling atas bersama sesi berakhir: selama ini
        // tidak dibereskan, apa pun yang dicatat di HP ini akhirnya ditolak.
        if (lock != null)
          TerraBanner(
            kind: lock.graceOver ? BannerKind.danger : BannerKind.warning,
            icon: Icons.phonelink_lock,
            title: lock.graceOver
                ? 'HP ini sudah digantikan'
                : 'Akun ini dipakai di HP lain',
            body: lock.graceOver
                ? 'Akun Anda dipakai masuk di HP lain, jadi HP ini tidak lagi menerima catatan baru. '
                    'Sisa antrean tetap terkirim dari sini. Bila HP ini yang Anda pakai, masuk lagi di HP ini.'
                : 'Akun Anda dipakai masuk di HP lain'
                    '${lock.byName == null ? '' : ' (${lock.byName})'}. '
                    'Kirim sisa data dari HP ini, lalu lanjutkan di HP itu. '
                    'Mulai ${longDate(lock.until)} HP ini tidak lagi menerima catatan baru.',
            action: FilledButton(onPressed: () => context.go('/login'), child: const Text('Masuk di HP ini')),
          ),
        if (session?.sessionExpired ?? false)
          TerraBanner(
            kind: BannerKind.danger,
            icon: Icons.lock_clock_outlined,
            title: 'Sesi berakhir — masuk lagi',
            body: 'Data di HP ini AMAN dan tetap dapat diisi. Masuk lagi supaya antreannya dapat dikirim.',
            action: FilledButton(onPressed: () => context.go('/login'), child: const Text('Masuk')),
          ),
        if (clockOff)
          TerraBanner(
            kind: BannerKind.danger,
            icon: Icons.schedule,
            title: 'Jam HP ${clockDriftText(drift)} dari jam server',
            body: 'Semua jam bacaan bor dan jam TM diambil dari jam HP ini. '
                'Nyalakan "Tanggal & waktu otomatis" di pengaturan HP, lalu tarik data lagi.',
          ),
        if (rejected > 0)
          TerraBanner(
            kind: BannerKind.danger,
            title: '$rejected data ditolak server',
            body: 'Buka Antrean untuk melihat sebabnya dan memperbaikinya.',
            action: TextButton(onPressed: () => context.go('/queue'), child: const Text('Lihat')),
          ),
        if (showPending && (pending > 0 || pendingPhotos > 0) && !(session?.sessionExpired ?? false))
          TerraBanner(
            kind: stale ? BannerKind.danger : BannerKind.warning,
            icon: stale ? Icons.history_toggle_off : Icons.cloud_upload_outlined,
            title: syncState.running
                ? 'Mengirim…'
                : stale
                    ? 'Lebih dari sehari belum terkirim: $pending data, $pendingPhotos foto'
                    : 'Belum terkirim: $pending data, $pendingPhotos foto',
            body: stale
                ? 'Cari tempat bersinyal atau WiFi, lalu tekan Kirim. Bila tetap tidak terkirim, hubungi admin TerraBot.'
                : syncState.last?.offline ?? false
                    ? 'Tidak ada sinyal. Dikirim otomatis begitu HP mendapat sinyal, walau aplikasi ditutup.'
                    : 'Dikirim otomatis begitu ada sinyal.',
            action: syncState.running
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(
                    onPressed: () => ref.read(syncProvider.notifier).run(),
                    child: const Text('Kirim'),
                  ),
          ),
      ],
    );
  }
}
