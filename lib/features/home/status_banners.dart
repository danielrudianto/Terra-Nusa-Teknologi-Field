import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/util/clock_drift.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/util/format.dart';
import '../../core/i18n.dart';

/// Status banners shown at the TOP of every main page.
///
/// Ordered by severity: session expired (the queue cannot be pushed at all),
/// rejected (something the foreman must fix), then not yet pushed (just
/// good to know).
class StatusBanners extends ConsumerWidget {
  const StatusBanners({super.key, this.showPending = true, this.showUpdate = false});

  final bool showPending;

  /// Tampilkan ajakan memperbarui aplikasi.
  ///
  /// MATI bawaannya, dan dinyalakan HANYA di beranda. Ajakan yang muncul di
  /// layar pengecoran dan absen akan ditutup refleks tanpa dibaca — dan yang
  /// ditutup refleks sama saja dengan tidak ada. Beranda tempat orang berdiri
  /// sebelum mulai bekerja; di situ memperbarui tidak memotong apa pun.
  final bool showUpdate;

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

    // Ajakan memperbarui: hanya bila layar ini memintanya, ada versi lebih
    // baru, dan penundaannya untuk VERSI ITU belum habis. Penundaan disimpan
    // beserta versinya — menunda 1.0.6 tidak boleh ikut menyembunyikan 1.0.7.
    //
    // Hasilnya satu variabel BERNILAI atau `null`, bukan bendera `bool`
    // terpisah: Dart tidak mempromosikan `update` menjadi non-null lewat
    // bendera, jadi bentuk itu menuntut `!` di setiap pemakaiannya.
    final tersedia = ref.watch(updateAvailableProvider).value;
    final snooze = ref.watch(updateSnoozeProvider).value;
    final update = (showUpdate &&
            tersedia != null &&
            !(snooze?.menunda(tersedia.latestVersion, DateTime.now()) ?? false))
        ? tersedia
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Satu akun, satu HP. Paling atas bersama sesi berakhir: selama ini
        // tidak dibereskan, apa pun yang dicatat di HP ini akhirnya ditolak.
        if (lock != null)
          TerraBanner(
            kind: lock.graceOver ? BannerKind.danger : BannerKind.warning,
            icon: Icons.phonelink_lock,
            title: lock.graceOver ? t(context).phoneReplacedTitle : t(context).accountUsedElsewhere,
            body: lock.graceOver
                ? t(context).phoneReplacedBody
                : t(context).accountUsedElsewhereBody(
                    lock.byName == null ? '' : t(context).inParens(lock.byName!),
                    longDate(lock.until),
                  ),
            action: FilledButton(onPressed: () => context.go('/login'), child: Text(t(context).signInOnThisPhone)),
          ),
        if (session?.sessionExpired ?? false)
          TerraBanner(
            kind: BannerKind.danger,
            icon: Icons.lock_clock_outlined,
            title: t(context).sessionExpired,
            body: t(context).sessionExpiredBody,
            action: FilledButton(onPressed: () => context.go('/login'), child: Text(t(context).signIn)),
          ),
        if (clockOff)
          TerraBanner(
            kind: BannerKind.danger,
            icon: Icons.schedule,
            title: t(context).clockOffTitle(clockDriftText(drift)),
            body: t(context).clockOffBody,
          ),
        if (rejected > 0)
          TerraBanner(
            kind: BannerKind.danger,
            title: t(context).rejectedCount(rejected),
            body: t(context).rejectedBody,
            action: TextButton(onPressed: () => context.go('/queue'), child: Text(t(context).view)),
          ),
        if (showPending && (pending > 0 || pendingPhotos > 0) && !(session?.sessionExpired ?? false))
          TerraBanner(
            kind: stale ? BannerKind.danger : BannerKind.warning,
            icon: stale ? Icons.history_toggle_off : Icons.cloud_upload_outlined,
            title: syncState.running
                ? t(context).sending
                : stale
                    ? t(context).staleUnsent(pending, pendingPhotos)
                    : t(context).unsent(pending, pendingPhotos),
            body: stale
                ? t(context).staleUnsentBody
                : syncState.last?.offline ?? false
                    ? t(context).offlineAutoSend
                    : t(context).autoSendOnSignal,
            action: syncState.running
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(
                    onPressed: () => ref.read(syncProvider.notifier).run(diminta: true),
                    child: Text(t(context).send),
                  ),
          ),
        // PALING BAWAH, dan `info` — bukan peringatan.
        //
        // Tidak ada yang rusak dan tidak ada yang perlu dikerjakan sekarang;
        // mengangkatnya ke `warning` membuat kru belajar bahwa warna oranye
        // di aplikasi ini kadang tidak berarti apa-apa, lalu peringatan yang
        // sungguhan ikut tidak dibaca.
        if (update != null)
          TerraBanner(
            kind: BannerKind.info,
            icon: Icons.system_update,
            title: t(context).updateAvailableTitle(update.latestVersion),
            body: t(context).updateAvailableBody,
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(dbProvider)
                      .writeMeta(
                        'update_snooze',
                        UpdateSnooze(
                          version: update.latestVersion,
                          until: DateTime.now().add(UpdateSnooze.durasi),
                        ).encode(),
                      ),
                  child: Text(t(context).later),
                ),
                if (update.downloadUrl != null)
                  FilledButton(
                    onPressed: () => launchUrl(
                      Uri.parse(update.downloadUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(t(context).updateNow),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
