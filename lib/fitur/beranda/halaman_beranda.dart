import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../inti/penyedia.dart';
import '../../inti/tema/token_warna.dart';
import '../../inti/tema/ukuran.dart';
import '../../inti/util/format.dart';
import '../../inti/widget/banner_terra.dart';
import '../../inti/widget/kartu_daftar.dart';
import 'banner_sesi.dart';

class HalamanBeranda extends ConsumerWidget {
  const HalamanBeranda({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.warna;
    final sesi = ref.watch(sesiProvider).value;
    final pengguna = sesi?.pengguna;
    final proyek = ref.watch(proyekProvider).value ?? const [];
    final bolehAbsen = sesi?.boleh('field_attendance', 'create') ?? false;
    final bolehCor = sesi?.boleh('field_casting', 'create') ?? false;
    final bolehPekerja = sesi?.boleh('field_worker', 'read') ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TerraBot Field'),
        actions: [
          IconButton(
            tooltip: 'Pengaturan',
            onPressed: () => context.push('/pengaturan'),
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: w.brandSoft,
              child: Text(pengguna?.inisial ?? '?', style: TextStyle(fontSize: 12, color: w.brandStrong, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(sinkronProvider.notifier).jalankan(),
        child: ListView(
          padding: const EdgeInsets.all(Ukuran.tepi),
          children: [
            Text('Halo, ${pengguna?.nama.split(' ').first ?? ''}',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: w.ink)),
            Text(tanggalPanjang(DateTime.now()), style: TextStyle(color: w.muted)),
            const SizedBox(height: 14),
            const BannerKeadaan(),
            if (proyek.isEmpty)
              const BannerTerra(
                jenis: JenisBanner.info,
                judul: 'Daftar proyek belum ada di HP',
                isi: 'Tarik ke bawah untuk mengambilnya dari server. Perlu sinyal sekali saja; sesudahnya dapat dipakai tanpa sinyal.',
              ),
            if (!bolehAbsen && !bolehCor)
              const BannerTerra(
                jenis: JenisBanner.awas,
                judul: 'Akun ini belum punya akses lapangan',
                isi: 'Minta admin TerraBot menambahkan divisi Field Engineer ke akun Anda, lalu tarik ke bawah.',
              ),
            if (bolehAbsen)
              _Pintasan(
                ikon: Icons.how_to_reg,
                judul: 'Absen kru',
                isi: 'Foto masuk & pulang, centang kru yang hadir',
                onTap: () => context.push('/absensi/baru'),
              ),
            if (bolehCor)
              _Pintasan(
                ikon: Icons.foundation,
                judul: 'Log pengecoran',
                isi: 'Tandai titik dibor, catat TM, tremie & sounding',
                onTap: () => context.go('/pengecoran'),
              ),
            if (bolehPekerja)
              _Pintasan(
                ikon: Icons.groups_outlined,
                judul: 'Kru saya',
                isi: 'Daftarkan pekerja baru dengan foto wajah',
                onTap: () => context.push('/pekerja'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pintasan extends StatelessWidget {
  const _Pintasan({required this.ikon, required this.judul, required this.isi, required this.onTap});

  final IconData ikon;
  final String judul;
  final String isi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    return KartuDaftar(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: w.brandSoft, borderRadius: BorderRadius.circular(12)),
            child: Icon(ikon, color: w.brandStrong),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(judul, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: w.ink)),
                Text(isi, style: TextStyle(color: w.muted, fontSize: 13)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: w.muted),
        ],
      ),
    );
  }
}
