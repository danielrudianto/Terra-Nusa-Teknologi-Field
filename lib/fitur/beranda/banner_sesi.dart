import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../inti/penyedia.dart';
import '../../inti/widget/banner_terra.dart';

/// Banner keadaan yang muncul di ATAS setiap halaman utama.
///
/// Urutan menurut gawatnya: sesi habis (antrean tidak dapat dikirim sama
/// sekali), ditolak (ada yang harus diperbaiki mandor), lalu belum
/// terkirim (cukup diketahui).
class BannerKeadaan extends ConsumerWidget {
  const BannerKeadaan({super.key, this.tampilkanBelumTerkirim = true});

  final bool tampilkanBelumTerkirim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesi = ref.watch(sesiProvider).value;
    final ditolak = ref.watch(jumlahDitolakProvider).value ?? 0;
    final belum = ref.watch(jumlahBelumTerkirimProvider).value ?? 0;
    final foto = ref.watch(jumlahFotoBelumTerkirimProvider).value ?? 0;
    final sinkron = ref.watch(sinkronProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sesi?.sesiHabis ?? false)
          BannerTerra(
            jenis: JenisBanner.bahaya,
            ikon: Icons.lock_clock_outlined,
            judul: 'Sesi berakhir — masuk lagi',
            isi: 'Data di HP ini AMAN dan tetap dapat diisi. Masuk lagi supaya antreannya dapat dikirim.',
            aksi: FilledButton(onPressed: () => context.go('/masuk'), child: const Text('Masuk')),
          ),
        if (ditolak > 0)
          BannerTerra(
            jenis: JenisBanner.bahaya,
            judul: '$ditolak data ditolak server',
            isi: 'Buka Antrean untuk melihat sebabnya dan memperbaikinya.',
            aksi: TextButton(onPressed: () => context.go('/antrean'), child: const Text('Lihat')),
          ),
        if (tampilkanBelumTerkirim && (belum > 0 || foto > 0) && !(sesi?.sesiHabis ?? false))
          BannerTerra(
            jenis: JenisBanner.awas,
            ikon: Icons.cloud_upload_outlined,
            judul: sinkron.berjalan ? 'Mengirim…' : 'Belum terkirim: $belum data, $foto foto',
            isi: sinkron.terakhir?.tanpaJaringan ?? false
                ? 'Tidak ada sinyal. Dikirim otomatis begitu HP mendapat sinyal, walau aplikasi ditutup.'
                : 'Dikirim otomatis begitu ada sinyal.',
            aksi: sinkron.berjalan
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(
                    onPressed: () => ref.read(sinkronProvider.notifier).jalankan(),
                    child: const Text('Kirim'),
                  ),
          ),
      ],
    );
  }
}
