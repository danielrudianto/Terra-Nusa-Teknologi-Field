import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../inti/penyedia.dart';
import '../../inti/perangkat/kamera.dart';
import '../../inti/tema/token_warna.dart';
import '../../inti/tema/ukuran.dart';
import '../../inti/util/alasan.dart';
import '../../inti/util/format.dart';
import '../../inti/widget/banner_terra.dart';

/// Daftarkan pekerja baru — atau ubah yang sudah ada bila berhak.
///
/// Isian dokumen = PERSIS `DataPekerja` di server (name, phone,
/// facePhotoUuid, note, isActive). Bidang lain ditolak server.
class FormPekerja extends ConsumerStatefulWidget {
  const FormPekerja({super.key, required this.uuid});

  final String? uuid;

  @override
  ConsumerState<FormPekerja> createState() => _FormPekerjaState();
}

class _FormPekerjaState extends ConsumerState<FormPekerja> {
  final _nama = TextEditingController();
  final _telepon = TextEditingController();
  final _catatan = TextEditingController();
  late final String _uuid = widget.uuid ?? uuidBaru();
  String? _fotoUuid;
  String? _fotoPath;
  int? _jumlahWajah;
  int? _versiServer;
  bool _dariServerSaja = false;
  bool _muat = true;
  bool _simpan = false;
  String? _alasanTolak;

  @override
  void initState() {
    super.initState();
    _baca();
  }

  Future<void> _baca() async {
    if (widget.uuid != null) {
      final db = ref.read(dbProvider);
      final dok = await db.satuDokumen(_uuid);
      Map<String, Object?>? isi;
      if (dok != null) {
        isi = (jsonDecode(dok.isi) as Map).cast<String, Object?>();
        if (dok.statusKirim == 'ditolak') _alasanTolak = kalimatAlasan(dok.alasan, dok.detail);
      } else {
        isi = await db.satuInduk('pekerja', _uuid);
        _dariServerSaja = isi != null;
        _versiServer = keInt(isi?['clientVersion']);
      }
      if (isi != null) {
        _nama.text = '${isi['name'] ?? ''}';
        _telepon.text = '${isi['phone'] ?? ''}';
        _catatan.text = '${isi['note'] ?? ''}';
        _fotoUuid = isi['facePhotoUuid']?.toString();
        if (_fotoUuid != null) _fotoPath = (await db.satuFoto(_fotoUuid!))?.path;
      }
    }
    if (mounted) setState(() => _muat = false);
  }

  @override
  void dispose() {
    _nama.dispose();
    _telepon.dispose();
    _catatan.dispose();
    super.dispose();
  }

  bool get _bolehUbah {
    final sesi = ref.read(sesiProvider).value;
    if (sesi == null) return false;
    // Pekerja yang dibuat di HP ini dan belum diterima server: boleh.
    // Yang sudah di server: hanya bila berhak `update` (level 3+).
    return _dariServerSaja ? sesi.boleh('field_worker', 'update') : sesi.boleh('field_worker', 'create');
  }

  Future<void> _foto() async {
    final p = ref.read(penggunaProvider);
    if (p == null) return;
    try {
      final f = await ambilFoto(db: ref.read(dbProvider), userId: p.id, jenis: 'wajah', hitungWajah: true);
      if (f == null) return;
      setState(() {
        _fotoUuid = f.uuid;
        _fotoPath = f.path;
        _jumlahWajah = f.jumlahWajah;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kamera gagal: $e')));
    }
  }

  Future<void> _simpanDok() async {
    final nama = _nama.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (nama.isEmpty) {
      setState(() => _alasanTolak = 'Isi nama pekerja.');
      return;
    }
    final p = ref.read(penggunaProvider);
    if (p == null) return;
    setState(() => _simpan = true);
    await ref.read(dbProvider).simpanDokumen(
      uuid: _uuid,
      entitas: 'worker',
      userId: p.id,
      versiServer: _dariServerSaja ? (_versiServer ?? 1) : null,
      isi: {
        'name': nama,
        'phone': _telepon.text.trim().isEmpty ? null : _telepon.text.trim(),
        'facePhotoUuid': _fotoUuid,
        'note': _catatan.text.trim().isEmpty ? null : _catatan.text.trim(),
        'isActive': true,
      },
    );
    ref.read(sinkronProvider.notifier).setelahSimpan();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    final bolehUbah = !_muat && _bolehUbah;
    return Scaffold(
      appBar: AppBar(title: Text(widget.uuid == null ? 'Pekerja baru' : 'Pekerja')),
      body: _muat
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(Ukuran.tepi),
              children: [
                if (_alasanTolak != null) BannerTerra(jenis: JenisBanner.bahaya, judul: 'Perlu diperbaiki', isi: _alasanTolak),
                if (!bolehUbah)
                  const BannerTerra(
                    jenis: JenisBanner.info,
                    judul: 'Hanya dapat dilihat',
                    isi: 'Pekerja yang sudah terdaftar di server hanya dapat diubah oleh kantor (level 3 ke atas).',
                  ),
                Center(
                  child: GestureDetector(
                    onTap: bolehUbah ? _foto : null,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: w.surface2,
                        borderRadius: BorderRadius.circular(70),
                        image: _fotoPath != null
                            ? DecorationImage(image: FileImage(File(_fotoPath!)), fit: BoxFit.cover)
                            : null,
                      ),
                      child: _fotoPath == null ? Icon(Icons.add_a_photo_outlined, size: 40, color: w.muted) : null,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_jumlahWajah != null && _jumlahWajah != 1)
                  BannerTerra(
                    jenis: JenisBanner.awas,
                    judul: _jumlahWajah == 0 ? 'Wajah tidak terdeteksi' : '$_jumlahWajah wajah terdeteksi',
                    isi: 'Foto wajah dipakai kantor untuk mencocokkan kru. Ambil ulang dengan satu wajah, menghadap kamera.',
                    aksi: TextButton(onPressed: _foto, child: const Text('Ulang')),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nama,
                  enabled: bolehUbah,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nama lengkap'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _telepon,
                  enabled: bolehUbah,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'No. HP (opsional)'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _catatan,
                  enabled: bolehUbah,
                  decoration: const InputDecoration(labelText: 'Catatan (mis. tukang besi, operator)'),
                ),
                const SizedBox(height: 24),
                if (bolehUbah)
                  SizedBox(
                    height: Ukuran.sentuhMinimum + 4,
                    child: FilledButton.icon(
                      onPressed: _simpan ? null : _simpanDok,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Simpan'),
                    ),
                  ),
              ],
            ),
    );
  }
}
