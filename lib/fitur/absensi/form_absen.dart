import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../inti/db/database.dart';
import '../../inti/penyedia.dart';
import '../../inti/perangkat/jam.dart';
import '../../inti/perangkat/kamera.dart';
import '../../inti/perangkat/lokasi.dart';
import '../../inti/tema/token_warna.dart';
import '../../inti/tema/ukuran.dart';
import '../../inti/util/alasan.dart';
import '../../inti/util/format.dart';
import '../../inti/util/jarak.dart';
import '../../inti/widget/banner_terra.dart';
import '../../inti/widget/kartu_daftar.dart';
import '../../inti/widget/lencana.dart';

/// Absen kru satu proyek, satu hari.
///
/// ISI DOKUMEN = PERSIS `DataAbsen` DI SERVER
///
///   projectID, date, checkIn{...}, checkOut{...}, lines[{uuid, workerUuid,
///   status, overtimeHours}]
///
/// Tidak ada bidang lain — server menolak bidang yang tidak dikenalnya.
///
/// DISIMPAN SETIAP KALI
///
/// Absen masuk/pulang langsung disimpan begitu fotonya diambil: HP yang
/// mati kehabisan baterai di tengah hari tidak boleh kehilangan absen
/// paginya. Centang kru disimpan dengan tombol Simpan.
class FormAbsen extends ConsumerStatefulWidget {
  const FormAbsen({super.key, required this.uuid, this.proyekId});

  final String? uuid;
  final int? proyekId;

  @override
  ConsumerState<FormAbsen> createState() => _FormAbsenState();
}

class _Baris {
  _Baris({required this.uuid, this.status = 'hadir', this.lembur = 0});

  final String uuid;
  String status;
  double lembur;
}

class _FormAbsenState extends ConsumerState<FormAbsen> {
  late final String _uuid = widget.uuid ?? uuidBaru();
  int? _proyekId;
  String _tanggal = tanggalIso(DateTime.now());
  Map<String, Object?>? _masuk;
  Map<String, Object?>? _pulang;
  final Map<String, _Baris> _baris = {};
  BarisDokumen? _dok;
  bool _muat = true;
  bool _sibuk = false;
  bool _berubah = false;
  String? _masalahLokasi;

  @override
  void initState() {
    super.initState();
    _proyekId = widget.proyekId;
    _baca();
  }

  Future<void> _baca() async {
    if (widget.uuid != null) {
      final d = await ref.read(dbProvider).satuDokumen(_uuid);
      if (d != null) _isiDari(d);
    } else if (_proyekId != null && await _bukaYangSudahAda(_proyekId!)) {
      return;
    }
    if (mounted) setState(() => _muat = false);
  }

  void _isiDari(BarisDokumen d) {
    final isi = (jsonDecode(d.isi) as Map).cast<String, Object?>();
    _dok = d;
    _proyekId = keInt(isi['projectID']);
    _tanggal = '${isi['date']}';
    _masuk = (isi['checkIn'] as Map?)?.cast<String, Object?>();
    _pulang = (isi['checkOut'] as Map?)?.cast<String, Object?>();
    _baris.clear();
    for (final b in (isi['lines'] as List?) ?? const []) {
      final m = (b as Map).cast<String, Object?>();
      _baris['${m['workerUuid']}'] = _Baris(
        uuid: '${m['uuid']}',
        status: '${m['status'] ?? 'hadir'}',
        lembur: keDouble(m['overtimeHours']) ?? 0,
      );
    }
  }

  /// Terkunci bila kantor sudah meninjau (disetujui atau ditolak).
  bool get _terkunci {
    final s = _dok?.statusServer;
    return s != null && s != 'dikirim';
  }

  /// Proyek & tanggal tetap setelah pernah diterima server.
  bool get _proyekTetap => (_dok?.versiTerkirim ?? 0) > 0;

