import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../inti/penyedia.dart';
import '../../inti/tema/token_warna.dart';
import '../../inti/tema/ukuran.dart';
import '../../inti/widget/kartu_daftar.dart';
import '../../inti/widget/keadaan.dart';
import '../../inti/widget/kepala_halaman.dart';
import '../beranda/banner_sesi.dart';

/// Pilih proyek → daftar titik bor.
class HalamanPengecoran extends ConsumerWidget {
  const HalamanPengecoran({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.warna;
    final proyek = ref.watch(proyekProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Log pengecoran')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(sinkronProvider.notifier).jalankan(),
        child: proyek.when(
          loading: () => const KeadaanMuat(),
          error: (e, _) => KeadaanGagal(judul: 'Proyek gagal dibaca', pesan: '$e'),
          data: (daftar) => ListView(
            padding: const EdgeInsets.all(Ukuran.tepi),
            children: [
              const BannerKeadaan(tampilkanBelumTerkirim: false),
              const KepalaHalaman(judul: 'Pilih proyek', deskripsi: 'Titik bor diisi kantor dari gambar kerja'),
              if (daftar.isEmpty)
                const KeadaanKosong(pesan: 'Belum ada proyek di HP. Tarik ke bawah saat ada sinyal.', ikon: Icons.domain_disabled),
              for (final p in daftar)
                Consumer(builder: (context, ref, _) {
                  final jumlah = ref.watch(titikProvider((p['id'] as num).toInt())).value?.length;
                  return KartuDaftar(
                    onTap: () => context.push('/pengecoran/proyek/${p['id']}'),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${p['code']}', style: TextStyle(fontWeight: FontWeight.w800, color: w.brandStrong)),
                              Text('${p['name']}', style: TextStyle(color: w.ink)),
                            ],
                          ),
                        ),
                        Text(jumlah == null ? '' : '$jumlah titik', style: TextStyle(color: w.muted)),
                        Icon(Icons.chevron_right, color: w.muted),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
