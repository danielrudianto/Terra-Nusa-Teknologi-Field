import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/device/notifications.dart';
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
  const StatusBanners({
    super.key,
    this.showPending = true,
    this.showUpdate = false,
    this.showNotifWarning = false,
  });

  final bool showPending;

  /// Tampilkan ajakan memperbarui aplikasi.
  ///
  /// MATI bawaannya, dan dinyalakan HANYA di beranda. Ajakan yang muncul di
  /// layar pengecoran dan absen akan ditutup refleks tanpa dibaca — dan yang
  /// ditutup refleks sama saja dengan tidak ada. Beranda tempat orang berdiri
  /// sebelum mulai bekerja; di situ memperbarui tidak memotong apa pun.
  final bool showUpdate;

  /// Tampilkan peringatan bahwa HP tidak mengizinkan notifikasi.
  ///
  /// MATI bawaannya, dan dinyalakan HANYA di beranda — alasannya sama
  /// dengan `showUpdate`: peringatan yang muncul di layar pengecoran akan
  /// ditutup refleks tanpa dibaca. Beranda tempat orang berdiri sebelum
  /// mulai bekerja, dan satu ketukan di situ membetulkannya untuk seluruh
  /// hari itu.
  final bool showNotifWarning;

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

    // `false` saat masih dimuat, bukan `true`: spanduk yang berkedip muncul
    // lalu hilang tiap kali beranda dibuka lebih buruk daripada sedetik
    // terlambat.
    final notifMati = ref.watch(notificationsEnabledProvider).value == false;
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
        // PENGINGAT TIDAK AKAN MUNCUL — dan itu diam tanpa peringatan ini.
        //
        // Ditaruh di atas yang lain selain kunci perangkat dan sesi habis:
        // yang ini bukan satu dokumen yang tertahan, ini SELURUH pengingat
        // hari itu — TM yang lewat 20 menit, cor yang dijeda, log bor yang
        // lupa ditutup. Satu ketukan membetulkannya.
        if (showNotifWarning && notifMati)
          TerraBanner(
            kind: BannerKind.danger,
            icon: Icons.notifications_off,
            title: t(context).notifBlockedTitle,
            body: t(context).notifBlockedBody,
            action: FilledButton(
              onPressed: () async {
                await Notifications.requestPermission();
                if (!context.mounted) return;
                ref.invalidate(notificationsEnabledProvider);

                // KALAU MASIH MATI, KATAKAN APA YANG HARUS DILAKUKAN.
                //
                // `requestPermission` hanya memanggil
                // `requestNotificationsPermission()`, yang baru ada sejak
                // Android 13 — sementara `minSdk` aplikasi ini 24. Pada
                // Android 12 ke bawah tidak ada izin runtime sama sekali:
                // notifikasinya dimatikan dari Setelan telepon, dan tombol
                // ini tidak dapat menyalakannya. Hal yang sama terjadi di
                // Android 13+ sesudah dua kali ditolak — sistem berhenti
                // menampilkan dialognya.
                //
                // Tanpa kalimat ini, yang menekan tombol melihat spanduk
                // merah yang tidak bisa ditutup dan tidak berubah apa pun,
                // berapa kali pun ditekan. Spanduk yang tidak dapat
                // dipatuhi akan diabaikan — termasuk saat ia benar.
                final hidup = await Notifications.enabled();
                if (!context.mounted || hidup) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(t(context).notifAllowManual),
                    duration: const Duration(seconds: 6),
                  ),
                );
              },
              child: Text(t(context).notifAllow),
            ),
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