  Map<String, Object?>? get _proyek {
    final semua = ref.read(proyekProvider).value ?? const [];
    for (final p in semua) {
      if ('${p['id']}' == '$_proyekId') return p;
    }
    return null;
  }

  Map<String, Object?> _isiDokumen() => {
        'projectID': _proyekId,
        'date': _tanggal,
        'checkIn': _masuk,
        'checkOut': _pulang,
        'lines': [
          for (final e in _baris.entries)
            {
              'uuid': e.value.uuid,
              'workerUuid': e.key,
              'status': e.value.status,
              'overtimeHours': angkaTeks(e.value.lembur, desimal: 1),
            },
        ],
      };

  Future<void> _simpan({bool tutup = false}) async {
    final p = ref.read(penggunaProvider);
    if (p == null || _proyekId == null) return;
    final db = ref.read(dbProvider);
    await db.simpanDokumen(uuid: _uuid, entitas: 'attendance', userId: p.id, isi: _isiDokumen());
    _dok = await db.satuDokumen(_uuid);
    _berubah = false;
    ref.read(sinkronProvider.notifier).setelahSimpan();
    if (!mounted) return;
    if (tutup) {
      context.pop();
    } else {
      setState(() {});
    }
  }

  /// Satu absen per proyek per hari: bila sudah ada di HP, buka yang itu.
  Future<bool> _bukaYangSudahAda(int proyekId) async {
    final p = ref.read(penggunaProvider);
    if (p == null) return false;
    final semua = await ref.read(dbProvider).pantauDokumen('attendance', p.id).first;
    for (final d in semua) {
      if (d.uuid == _uuid) continue;
      final isi = (jsonDecode(d.isi) as Map).cast<String, Object?>();
      if ('${isi['projectID']}' == '$proyekId' && '${isi['date']}' == _tanggal) {
        if (mounted) context.pushReplacement('/absensi/${d.uuid}');
        return true;
      }
    }
    return false;
  }

