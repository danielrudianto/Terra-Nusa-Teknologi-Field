import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../inti/db/database.dart';
import '../../inti/penyedia.dart';
import '../../inti/tema/token_warna.dart';
import '../../inti/tema/ukuran.dart';
import '../../inti/util/alasan.dart';
import '../../inti/util/format.dart';
import '../../inti/widget/banner_terra.dart';
import '../../inti/widget/kartu_daftar.dart';
import '../../inti/widget/keadaan.dart';
import '../../inti/widget/kepala_halaman.dart';
import '../../inti/widget/lencana.dart';
import '../beranda/banner_sesi.dart';

final _antreanProvider = StreamProvider<List<BarisDokumen>>((ref) {
  final p = ref.watch(penggunaProvider);
  if (p == null) return Stream.value(const []);
  return ref.watch(dbProvider).pantauAntrean(p.id);
});

final _fotoAntreanProvider = StreamProvider<List<BarisFoto>>((ref) {
  final p = ref.watch(penggunaProvider);
  if (p == null) return Stream.value(const []);
  return ref.watch(dbProvider).pantauFotoBelumTerkirim(p.id);
});

/// Yang belum selesai urusannya dengan server.
class HalamanAntrean extends ConsumerWidget {
  const HalamanAntrean({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.warna;
    final dok = ref.watch(_antreanProvider);
    final foto = ref.watch(_fotoAntreanProvider).value ?? const [];
    final sinkron = ref.watch(sinkronProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Antrean kirim')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(sinkronProvider.notifier).jalankan(),
        child: dok.when(
          loading: () => const KeadaanMuat(),
          error: (e, _) => KeadaanGagal(judul: 'Antrean gagal dibaca', pesan: '$e'),
          data: (daftar) => ListView(
            padding: const EdgeInsets.all(Ukuran.tepi),
            children: [
              const BannerKeadaan(),
              if (sinkron.terakhir?.galat != null)
                BannerTerra(jenis: JenisBanner.bahaya, judul: 'Kiriman terakhir gagal', isi: sinkron.terakhir!.galat),
              KepalaHalaman(
                judul: '${daftar.length} data · ${foto.length} foto',
                deskripsi: sinkron.waktu == null ? 'Belum dikirim sejak aplikasi dibuka' : 'Terakhir dicoba pukul ${jam(sinkron.waktu!)}',
              ),
              if (daftar.isEmpty && foto.isEmpty)
                const KeadaanKosong(pesan: 'Semua sudah terkirim.', ikon: Icons.cloud_done_outlined),
              for (final d in daftar) _KartuDok(d: d),
              if (foto.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Foto', style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
                const SizedBox(height: 6),
                for (final f in foto)
                  KartuDaftar(
                    warnaTepi: f.statusKirim == 'ditolak' ? w.badFg : null,
                    child: Row(
                      children: [
                        Icon(Icons.image_outlined, color: w.muted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_namaFoto(f.jenis)} · ${(f.ukuran / 1024).round()} kB · ${jam(f.diambil)}'
                            '${f.alasan == null ? '' : '\n${kalimatAlasan(f.alasan)}'}',
                            style: TextStyle(color: w.ink, fontSize: 13),
                          ),
                        ),
                        Lencana.statusKirim(context, f.statusKirim == 'lokal' ? (f.percobaan > 0 ? 'gagal' : 'lokal') : f.statusKirim),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _namaFoto(String jenis) => switch (jenis) {
        'wajah' => 'Wajah pekerja',
        'absen_masuk' => 'Absen masuk',
        'absen_pulang' => 'Absen pulang',
        'tiket_tm' => 'Tiket TM',
        _ => jenis,
      };
}

class _KartuDok extends ConsumerWidget {
  const _KartuDok({required this.d});

  final BarisDokumen d;

  String? get _rute => switch (d.entitas) {
        'attendance' => '/absensi/${d.uuid}',
        'casting' => '/pengecoran/cor/${d.uuid}',
        'worker' => '/pekerja/${d.uuid}',
        _ => null,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.warna;
    final ditolak = d.statusKirim == 'ditolak';
    return KartuDaftar(
      warnaTepi: ditolak ? w.badFg : null,
      onTap: _rute == null ? null : () => context.push(_rute!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${namaEntitas(d.entitas)} · v${d.versi}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
              ),
              Lencana.statusKirim(context, d.statusKirim),
            ],
          ),
          Text('Diubah ${jam(d.diubah)} · ${d.uuid.substring(0, 8)}', style: TextStyle(color: w.muted, fontSize: 12)),
          if (d.alasan != null) ...[
            const SizedBox(height: 6),
            Text(kalimatAlasan(d.alasan, d.detail), style: TextStyle(color: ditolak ? w.badFg : w.warnFg, fontSize: 13)),
          ],
          if (d.tundaSampai != null && !ditolak)
            Text('Dicoba lagi pukul ${jam(d.tundaSampai!)}', style: TextStyle(color: w.muted, fontSize: 12)),
          if (ditolak)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    final ya = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Buang dari HP?'),
                        content: const Text('Data ini tidak akan dikirim lagi. Tidak dapat dibatalkan.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Buang')),
                        ],
                      ),
                    );
                    if (ya == true) await ref.read(dbProvider).buangDokumen(d.uuid);
                  },
                  child: const Text('Buang'),
                ),
                TextButton(
                  onPressed: () async {
                    await ref.read(dbProvider).cobaLagiDokumen(d.uuid);
                    ref.read(sinkronProvider.notifier).setelahSimpan();
                  },
                  child: const Text('Kirim ulang'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
