import 'dart:convert';

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
import '../beranda/banner_sesi.dart';
import 'status_tinjau.dart';

class HalamanAbsensi extends ConsumerWidget {
  const HalamanAbsensi({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.warna;
    final dok = ref.watch(dokumenProvider('attendance'));
    final proyek = {for (final p in ref.watch(proyekProvider).value ?? const []) '${p['id']}': p};
    final boleh = ref.watch(sesiProvider).value?.boleh('field_attendance', 'create') ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Absensi kru')),
      floatingActionButton: boleh
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/absensi/baru'),
              icon: const Icon(Icons.add),
              label: const Text('Absen hari ini'),
            )
          : null,
      body: dok.when(
        loading: () => const KeadaanMuat(),
        error: (e, _) => KeadaanGagal(judul: 'Absen gagal dibaca', pesan: '$e'),
        data: (daftar) => ListView(
          padding: const EdgeInsets.fromLTRB(Ukuran.tepi, Ukuran.tepi, Ukuran.tepi, 96),
          children: [
            const BannerKeadaan(tampilkanBelumTerkirim: false),
            const KepalaHalaman(judul: 'Riwayat absen', deskripsi: 'Absen yang dibuat dari HP ini'),
            if (daftar.isEmpty) const KeadaanKosong(pesan: 'Belum ada absen.', ikon: Icons.how_to_reg_outlined),
            for (final d in daftar)
              Builder(builder: (context) {
                final isi = (jsonDecode(d.isi) as Map).cast<String, Object?>();
                final p = proyek['${isi['projectID']}'];
                final baris = (isi['lines'] as List?)?.length ?? 0;
                final masuk = isi['checkIn'] != null;
                final pulang = isi['checkOut'] != null;
                return KartuDaftar(
                  warnaTepi: d.statusKirim == 'ditolak' ? w.badFg : null,
                  onTap: () => context.push('/absensi/${d.uuid}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p == null ? 'Proyek #${isi['projectID']}' : '${p['code']} · ${p['name']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700, color: w.ink),
                            ),
                          ),
                          Lencana.statusKirim(context, d.statusKirim),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${isi['date']} · $baris kru · ${masuk ? 'masuk ✓' : 'belum masuk'} · ${pulang ? 'pulang ✓' : 'belum pulang'}',
                          style: TextStyle(color: w.muted, fontSize: 13)),
                      if (d.statusServer != null) ...[
                        const SizedBox(height: 6),
                        LencanaTinjau(status: d.statusServer!),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