  Future<void> _kejadian({required bool masuk}) async {
    final p = ref.read(penggunaProvider);
    if (p == null || _proyekId == null) return;
    setState(() {
      _sibuk = true;
      _masalahLokasi = null;
    });
    try {
      // GPS dimulai BERSAMAAN dengan kamera: saat foto selesai diambil,
      // lokasinya biasanya sudah didapat.
      final lokasiNanti = ambilLokasi();
      final foto = await ambilFoto(
        db: ref.read(dbProvider),
        userId: p.id,
        jenis: masuk ? 'absen_masuk' : 'absen_pulang',
        hitungWajah: true,
      );
      if (foto == null) return;
      final stempel = await StempelWaktu.sekarang();
      final lokasi = await lokasiNanti;
      final kejadian = <String, Object?>{
        ...stempel.keKejadian(),
        if (lokasi.titik != null) ...lokasi.titik!.keKejadian() else 'isMocked': false,
        'photoUuid': foto.uuid,
        'faceCount': foto.jumlahWajah,
      };
      setState(() {
        if (masuk) {
          _masuk = kejadian;
        } else {
          _pulang = kejadian;
        }
        _masalahLokasi = lokasi.masalah;
      });
      await _simpan();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e')));
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    if (_muat) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // Status kirim/tinjau terbaru (berubah sendiri saat sinkron berjalan).
    final hidup = ref.watch(_dokumenHidupProvider(_uuid)).value;
    if (hidup != null) _dok = hidup;

    final proyekSemua = ref.watch(proyekProvider).value ?? const [];
    final pekerja = ref.watch(pekerjaProvider).value ?? const <Pekerja>[];
    final proyek = _proyek;
    final hadir = _baris.length;

    return PopScope(
      canPop: !_berubah,
      onPopInvokedWithResult: (sudah, _) async {
        if (sudah) return;
        final simpan = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Simpan centang kru?'),
            content: const Text('Ada perubahan kru yang belum disimpan.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Buang')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Simpan')),
            ],
          ),
        );
        if (!context.mounted) return;
        if (simpan == true) {
          await _simpan(tutup: true);
        } else if (simpan == false) {
          setState(() => _berubah = false);
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Absen kru'),
          actions: [if (_dok != null) Padding(padding: const EdgeInsets.only(right: 12), child: Lencana.statusKirim(context, _dok!.statusKirim))],
        ),
        bottomNavigationBar: _terkunci || _proyekId == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Ukuran.tepi, 8, Ukuran.tepi, 12),
                  child: SizedBox(
                    height: Ukuran.sentuhMinimum + 4,
                    child: FilledButton.icon(
                      onPressed: _sibuk ? null : () => _simpan(tutup: true),
                      icon: const Icon(Icons.save_outlined),
                      label: Text('Simpan · $hadir kru'),
                    ),
                  ),
                ),
              ),
        body: ListView(
          padding: const EdgeInsets.all(Ukuran.tepi),
          children: [
            if (_dok?.statusKirim == 'ditolak')
              BannerTerra(
                jenis: JenisBanner.bahaya,
                judul: 'Ditolak server',
                isi: kalimatAlasan(_dok!.alasan, _dok!.detail),
              ),
            if (_dok?.statusServer != null && _dok!.statusServer != 'dikirim')
              BannerTerra(
                jenis: _dok!.statusServer == 'ditolak' ? JenisBanner.bahaya : JenisBanner.ok,
                judul: _dok!.statusServer == 'ditolak' ? 'Ditolak kantor' : 'Sudah disetujui kantor',
                isi: [
                  if (_dok!.catatanServer != null && _dok!.catatanServer!.isNotEmpty) 'Catatan: ${_dok!.catatanServer}',
                  'Absen ini tidak dapat diubah lagi dari HP.',
                ].join('\n'),
              ),
            ..._bannerPenanda(),

            // --- proyek ---------------------------------------------------
            Text('Proyek', style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _proyekId,
              isExpanded: true,
              hint: const Text('Pilih proyek'),
              items: [
                for (final p in proyekSemua)
                  DropdownMenuItem(value: keInt(p['id']), child: Text('${p['code']} · ${p['name']}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _proyekTetap || _terkunci
                  ? null
                  : (v) async {
                      if (v == null) return;
                      if (await _bukaYangSudahAda(v)) return;
                      setState(() => _proyekId = v);
                    },
            ),
            const SizedBox(height: 6),
            Text(tanggalPanjang(DateTime.parse(_tanggal)), style: TextStyle(color: w.muted)),
            const SizedBox(height: 16),
            if (_proyekId != null && proyek != null && (proyek['latitude'] == null || proyek['longitude'] == null))
              const BannerTerra(
                jenis: JenisBanner.info,
                judul: 'Lokasi proyek belum diisi kantor',
                isi: 'Absen tetap tersimpan; jarak ke proyek tidak dapat diperiksa.',
              ),

            if (_proyekId != null) ...[
              _KartuKejadian(
                judul: 'Absen masuk',
                kejadian: _masuk,
                proyek: proyek,
                sibuk: _sibuk,
                aktif: !_terkunci,
                onAmbil: () => _kejadian(masuk: true),
              ),
              _KartuKejadian(
                judul: 'Absen pulang',
                kejadian: _pulang,
                proyek: proyek,
                sibuk: _sibuk,
                aktif: !_terkunci && _masuk != null,
                onAmbil: () => _kejadian(masuk: false),
              ),
              if (_masalahLokasi != null)
                BannerTerra(
                  jenis: JenisBanner.awas,
                  ikon: Icons.location_off_outlined,
                  judul: 'Tersimpan tanpa lokasi',
                  isi: '$_masalahLokasi Kantor akan melihat absen ini bertanda "tanpa lokasi".',
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text('Kru hadir ($hadir)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: w.ink))),
                  if (!_terkunci)
                    TextButton.icon(
                      onPressed: () => context.push('/pekerja/baru'),
                      icon: const Icon(Icons.person_add_alt_1, size: 18),
                      label: const Text('Pekerja baru'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (pekerja.isEmpty)
                const BannerTerra(
                  jenis: JenisBanner.info,
                  judul: 'Belum ada kru',
                  isi: 'Daftarkan pekerja baru dulu. Pekerja yang didaftarkan di sini langsung dapat diabsen, walau belum terkirim.',
                ),
              for (final k in pekerja) _barisKru(k),
              // Kru yang tercentang tetapi sudah tidak ada di daftar (dihapus
              // kantor) tetap ditampilkan, supaya dapat dilepas.
              for (final u in _baris.keys.where((u) => !pekerja.any((k) => k.uuid == u)).toList())
                _barisKru(Pekerja(uuid: u, nama: 'Pekerja tidak dikenal')),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _bannerPenanda() {
    final t = _dok?.penanda;
    if (t == null) return const [];
    final m = (jsonDecode(t) as Map).cast<String, Object?>();
    final semua = <String>{
      for (final v in m.values)
        if (v is List) ...v.map((e) => '$e'),
    };
    if (semua.isEmpty) return const [];
    final kalimat = semua.map(_kalimatPenanda).join('\n');
    return [
      BannerTerra(
        jenis: JenisBanner.awas,
        ikon: Icons.flag_outlined,
        judul: 'Ditandai untuk diperiksa kantor',
        isi: kalimat,
      ),
    ];
  }

  String _kalimatPenanda(String k) => switch (k) {
        'DI_LUAR_RADIUS' => '• Lokasi absen di luar radius proyek',
        'LOKASI_PROYEK_KOSONG' => '• Lokasi proyek belum diisi kantor',
        'TANPA_LOKASI' => '• Absen tanpa lokasi GPS',
        'GPS_PALSU' => '• HP melaporkan lokasi palsu',
        'JAM_HP_SELISIH' => '• Jam HP berbeda jauh dari jam server',
        'JAM_TAK_TERVERIFIKASI' => '• Jam HP tidak dapat diverifikasi (HP dinyalakan ulang)',
        'JAM_DIEDIT' => '• Jam diubah manual',
        'JUMLAH_WAJAH_BEDA' => '• Jumlah wajah di foto berbeda dengan jumlah kru',
        'FOTO_BELUM_MASUK' => '• Foto masih menunggu terkirim',
        _ => '• $k',
      };

  Widget _barisKru(Pekerja k) {
    final w = context.warna;
    final b = _baris[k.uuid];
    final dipilih = b != null;
    return KartuDaftar(
      onTap: _terkunci
          ? null
          : () => setState(() {
                _berubah = true;
                if (dipilih) {
                  _baris.remove(k.uuid);
                } else {
                  _baris[k.uuid] = _Baris(uuid: uuidBaru());
                }
              }),
      child: Column(
        children: [
          Row(
            children: [
              Icon(dipilih ? Icons.check_box : Icons.check_box_outline_blank, color: dipilih ? w.brand : w.muted),
              const SizedBox(width: 12),
              Expanded(child: Text(k.nama, style: TextStyle(fontWeight: FontWeight.w600, color: w.ink))),
              if (k.lokal) Lencana.statusKirim(context, 'lokal'),
            ],
          ),
          if (dipilih) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'hadir', label: Text('Penuh')),
                    ButtonSegment(value: 'setengah', label: Text('½ hari')),
                  ],
                  selected: {b.status},
                  showSelectedIcon: false,
                  onSelectionChanged: _terkunci
                      ? null
                      : (s) => setState(() {
                            _berubah = true;
                            b.status = s.first;
                          }),
                ),
                const Spacer(),
                Text('Lembur', style: TextStyle(color: w.muted, fontSize: 13)),
                IconButton(
                  onPressed: _terkunci || b.lembur <= 0
                      ? null
                      : () => setState(() {
                            _berubah = true;
                            b.lembur = (b.lembur - 0.5).clamp(0, 24);
                          }),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('${b.lembur.toStringAsFixed(1).replaceAll('.', ',')} j',
                    style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
                IconButton(
                  onPressed: _terkunci || b.lembur >= 24
                      ? null
                      : () => setState(() {
                            _berubah = true;
                            b.lembur = (b.lembur + 0.5).clamp(0, 24);
                          }),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

final _dokumenHidupProvider = StreamProvider.autoDispose.family<BarisDokumen?, String>(
  (ref, uuid) => ref.watch(dbProvider).pantauSatuDokumen(uuid),
);

class _KartuKejadian extends StatelessWidget {
  const _KartuKejadian({
    required this.judul,
    required this.kejadian,
    required this.proyek,
    required this.sibuk,
    required this.aktif,
    required this.onAmbil,
  });

  final String judul;
  final Map<String, Object?>? kejadian;
  final Map<String, Object?>? proyek;
  final bool sibuk;
  final bool aktif;
  final VoidCallback onAmbil;

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    final k = kejadian;
    if (k == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: SizedBox(
          height: 64,
          child: OutlinedButton.icon(
            onPressed: aktif && !sibuk ? onAmbil : null,
            icon: sibuk
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.photo_camera_outlined),
            label: Text('Foto kru · $judul', style: const TextStyle(fontSize: 16)),
          ),
        ),
      );
    }

    final saat = DateTime.tryParse('${k['at']}');
    final lat = keDouble(k['lat']);
    final lng = keDouble(k['lng']);
    final pLat = keDouble(proyek?['latitude']);
    final pLng = keDouble(proyek?['longitude']);
    final radius = keDouble(proyek?['geofenceRadiusM']) ?? 200;
    final jarak = lat != null && lng != null && pLat != null && pLng != null ? jarakMeter(lat, lng, pLat, pLng) : null;
    final wajah = keInt(k['faceCount']);

    return KartuDaftar(
      onLongPress: aktif ? onAmbil : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Miniatur(uuid: '${k['photoUuid']}'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(judul, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
                Text(saat == null ? '–' : 'Pukul ${jam(saat)}', style: TextStyle(color: w.ink)),
                const SizedBox(height: 4),
                if (jarak != null)
                  Text(
                    jarak <= radius ? '${jarak.round()} m dari proyek ✓' : '${jarak.round()} m dari proyek — di luar radius ${radius.round()} m',
                    style: TextStyle(color: jarak <= radius ? w.okFg : w.warnFg, fontSize: 13, fontWeight: FontWeight.w600),
                  )
                else if (lat == null)
                  Text('Tanpa lokasi', style: TextStyle(color: w.warnFg, fontSize: 13)),
                if (k['isMocked'] == true) Text('Lokasi palsu terdeteksi', style: TextStyle(color: w.badFg, fontSize: 13)),
                if (wajah != null) Text('$wajah wajah di foto', style: TextStyle(color: w.muted, fontSize: 13)),
                if (aktif) Text('Tekan lama untuk foto ulang', style: TextStyle(color: w.faint, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Miniatur extends ConsumerWidget {
  const _Miniatur({required this.uuid});

  final String uuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.warna;
    final foto = ref.watch(_fotoProvider(uuid)).value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 72,
        height: 72,
        color: w.surface2,
        child: foto != null && File(foto.path).existsSync()
            ? Image.file(File(foto.path), fit: BoxFit.cover, cacheWidth: 200)
            : Icon(Icons.image_outlined, color: w.muted),
      ),
    );
  }
}

final _fotoProvider = FutureProvider.autoDispose.family<BarisFoto?, String>((ref, uuid) => ref.watch(dbProvider).satuFoto(uuid));
