import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../inti/penyedia.dart';
import '../../inti/tema/token_warna.dart';
import '../../inti/tema/ukuran.dart';
import '../../inti/util/format.dart';
import '../../inti/widget/banner_terra.dart';
import '../../inti/widget/kartu_daftar.dart';
import '../../inti/widget/keadaan.dart';
import '../../inti/widget/lencana.dart';
import 'data_titik.dart';

/// Titik bor satu proyek.
class HalamanTitik extends ConsumerStatefulWidget {
  const HalamanTitik({super.key, required this.proyekId});

  final int proyekId;

  @override
  ConsumerState<HalamanTitik> createState() => _HalamanTitikState();
}

class _HalamanTitikState extends ConsumerState<HalamanTitik> {
  String _saring = 'semua';
  String _cari = '';

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    final data = ref.watch(titikLapanganProvider(widget.proyekId));
    final proyek = (ref.watch(proyekProvider).value ?? const []).where((p) => '${p['id']}' == '${widget.proyekId}').firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(proyek == null ? 'Titik bor' : '${proyek['code']} · titik bor')),
      body: data.when(
        loading: () => const KeadaanMuat(),
        error: (e, _) => KeadaanGagal(judul: 'Titik gagal dibaca', pesan: '$e'),
        data: (semua) {
          final daftar = semua.where((t) {
            if (_cari.isNotEmpty && !t.kode.toLowerCase().contains(_cari.toLowerCase())) return false;
            return switch (_saring) {
              'belum' => t.keadaan == 'belum_bor',
              'bor' => t.keadaan == 'sudah_bor' || t.keadaan == 'berjalan',
              'cor' => t.keadaan == 'selesai' || t.keadaan == 'sudah_cor',
              _ => true,
            };
          }).toList();
          final dicor = semua.where((t) => t.keadaan == 'selesai' || t.keadaan == 'sudah_cor').length;

          return ListView(
            padding: const EdgeInsets.all(Ukuran.tepi),
            children: [
              if (semua.isEmpty)
                const BannerTerra(
                  jenis: JenisBanner.info,
                  judul: 'Belum ada titik bor',
                  isi: 'Titik bor diisi kantor (impor Excel di TerraBot web). Tarik ke bawah di halaman sebelumnya untuk mengambil yang terbaru.',
                )
              else
                Text('$dicor dari ${semua.length} titik sudah dicor', style: TextStyle(color: w.muted)),
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari kode titik'),
                onChanged: (v) => setState(() => _cari = v.trim()),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final (k, l) in const [('semua', 'Semua'), ('belum', 'Belum bor'), ('bor', 'Dibor'), ('cor', 'Dicor')])
                    ChoiceChip(label: Text(l), selected: _saring == k, onSelected: (_) => setState(() => _saring = k)),
                ],
              ),
              const SizedBox(height: 12),
              if (semua.isNotEmpty && daftar.isEmpty) const KeadaanKosong(pesan: 'Tidak ada titik yang cocok.'),
              for (final t in daftar) _kartu(t),
            ],
          );
        },
      ),
    );
  }

  Widget _kartu(TitikLapangan t) {
    final w = context.warna;
    final g = t.geometri;
    final (teks, latar, depan) = switch (t.keadaan) {
      'berjalan' => ('Sedang dicor', w.warnBg, w.warnFg),
      'selesai' || 'sudah_cor' => ('Sudah dicor', w.okBg, w.okFg),
      'sudah_bor' => ('Dibor ${meter(t.kedalamanBorM)}', w.infoBg, w.infoFg),
      _ => ('Belum dibor', w.surface2, w.muted),
    };
    return KartuDaftar(
      onTap: () => _aksi(t),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.kode, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: w.ink)),
                Text('D${t.diameterMm} · efektif ${meter(g.panjangEfektifRencanaM)} · ${g.volumeTeoritisRencanaM3.toStringAsFixed(2).replaceAll('.', ',')} m³',
                    style: TextStyle(color: w.muted, fontSize: 13)),
              ],
            ),
          ),
          Lencana(teks: teks, latar: latar, depan: depan),
        ],
      ),
    );
  }

  Future<void> _aksi(TitikLapangan t) async {
    final sesi = ref.read(sesiProvider).value;
    final boleh = sesi?.boleh('field_casting', 'create') ?? false;
    final g = t.geometri;
    final w = context.warna;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Ukuran.tepi, 0, Ukuran.tepi, Ukuran.tepi),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Titik ${t.kode}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: w.ink)),
              const SizedBox(height: 8),
              _Baris('Diameter', '${t.diameterMm} mm'),
              _Baris('GS / cut-off / tip', '${_el(g.groundLevel)} / ${_el(g.cutOffLevel)} / ${_el(g.tipLevel)}'),
              _Baris('Kedalaman cut-off dari GS', meter(g.kedalamanCutOffM)),
              _Baris('Panjang bor rencana', meter(g.panjangBorRencanaM)),
              _Baris('Panjang efektif rencana', meter(g.panjangEfektifRencanaM)),
              _Baris('Volume teoritis rencana', '${g.volumeTeoritisRencanaM3.toStringAsFixed(2).replaceAll('.', ',')} m³'),
              if (t.kedalamanBorM != null) _Baris('Kedalaman bor aktual', meter(t.kedalamanBorM)),
              const SizedBox(height: 14),
              if (!boleh)
                const BannerTerra(jenis: JenisBanner.info, judul: 'Hanya dapat dilihat', isi: 'Akun ini tidak berhak mencatat log cor.')
              else ...[
                if (t.keadaan == 'belum_bor' || t.keadaan == 'sudah_bor')
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      _tandaiBor(t);
                    },
                    icon: const Icon(Icons.straighten),
                    label: Text(t.keadaan == 'belum_bor' ? 'Tandai sudah dibor' : 'Koreksi kedalaman bor'),
                  ),
                const SizedBox(height: 10),
                if (t.cor != null)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      context.push('/pengecoran/cor/${t.cor!.uuid}');
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Buka log cor'),
                  )
                else if (t.keadaan != 'sudah_cor')
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      context.push('/pengecoran/cor/${uuidBaru()}?titik=${t.uuid}');
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Mulai log cor'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _el(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2).replaceAll('.', ',')}';

  Future<void> _tandaiBor(TitikLapangan t) async {
    final awal = t.kedalamanBorM ?? t.geometri.panjangBorRencanaM;
    final isian = TextEditingController(text: awal.toStringAsFixed(2).replaceAll('.', ','));
    final w = context.warna;
    final hasil = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Kedalaman bor ${t.kode}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Diukur dari muka tanah (GS) titik ini sampai dasar lubang. Rencana: ${meter(t.geometri.panjangBorRencanaM)}.',
                style: TextStyle(color: w.muted)),
            const SizedBox(height: 12),
            TextField(
              controller: isian,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Kedalaman (m)', suffixText: 'm'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              final v = bacaAngka(isian.text);
              if (v == null || v <= 0 || v > 200) return;
              Navigator.pop(c, v);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    isian.dispose();
    if (hasil == null) return;
    final p = ref.read(penggunaProvider);
    if (p == null) return;
    await ref.read(dbProvider).simpanDokumen(
      uuid: uuidBaru(),
      entitas: 'drill_mark',
      userId: p.id,
      isi: {'pilePointUuid': t.uuid, 'drilledDepthM': angkaTeks(hasil), 'at': isoBerzona(DateTime.now())},
    );
    ref.read(sinkronProvider.notifier).setelahSimpan();
  }
}

class _Baris extends StatelessWidget {
  const _Baris(this.label, this.nilai);

  final String label;
  final String nilai;

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: w.muted))),
          Text(nilai, style: TextStyle(fontWeight: FontWeight.w600, color: w.ink)),
        ],
      ),
    );
  }
}
