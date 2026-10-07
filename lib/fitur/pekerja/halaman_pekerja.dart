import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../inti/penyedia.dart';
import '../../inti/tema/token_warna.dart';
import '../../inti/tema/ukuran.dart';
import '../../inti/widget/kartu_daftar.dart';
import '../../inti/widget/keadaan.dart';
import '../../inti/widget/kepala_halaman.dart';
import '../../inti/widget/lencana.dart';

class HalamanPekerja extends ConsumerWidget {
  const HalamanPekerja({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.warna;
    final pekerja = ref.watch(pekerjaProvider);
    final bolehTambah = ref.watch(sesiProvider).value?.boleh('field_worker', 'create') ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Kru saya')),
      floatingActionButton: bolehTambah
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/pekerja/baru'),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Pekerja baru'),
            )
          : null,
      body: pekerja.when(
        loading: () => const KeadaanMuat(),
        error: (e, _) => KeadaanGagal(judul: 'Daftar kru gagal dibaca', pesan: '$e'),
        data: (daftar) => ListView(
          padding: const EdgeInsets.fromLTRB(Ukuran.tepi, Ukuran.tepi, Ukuran.tepi, 96),
          children: [
            KepalaHalaman(judul: '${daftar.length} pekerja', deskripsi: 'Kru aktif yang dapat diabsen'),
            if (daftar.isEmpty) const KeadaanKosong(pesan: 'Belum ada kru. Daftarkan pekerja baru dengan tombol di bawah.'),
            for (final p in daftar)
              KartuDaftar(
                onTap: () => context.push('/pekerja/${p.uuid}'),
                child: Row(
                  children: [
                    CircleAvatar(backgroundColor: w.brandSoft, child: Icon(Icons.person, color: w.brandStrong)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.nama, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
                          if (p.telepon != null && p.telepon!.isNotEmpty)
                            Text(p.telepon!, style: TextStyle(color: w.muted, fontSize: 13)),
                        ],
                      ),
                    ),
                    if (p.lokal) Lencana.statusKirim(context, 'lokal'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
