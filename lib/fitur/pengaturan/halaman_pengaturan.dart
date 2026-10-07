import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../inti/konfigurasi/env.dart';
import '../../inti/penyedia.dart';
import '../../inti/tema/token_warna.dart';
import '../../inti/tema/ukuran.dart';
import '../../inti/widget/banner_terra.dart';
import '../../inti/widget/kartu_daftar.dart';

class HalamanPengaturan extends ConsumerWidget {
  const HalamanPengaturan({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.warna;
    final konteks = ref.watch(konteksProvider);
    final sesi = ref.watch(sesiProvider).value;
    final belum = ref.watch(jumlahBelumTerkirimProvider).value ?? 0;
    final foto = ref.watch(jumlahFotoBelumTerkirimProvider).value ?? 0;

    Widget baris(String label, String nilai) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: w.muted))),
            Flexible(child: Text(nilai, textAlign: TextAlign.end, style: TextStyle(color: w.ink, fontWeight: FontWeight.w600))),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(Ukuran.tepi),
        children: [
          KartuDaftar(
            child: Column(children: [
              baris('Nama', sesi?.pengguna?.nama ?? '–'),
              baris('Email', sesi?.pengguna?.email ?? '–'),
              baris('Level', '${sesi?.izin.level ?? '–'}'),
              baris('Divisi', (sesi?.izin.divisi ?? const []).join(', ')),
            ]),
          ),
          KartuDaftar(
            child: Column(children: [
              baris('Versi aplikasi', Env.versiAplikasi),
              baris('Server', Env.apiUrl.replaceFirst('https://', '')),
              baris('ID perangkat', konteks.idPerangkat.substring(0, 8)),
            ]),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => ref.read(sesiProvider.notifier).segarkanIzin(),
            icon: const Icon(Icons.refresh),
            label: const Text('Muat ulang hak akses'),
          ),
          const SizedBox(height: 24),
          if (belum > 0 || foto > 0)
            BannerTerra(
              jenis: JenisBanner.awas,
              judul: 'Masih ada $belum data dan $foto foto belum terkirim',
              isi: 'Keluar TIDAK menghapusnya; terkirim begitu Anda masuk lagi. Tetapi orang lain yang masuk di HP ini tidak dapat mengirimnya.',
            ),
          FilledButton.tonalIcon(
            onPressed: () async {
              final ya = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Keluar?'),
                  content: const Text('Perlu sinyal untuk masuk lagi.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Keluar')),
                  ],
                ),
              );
              if (ya != true) return;
              await ref.read(sesiProvider.notifier).keluar();
              if (context.mounted) context.go('/masuk');
            },
            icon: const Icon(Icons.logout),
            label: const Text('Keluar'),
          ),
        ],
      ),
    );
  }
}
