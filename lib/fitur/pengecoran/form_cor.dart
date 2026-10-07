import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../inti/db/database.dart';
import '../../inti/penyedia.dart';
import '../../inti/perangkat/kamera.dart';
import '../../inti/perangkat/notifikasi.dart';
import '../../inti/tema/token_warna.dart';
import '../../inti/tema/ukuran.dart';
import '../../inti/util/alasan.dart';
import '../../inti/util/format.dart';
import '../../inti/widget/banner_terra.dart';
import '../../inti/widget/kartu_daftar.dart';
import '../../inti/widget/keadaan.dart';
import '../../inti/widget/lencana.dart';
import '../absensi/status_tinjau.dart';
import 'hitung/keadaan_cor.dart';
import 'hitung/rencana_potong.dart';
import 'hitung/volume.dart';

/// Log cor satu titik bor.
///
/// ISI DOKUMEN = PERSIS `DataCor` DI SERVER
///
///   pilePointUuid, date, concreteGrade, supplierID, supplierName,
///   tremieBottomGapM, status, note, tremie[...], trucks[...]
///
/// URUTAN KERJA DI LAPANGAN — dan urutan layar ini
///
///   1. Susun tremie (segmen bawah → atas).
///   2. TM datang: isi no. truk, tiket, volume, slump, foto tiket.
///      Aplikasi menghitung RENCANA potong untuk TM itu.
///   3. Mulai cor TM → stopwatch (juga di notifikasi).
///   4. Cabut segmen di tengah TM bila rencana memintanya: centang.
///   5. Selesai TM → sounding muka beton → saran potong → centang.
///   6. Ulangi 2–5. Terakhir: Selesai cor.
///
/// Setiap langkah langsung disimpan (dan masuk antrean kirim).
class FormCor extends ConsumerStatefulWidget {
  const FormCor({super.key, required this.uuid, this.titikUuid});

  final String uuid;

  /// Diisi saat log cor BARU dibuat dari daftar titik.
  final String? titikUuid;

  @override
  ConsumerState<FormCor> createState() => _FormCorState();
}

class _FormCorState extends ConsumerState<FormCor> {
  Map<String, Object?>? _dok;
  Map<String, Object?>? _titik;
  Map<String, Object?>? _proyek;
  double? _borLokal;
  BarisDokumen? _baris;
  bool _baru = false;
  String? _galat;
  Timer? _detak;

  @override
  void initState() {
    super.initState();
    _baca();
    _detak = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _tmBerjalan != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _detak?.cancel();
    super.dispose();
  }

  Future<void> _baca() async {
    final db = ref.read(dbProvider);
    final baris = await db.satuDokumen(widget.uuid);
    Map<String, Object?>? dok;
    String? titikUuid = widget.titikUuid;
    if (baris != null) {
      dok = (jsonDecode(baris.isi) as Map).cast<String, Object?>();
      titikUuid = '${dok['pilePointUuid']}';
    }
    if (titikUuid == null) {
      setState(() => _galat = 'Log cor tidak ditemukan di HP ini.');
      return;
    }
    final titik = await db.satuInduk('titik', titikUuid);
    if (titik == null) {
      setState(() => _galat = 'Titik bor tidak ada di HP ini. Tarik data terbaru saat ada sinyal.');
      return;
    }
    final proyek = await db.satuInduk('proyek', '${titik['projectID']}');

    // Tanda bor di HP yang belum tentu sudah sampai server.
    final p = ref.read(penggunaProvider);
    double? borLokal;
    if (p != null) {
      final tanda = await db.pantauDokumen('drill_mark', p.id).first;
      for (final d in tanda) {
        final isi = (jsonDecode(d.isi) as Map).cast<String, Object?>();
        if ('${isi['pilePointUuid']}' == titikUuid && d.statusKirim != 'ditolak') {
          borLokal = keDouble(isi['drilledDepthM']);
          break;
        }
      }
    }

    if (dok == null) {
      _baru = true;
      dok = {
        'pilePointUuid': titikUuid,
        'date': tanggalIso(DateTime.now()),
        'concreteGrade': null,
        'supplierID': null,
        'supplierName': null,
        'tremieBottomGapM': '0.30',
        'status': 'berjalan',
        'note': null,
        'tremie': <Object?>[],
        'trucks': <Object?>[],
      };
    }
    if (!mounted) return;
    setState(() {
      _dok = dok;
      _baris = baris;
      _titik = titik;
      _proyek = proyek;
      _borLokal = borLokal;
    });
  }

  // -------------------------------------------------------------------------
  // Turunan
  // -------------------------------------------------------------------------

  GeometriTitik get _geometri => GeometriTitik(
        diameterMm: keInt(_titik!['diameterMm']) ?? 0,
        groundLevel: keDouble(_titik!['groundLevel']) ?? 0,
        cutOffLevel: keDouble(_titik!['cutOffLevel']) ?? 0,
        tipLevel: keDouble(_titik!['tipLevel']) ?? 0,
        drilledDepthM: _borLokal ?? keDouble(_titik!['drilledDepthM']),
      );

  KeadaanCor get _keadaan => KeadaanCor.dari(_geometri, _dok!);

  List<Map<String, Object?>> get _tremie => [for (final s in (_dok!['tremie'] as List)) (s as Map).cast<String, Object?>()];
  List<Map<String, Object?>> get _tm => [for (final t in (_dok!['trucks'] as List)) (t as Map).cast<String, Object?>()];

  Map<String, Object?>? get _tmTerakhir {
    final d = _tm;
    if (d.isEmpty) return null;
    d.sort((a, b) => (keInt(a['seq']) ?? 0).compareTo(keInt(b['seq']) ?? 0));
    return d.last;
  }

  Map<String, Object?>? get _tmBerjalan {
    final t = _dok == null ? null : _tmTerakhir;
    return t != null && t['startAt'] != null && t['endAt'] == null ? t : null;
  }

  /// Mutu efektif: isian log cor → titik → proyek.
  double? get _mutu =>
      keDouble(_dok!['concreteGrade']) ?? keDouble(_titik!['concreteGrade']) ?? keDouble(_proyek?['defaultConcreteGrade']);

  bool get _terkunci => _baris?.statusServer == 'diperiksa';
  bool get _selesai => _dok!['status'] == 'selesai';

  // -------------------------------------------------------------------------
  // Simpan
  // -------------------------------------------------------------------------

  Future<void> _ubah(void Function(Map<String, Object?> d) f) async {
    if (_terkunci) return;
    final p = ref.read(penggunaProvider);
    if (p == null) return;
    setState(() => f(_dok!));
    final db = ref.read(dbProvider);
    await db.simpanDokumen(uuid: widget.uuid, entitas: 'casting', userId: p.id, isi: _dok!);
    _baris = await db.satuDokumen(widget.uuid);
    _baru = false;
    ref.read(sinkronProvider.notifier).setelahSimpan();
    if (mounted) setState(() {});
  }

  // -------------------------------------------------------------------------
  // Tremie
  // -------------------------------------------------------------------------

  Future<void> _tambahSegmen(double panjang) => _ubah((d) {
        final s = _tremie;
        final posisi = s.isEmpty ? 1 : s.map((x) => keInt(x['position']) ?? 0).reduce((a, b) => a > b ? a : b) + 1;
        (d['tremie'] as List).add({
          'uuid': uuidBaru(),
          'position': posisi,
          'lengthM': angkaTeks(panjang),
          'removedAfterTruckSeq': null,
          'removedAt': null,
        });
      });

  Future<void> _hapusSegmenAtas() => _ubah((d) {
        final s = _tremie..sort((a, b) => (keInt(a['position']) ?? 0).compareTo(keInt(b['position']) ?? 0));
        if (s.isEmpty) return;
        final atas = s.last;
        (d['tremie'] as List).removeWhere((x) => (x as Map)['uuid'] == atas['uuid']);
      });

  Future<void> _segmenLain() async {
    final v = (await _mintaAngka(judul: 'Panjang segmen', label: 'Panjang (m)', akhiran: 'm', maks: 12))?.$1;
    if (v != null) await _tambahSegmen(v);
  }

  /// Centang / lepas segmen dicabut setelah TM [seq].
  Future<void> _cabut(String uuidSegmen, int? seq) => _ubah((d) {
        for (final x in (d['tremie'] as List)) {
          final m = x as Map;
          if (m['uuid'] == uuidSegmen) {
            m['removedAfterTruckSeq'] = seq;
            m['removedAt'] = seq == null ? null : isoBerzona(DateTime.now());
          }
        }
      });

  // -------------------------------------------------------------------------
  // TM
  // -------------------------------------------------------------------------

  Future<void> _tmBaru() async {
    final k = _keadaan;
    final seq = k.seqTerakhir + 1;
    final hasil = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _LembarTm(
        seq: seq,
        betonSebelumPerkiraan: k.betonSetelah(seq - 1).kedalamanM,
        ambilFotoTiket: _fotoTiket,
      ),
    );
    if (hasil == null) return;
    await _ubah((d) {
      (d['trucks'] as List).add({
        'uuid': uuidBaru(),
        'seq': seq,
        'truckNo': hasil['truckNo'],
        'ticketNo': hasil['ticketNo'],
        'arrivedAt': isoBerzona(DateTime.now()),
        'slumpCm': hasil['slumpCm'],
        'volumeM3': hasil['volumeM3'],
        'startAt': null,
        'startEdited': false,
        'endAt': null,
        'endEdited': false,
        // Panjang tremie terpasang saat TM ini mulai — diturunkan dari
        // segmen, bukan diketik ulang.
        'tremieLengthM': angkaTeks(k.panjangTerpasangSetelah(seq - 1)),
        'concreteDepthBeforeM': hasil['concreteDepthBeforeM'],
        'concreteDepthAfterM': null,
        'ticketPhotoUuid': hasil['ticketPhotoUuid'],
        'note': null,
      });
    });
  }

  Future<String?> _fotoTiket() async {
    final p = ref.read(penggunaProvider);
    if (p == null) return null;
    final f = await ambilFoto(db: ref.read(dbProvider), userId: p.id, jenis: 'tiket_tm');
    return f?.uuid;
  }

  Future<void> _ubahTm(String uuidTm, void Function(Map<Object?, Object?> t) f) => _ubah((d) {
        for (final x in (d['trucks'] as List)) {
          final m = x as Map;
          if (m['uuid'] == uuidTm) f(m);
        }
      });

  Future<void> _mulaiTm(Map<String, Object?> tm) async {
    final mulai = DateTime.now();
    await _ubahTm('${tm['uuid']}', (t) => t['startAt'] = isoBerzona(mulai));
    await Notifikasi.mintaIzin();
    await Notifikasi.tampilkanStopwatch(
      rute: '/pengecoran/cor/${widget.uuid}',
      judul: 'TM #${tm['seq']} dicor · ${_titik!['code']}',
      isi: '${_desimal(tm['volumeM3'])} m³ · ketuk untuk membuka log cor',
      mulai: mulai,
    );
  }

  Future<void> _selesaiTm(Map<String, Object?> tm) async {
    await _ubahTm('${tm['uuid']}', (t) => t['endAt'] = isoBerzona(DateTime.now()));
    await Notifikasi.hapusStopwatch();
    if (!mounted) return;
    final k = _keadaan;
    final seq = keInt(tm['seq']) ?? 0;
    final v = await _mintaAngka(
      judul: 'Sounding setelah TM #$seq',
      label: 'Kedalaman muka beton dari GS (m)',
      akhiran: 'm',
      maks: 200,
      penjelas: 'Perkiraan dari volume: ${meter(k.betonSetelah(seq).kedalamanM)}. Kosongkan bila tidak diukur.',
      bolehKosong: true,
    );
    final nilai = v?.$1;
    if (nilai != null) await _ubahTm('${tm['uuid']}', (t) => t['concreteDepthAfterM'] = angkaTeks(nilai));
  }

  Future<void> _ubahJam(Map<String, Object?> tm, {required bool mulai}) async {
    final kunci = mulai ? 'startAt' : 'endAt';
    final awal = DateTime.tryParse('${tm[kunci]}')?.toLocal() ?? DateTime.now();
    final pilih = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(awal));
    if (pilih == null) return;
    final baru = DateTime(awal.year, awal.month, awal.day, pilih.hour, pilih.minute);
    await _ubahTm('${tm['uuid']}', (t) {
      t[kunci] = isoBerzona(baru);
      t[mulai ? 'startEdited' : 'endEdited'] = true;
    });
  }

  Future<void> _soundingUlang(Map<String, Object?> tm, {required bool sesudah}) async {
    final kunci = sesudah ? 'concreteDepthAfterM' : 'concreteDepthBeforeM';
    final v = await _mintaAngka(
      judul: sesudah ? 'Sounding setelah TM #${tm['seq']}' : 'Sounding sebelum TM #${tm['seq']}',
      label: 'Kedalaman muka beton dari GS (m)',
      akhiran: 'm',
      maks: 200,
      awal: keDouble(tm[kunci]),
      bolehKosong: true,
    );
    if (v == null) return; // dibatalkan
    final nilai = v.$1;
    await _ubahTm('${tm['uuid']}', (t) => t[kunci] = nilai == null ? null : angkaTeks(nilai));
  }

  Future<void> _ubahHeader() async {
    final hasil = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _LembarHeader(
        mutu: keDouble(_dok!['concreteGrade']),
        mutuBawaan: keDouble(_titik!['concreteGrade']) ?? keDouble(_proyek?['defaultConcreteGrade']),
        pemasok: _dok!['supplierName']?.toString(),
        celah: keDouble(_dok!['tremieBottomGapM']) ?? 0.30,
        catatan: _dok!['note']?.toString(),
      ),
    );
    if (hasil == null) return;
    await _ubah((d) => d.addAll(hasil));
  }

  Future<void> _selesaiCor() async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Selesai cor titik ini?'),
        content: const Text('Titik ditandai sudah dicor. Log cor masih dapat diperbaiki sampai diperiksa kantor.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Belum')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Selesai')),
        ],
      ),
    );
    if (ya != true) return;
    await Notifikasi.hapusStopwatch();
    await _ubah((d) => d['status'] = 'selesai');
  }

  /// Null = dibatalkan. `(null,)` = dikosongkan (bila [bolehKosong]).
  Future<(double?,)?> _mintaAngka({
    required String judul,
    required String label,
    String? akhiran,
    required double maks,
    double? awal,
    String? penjelas,
    bool bolehKosong = false,
  }) async {
    final isian = TextEditingController(text: awal == null ? '' : awal.toStringAsFixed(2).replaceAll('.', ','));
    final hasil = await showDialog<(double?,)>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(judul),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (penjelas != null) ...[Text(penjelas), const SizedBox(height: 12)],
            TextField(
              controller: isian,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: label, suffixText: akhiran),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              final t = isian.text.trim();
              if (t.isEmpty && bolehKosong) return Navigator.pop(c, (null,));
              final v = bacaAngka(t);
              if (v == null || v <= 0 || v > maks) return;
              Navigator.pop(c, (v,));
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    isian.dispose();
    return hasil;
  }

  // -------------------------------------------------------------------------
  // Tampilan
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_galat != null) {
      return Scaffold(appBar: AppBar(title: const Text('Log cor')), body: KeadaanGagal(judul: _galat!));
    }
    if (_dok == null) return const Scaffold(body: KeadaanMuat());

    final hidup = ref.watch(_dokHidupProvider(widget.uuid)).value;
    if (hidup != null) _baris = hidup;

    final w = context.warna;
    final k = _keadaan;
    final g = _geometri;
    final tmTerakhir = _tmTerakhir;
    final berjalan = _tmBerjalan;
    final seq = k.seqTerakhir;

    return Scaffold(
      appBar: AppBar(
        title: Text('Cor ${_titik!['code']}'),
        actions: [
          if (_baris != null) Padding(padding: const EdgeInsets.only(right: 12), child: Lencana.statusKirim(context, _baris!.statusKirim)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Ukuran.tepi, Ukuran.tepi, Ukuran.tepi, 120),
        children: [
          if (_baris?.statusKirim == 'ditolak')
            BannerTerra(jenis: JenisBanner.bahaya, judul: 'Ditolak server', isi: kalimatAlasan(_baris!.alasan, _baris!.detail)),
          if (_terkunci)
            BannerTerra(
              jenis: JenisBanner.ok,
              judul: 'Sudah diperiksa kantor',
              isi: [if (_baris!.catatanServer != null) 'Catatan: ${_baris!.catatanServer}', 'Log cor ini tidak dapat diubah lagi.'].join('\n'),
            ),
          if (_mutu == null)
            BannerTerra(
              jenis: JenisBanner.awas,
              judul: "Mutu beton (fc') belum diisi",
              isi: 'Titik dan proyek ini belum punya mutu bawaan. Isi di data cor, atau log cor akan ditolak server.',
              aksi: TextButton(onPressed: _ubahHeader, child: const Text('Isi')),
            ),
          if (g.drilledDepthM == null)
            const BannerTerra(
              jenis: JenisBanner.info,
              judul: 'Kedalaman bor belum ditandai',
              isi: 'Hitungan memakai panjang bor RENCANA. Tandai kedalaman aktual dari daftar titik supaya saran potong tepat.',
            ),

          _KartuRingkas(geometri: g, keadaan: k, mutu: _mutu, pemasok: _dok!['supplierName']?.toString(), onUbah: _terkunci ? null : _ubahHeader),
          if (_baris?.statusServer != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: LencanaTinjau(status: _baris!.statusServer!)),

          // --- tremie -----------------------------------------------------
          _Judul('Tremie', 'Segmen bawah → atas. Ujung bawah ${meter(k.celahBawahM)} di atas dasar lubang.'),
          _KartuTremie(
            keadaan: k,
            seqKini: seq,
            bolehUbahSusunan: !_terkunci && _tm.isEmpty,
            bolehCabut: !_terkunci && seq > 0,
            onTambah: _tambahSegmen,
            onLain: _segmenLain,
            onHapusAtas: _hapusSegmenAtas,
            onCabut: _cabut,
          ),

          // --- rekomendasi --------------------------------------------------
          if (seq > 0 && !_selesai) _kartuSaran(k, seq),

          // --- TM ---------------------------------------------------------
          _Judul('Truk mixer (TM)', '${_tm.length} TM · ${_desimal(k.volumeTotalM3)} m³'),
          for (final tm in _tm..sort((a, b) => (keInt(a['seq']) ?? 0).compareTo(keInt(b['seq']) ?? 0)))
            _KartuTm(
              tm: tm,
              keadaan: k,
              terkunci: _terkunci,
              onMulai: () => _mulaiTm(tm),
              onSelesai: () => _selesaiTm(tm),
              onJamMulai: () => _ubahJam(tm, mulai: true),
              onJamSelesai: () => _ubahJam(tm, mulai: false),
              onSoundingSebelum: () => _soundingUlang(tm, sesudah: false),
              onSoundingSesudah: () => _soundingUlang(tm, sesudah: true),
            ),
          if (_tm.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Belum ada TM.', style: TextStyle(color: w.muted))),
        ],
      ),
      bottomNavigationBar: _terkunci
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Ukuran.tepi, 8, Ukuran.tepi, 12),
                child: Row(
                  children: [
                    if (!_selesai && berjalan == null && _tm.isNotEmpty)
                      Expanded(
                        child: OutlinedButton(onPressed: _selesaiCor, child: const Text('Selesai cor')),
                      ),
                    if (!_selesai && berjalan == null && _tm.isNotEmpty) const SizedBox(width: 10),
                    if (!_selesai)
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: Ukuran.sentuhMinimum + 4,
                          child: berjalan != null
                              ? FilledButton.icon(
                                  onPressed: () => _selesaiTm(berjalan),
                                  icon: const Icon(Icons.stop_circle_outlined),
                                  label: Text('Selesai TM #${berjalan['seq']}'),
                                )
                              : tmTerakhir != null && tmTerakhir['startAt'] == null
                                  ? FilledButton.icon(
                                      onPressed: () => _mulaiTm(tmTerakhir),
                                      icon: const Icon(Icons.play_arrow),
                                      label: Text('Mulai cor TM #${tmTerakhir['seq']}'),
                                    )
                                  : FilledButton.icon(
                                      onPressed: _tremie.isEmpty ? null : _tmBaru,
                                      icon: const Icon(Icons.local_shipping_outlined),
                                      label: Text(_tremie.isEmpty ? 'Susun tremie dulu' : 'TM #${seq + 1} datang'),
                                    ),
                        ),
                      ),
                    if (_selesai)
                      Expanded(
                        child: BannerTerra(
                          jenis: JenisBanner.ok,
                          judul: 'Cor selesai',
                          isi: _baru ? null : 'Tersimpan. Dikirim otomatis.',
                          aksi: TextButton(onPressed: () => _ubah((d) => d['status'] = 'berjalan'), child: const Text('Buka lagi')),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  /// Rencana / saran potong untuk TM terakhir.
  Widget _kartuSaran(KeadaanCor k, int seq) {
    final tm = _tmTerakhir!;
    const batas = BatasTertanam();
    final segmenTerpasang = [
      for (final s in k.terpasangSetelah(seq)) Segmen(kunci: s.uuid, panjangM: s.panjangM),
    ];

    if (tm['endAt'] == null) {
      // TM belum selesai: rencana dihitung dari keadaan SEBELUM TM ini.
      final sebelum = k.betonSetelah(seq - 1).kedalamanM;
      final r = rencanakanTm(
        diameterMm: k.geometri.diameterMm,
        ujungBawahM: k.ujungBawahSetelah(seq - 1),
        segmen: [for (final s in k.terpasangSetelah(seq - 1)) Segmen(kunci: s.uuid, panjangM: s.panjangM)],
        kedalamanBetonM: keDouble(tm['concreteDepthBeforeM']) ?? sebelum,
        kedalamanCutOffM: k.geometri.kedalamanCutOffM,
        volumeM3: keDouble(tm['volumeM3']) ?? 0,
        rasio: k.rasioRataRata,
        batas: batas,
      );
      final posisi = {for (final s in k.segmen) s.uuid: s.posisi};
      return BannerTerra(
        jenis: r.peringatan.isEmpty ? JenisBanner.info : JenisBanner.awas,
        ikon: Icons.tips_and_updates_outlined,
        judul: r.potong.isEmpty ? 'Rencana TM #$seq: tidak perlu cabut' : 'Rencana TM #$seq',
        isi: [
          for (final p in r.potong)
            '• Setelah ±${_desimal(p.setelahM3)} m³: cabut ${p.cabut.map((s) => '#${posisi[s.kunci]} (${_desimal(s.panjangM)} m)').join(' lalu ')} '
                '→ tertanam ${_desimal(p.tertanamSebelumM)} → ${_desimal(p.tertanamSesudahM)} m',
          for (final p in r.peringatan)
            p.jenis == JenisPeringatan.tertanamKurang
                ? '⚠ Tertanam sebelum TM ini hanya ${_desimal(p.tertanamM)} m — periksa sounding.'
                : '⚠ Setelah ±${_desimal(p.setelahM3)} m³ tertanam melewati 6 m dan tidak ada segmen yang aman dicabut.',
          'Perkiraan akhir TM: muka beton ${meter(r.kedalamanBetonAkhirM)}, tertanam ${meter(r.tertanamAkhirM)}'
              '${r.cutOffTercapai ? ' — cut-off tercapai' : ''}.',
          if (k.rasioRataRata != 1.0) 'Memakai rasio overbreak ${_desimal(k.rasioRataRata)} dari sounding TM sebelumnya.',
        ].join('\n'),
      );
    }

    // TM selesai: saran dari tertanam sekarang.
    final beton = k.betonSetelah(seq);
    final tertanam = k.tertanamSetelah(seq);
    final saran = pilihCabut(segmenTerpasang, tertanam, batas);
    final posisi = {for (final s in k.segmen) s.uuid: s.posisi};
    final jenis = tertanam < batas.minimumM
        ? JenisBanner.bahaya
        : tertanam > batas.maksimumM
            ? JenisBanner.awas
            : JenisBanner.info;
    return BannerTerra(
      jenis: jenis,
      ikon: Icons.tips_and_updates_outlined,
      judul: 'Tertanam ${meter(tertanam)}${beton.terukur ? '' : ' (perkiraan)'}',
      isi: [
        if (!beton.terukur) 'Muka beton belum disounding — angka ini dari volume. Sounding dulu sebelum mencabut.',
        if (saran.isEmpty)
          tertanam < batas.minimumM
              ? 'Kurang dari 1 m: JANGAN cabut. Tremie berisiko keluar dari beton.'
              : 'Tidak perlu cabut sekarang.'
        else
          'Saran: cabut ${saran.map((s) => '#${posisi[s.kunci]} (${_desimal(s.panjangM)} m)').join(', ')} '
              '→ tertanam ${meter(tertanam - saran.fold(0.0, (a, s) => a + s.panjangM))}. Centang di daftar tremie setelah dicabut.',
      ].join('\n'),
      aksi: saran.isEmpty
          ? null
          : TextButton(
              onPressed: () async {
                for (final s in saran) {
                  await _cabut(s.kunci, seq);
                }
              },
              child: const Text('Centang'),
            ),
    );
  }
}

final _dokHidupProvider = StreamProvider.autoDispose.family<BarisDokumen?, String>(
  (ref, uuid) => ref.watch(dbProvider).pantauSatuDokumen(uuid),
);

String _desimal(Object? v, {int d = 2}) {
  final x = v is num ? v.toDouble() : keDouble(v);
  if (x == null) return '–';
  var t = x.toStringAsFixed(d);
  if (t.contains('.')) t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return t.replaceAll('.', ',');
}

class _Judul extends StatelessWidget {
  const _Judul(this.judul, this.isi);

  final String judul;
  final String isi;

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(judul, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: w.ink)),
          Text(isi, style: TextStyle(color: w.muted, fontSize: 13)),
        ],
      ),
    );
  }
}

class _KartuRingkas extends StatelessWidget {
  const _KartuRingkas({required this.geometri, required this.keadaan, required this.mutu, required this.pemasok, this.onUbah});

  final GeometriTitik geometri;
  final KeadaanCor keadaan;
  final double? mutu;
  final String? pemasok;
  final VoidCallback? onUbah;

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    final teori = geometri.volumeTeoritisAktualM3 ?? geometri.volumeTeoritisRencanaM3;
    final lebih = keadaan.lebihPakaiPersen;
    final seq = keadaan.seqTerakhir;
    final beton = keadaan.betonSetelah(seq);
    Widget sel(String label, String nilai, {Color? warna}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: w.muted, fontSize: 12)),
              Text(nilai, style: TextStyle(fontWeight: FontWeight.w700, color: warna ?? w.ink)),
            ],
          ),
        );
    return KartuDaftar(
      onTap: onUbah,
      child: Column(
        children: [
          Row(children: [
            sel('Diameter', 'D${geometri.diameterMm}'),
            sel("Mutu fc'", mutu == null ? '–' : '${_desimal(mutu, d: 1)} MPa', warna: mutu == null ? w.warnFg : null),
            sel('Pemasok', pemasok ?? '–'),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            sel('Dasar lubang', meter(geometri.kedalamanDasarM)),
            sel('Cut-off', meter(geometri.kedalamanCutOffM)),
            sel('Muka beton', '${meter(beton.kedalamanM)}${beton.terukur || seq == 0 ? '' : '*'}'),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            sel('Teoritis', '${_desimal(teori)} m³'),
            sel('Terpakai', '${_desimal(keadaan.volumeTotalM3)} m³'),
            sel('Lebih pakai', lebih == null ? '–' : '${lebih >= 0 ? '+' : ''}${_desimal(lebih, d: 1)}%'),
          ]),
          if (seq > 0 && !beton.terukur) ...[
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: Text('* perkiraan dari volume', style: TextStyle(color: w.faint, fontSize: 12))),
          ],
        ],
      ),
    );
  }
}

class _KartuTremie extends StatelessWidget {
  const _KartuTremie({
    required this.keadaan,
    required this.seqKini,
    required this.bolehUbahSusunan,
    required this.bolehCabut,
    required this.onTambah,
    required this.onLain,
    required this.onHapusAtas,
    required this.onCabut,
  });

  final KeadaanCor keadaan;
  final int seqKini;
  final bool bolehUbahSusunan;
  final bool bolehCabut;
  final Future<void> Function(double) onTambah;
  final VoidCallback onLain;
  final VoidCallback onHapusAtas;
  final Future<void> Function(String uuid, int? seq) onCabut;

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    final k = keadaan;
    final total = k.segmen.fold(0.0, (a, s) => a + s.panjangM);
    final perluMinimal = k.geometri.kedalamanDasarM - k.celahBawahM;
    final terpasang = k.terpasangSetelah(seqKini);
    final bawah = terpasang.isEmpty ? null : terpasang.first.uuid;

    return KartuDaftar(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Ditampilkan ATAS di atas — seperti tremie berdiri di lubang.
          for (final s in k.segmen.reversed)
            Builder(builder: (context) {
              final dicabut = s.dicabutSetelahTm != null;
              final bisaCentang = bolehCabut && s.uuid != bawah && (!dicabut || s.dicabutSetelahTm == seqKini);
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: dicabut,
                onChanged: bisaCentang ? (v) => onCabut(s.uuid, v == true ? seqKini : null) : null,
                title: Text(
                  '#${s.posisi} · ${_desimal(s.panjangM)} m${s.uuid == bawah ? ' (paling bawah)' : ''}',
                  style: TextStyle(
                    decoration: dicabut ? TextDecoration.lineThrough : null,
                    color: dicabut ? w.muted : w.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: dicabut ? Text('Dicabut setelah TM #${s.dicabutSetelahTm}') : null,
              );
            }),
          if (k.segmen.isEmpty) Text('Belum ada segmen. Tambahkan dari yang paling bawah.', style: TextStyle(color: w.muted)),
          const Divider(),
          Text('Terpasang ${_desimal(k.panjangTerpasangSetelah(seqKini))} m dari ${_desimal(total)} m · '
              'ujung bawah di ${meter(k.ujungBawahSetelah(seqKini))}',
              style: TextStyle(color: w.muted, fontSize: 13)),
          if (bolehUbahSusunan && k.segmen.isNotEmpty && total < perluMinimal)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Total ${_desimal(total)} m belum sampai ${meter(perluMinimal)} (dasar − celah). Tambah segmen.',
                  style: TextStyle(color: w.warnFg, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          if (bolehUbahSusunan) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in const [1.0, 1.5, 2.0, 3.0])
                  ActionChip(avatar: const Icon(Icons.add, size: 16), label: Text('${_desimal(p)} m'), onPressed: () => onTambah(p)),
                ActionChip(label: const Text('Lainnya'), onPressed: onLain),
                if (k.segmen.isNotEmpty) ActionChip(avatar: const Icon(Icons.remove, size: 16), label: const Text('Hapus teratas'), onPressed: onHapusAtas),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _KartuTm extends StatelessWidget {
  const _KartuTm({
    required this.tm,
    required this.keadaan,
    required this.terkunci,
    required this.onMulai,
    required this.onSelesai,
    required this.onJamMulai,
    required this.onJamSelesai,
    required this.onSoundingSebelum,
    required this.onSoundingSesudah,
  });

  final Map<String, Object?> tm;
  final KeadaanCor keadaan;
  final bool terkunci;
  final VoidCallback onMulai;
  final VoidCallback onSelesai;
  final VoidCallback onJamMulai;
  final VoidCallback onJamSelesai;
  final VoidCallback onSoundingSebelum;
  final VoidCallback onSoundingSesudah;

  @override
  Widget build(BuildContext context) {
    final w = context.warna;
    final mulai = DateTime.tryParse('${tm['startAt']}');
    final selesai = DateTime.tryParse('${tm['endAt']}');
    final berjalan = mulai != null && selesai == null;
    final lama = mulai == null ? null : (selesai ?? DateTime.now()).difference(mulai);
    final seq = keInt(tm['seq']) ?? 0;
    final rasio = rasioOverbreak(
      diameterMm: keadaan.geometri.diameterMm,
      volumeM3: keDouble(tm['volumeM3']) ?? 0,
      kedalamanSebelumM: keDouble(tm['concreteDepthBeforeM']) ?? keadaan.betonSetelah(seq - 1).kedalamanM,
      kedalamanSesudahM: keDouble(tm['concreteDepthAfterM']),
    );

    Widget nilai(String label, String isi, {VoidCallback? onTap, bool diedit = false}) => InkWell(
          onTap: terkunci ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(label, style: TextStyle(color: w.muted, fontSize: 13))),
                Text(isi, style: TextStyle(fontWeight: FontWeight.w600, color: w.ink)),
                if (diedit) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.edit, size: 13, color: w.warnFg)),
                if (onTap != null && !terkunci) Icon(Icons.chevron_right, size: 16, color: w.faint),
              ],
            ),
          ),
        );

    return KartuDaftar(
      warnaTepi: berjalan ? w.warnFg : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('TM #$seq · ${_desimal(tm['volumeM3'])} m³',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: w.ink)),
              ),
              if (lama != null)
                Text(durasi(lama),
                    style: TextStyle(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w800,
                      color: berjalan ? w.warnFg : w.muted,
                    )),
            ],
          ),
          Text(
            [
              if (tm['truckNo'] != null) 'Truk ${tm['truckNo']}',
              if (tm['ticketNo'] != null) 'Tiket ${tm['ticketNo']}',
              if (tm['slumpCm'] != null) 'Slump ${_desimal(tm['slumpCm'], d: 1)} cm',
            ].join(' · '),
            style: TextStyle(color: w.muted, fontSize: 13),
          ),
          const SizedBox(height: 6),
          nilai('Tremie terpasang', '${_desimal(tm['tremieLengthM'])} m'),
          nilai('Mulai', mulai == null ? '–' : jam(mulai), onTap: mulai == null ? null : onJamMulai, diedit: tm['startEdited'] == true),
          nilai('Selesai', selesai == null ? '–' : jam(selesai), onTap: selesai == null ? null : onJamSelesai, diedit: tm['endEdited'] == true),
          nilai('Sounding sebelum', tm['concreteDepthBeforeM'] == null ? '–' : meter(keDouble(tm['concreteDepthBeforeM'])),
              onTap: onSoundingSebelum),
          nilai('Sounding sesudah', tm['concreteDepthAfterM'] == null ? '–' : meter(keDouble(tm['concreteDepthAfterM'])),
              onTap: selesai == null ? null : onSoundingSesudah),
          if (rasio != null) nilai('Rasio overbreak', _desimal(rasio)),
          if (tm['ticketPhotoUuid'] != null) _FotoTiket(uuid: '${tm['ticketPhotoUuid']}'),
        ],
      ),
    );
  }
}

class _FotoTiket extends ConsumerWidget {
  const _FotoTiket({required this.uuid});

  final String uuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foto = ref.watch(_fotoProvider(uuid)).value;
    if (foto == null || !File(foto.path).existsSync()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (c) => Dialog(child: InteractiveViewer(child: Image.file(File(foto.path)))),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(File(foto.path), height: 90, fit: BoxFit.cover, cacheHeight: 270),
        ),
      ),
    );
  }
}

final _fotoProvider = FutureProvider.autoDispose.family<BarisFoto?, String>((ref, uuid) => ref.watch(dbProvider).satuFoto(uuid));

/// Isian TM baru.
class _LembarTm extends StatefulWidget {
  const _LembarTm({required this.seq, required this.betonSebelumPerkiraan, required this.ambilFotoTiket});

  final int seq;
  final double betonSebelumPerkiraan;
  final Future<String?> Function() ambilFotoTiket;

  @override
  State<_LembarTm> createState() => _LembarTmState();
}

class _LembarTmState extends State<_LembarTm> {
  final _truk = TextEditingController();
  final _tiket = TextEditingController();
  final _volume = TextEditingController();
  final _slump = TextEditingController();
  final _sounding = TextEditingController();
  String? _foto;
  String? _galat;

  @override
  void dispose() {
    for (final c in [_truk, _tiket, _volume, _slump, _sounding]) {
      c.dispose();
    }
    super.dispose();
  }

  void _simpan() {
    final volume = bacaAngka(_volume.text);
    if (volume == null || volume <= 0 || volume > 15) {
      setState(() => _galat = 'Isi volume TM (m³), paling besar 15.');
      return;
    }
    final slump = _slump.text.trim().isEmpty ? null : bacaAngka(_slump.text);
    if (_slump.text.trim().isNotEmpty && (slump == null || slump < 0 || slump > 40)) {
      setState(() => _galat = 'Slump tidak masuk akal (0–40 cm).');
      return;
    }
    final sounding = _sounding.text.trim().isEmpty ? null : bacaAngka(_sounding.text);
    String? kosong(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    Navigator.pop(context, {
      'truckNo': kosong(_truk),
      'ticketNo': kosong(_tiket),
      'volumeM3': angkaTeks(volume),
      'slumpCm': slump == null ? null : angkaTeks(slump, desimal: 1),
      'concreteDepthBeforeM': sounding == null ? null : angkaTeks(sounding),
      'ticketPhotoUuid': _foto,
    });
  }

  @override
  Widget build(BuildContext context) {
    const angka = TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: EdgeInsets.fromLTRB(Ukuran.tepi, 0, Ukuran.tepi, MediaQuery.viewInsetsOf(context).bottom + Ukuran.tepi),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('TM #${widget.seq} datang', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (_galat != null) BannerTerra(jenis: JenisBanner.bahaya, judul: _galat!),
            OutlinedButton.icon(
              onPressed: () async {
                final f = await widget.ambilFotoTiket();
                if (f != null) setState(() => _foto = f);
              },
              icon: Icon(_foto == null ? Icons.receipt_long_outlined : Icons.check_circle),
              label: Text(_foto == null ? 'Foto tiket TM' : 'Foto tiket tersimpan · ulang'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _truk, decoration: const InputDecoration(labelText: 'No. truk'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _tiket, decoration: const InputDecoration(labelText: 'No. tiket'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _volume,
                  keyboardType: angka,
                  decoration: const InputDecoration(labelText: 'Volume', suffixText: 'm³'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _slump,
                  keyboardType: angka,
                  decoration: const InputDecoration(labelText: 'Slump', suffixText: 'cm'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _sounding,
              keyboardType: angka,
              decoration: InputDecoration(
                labelText: 'Sounding sebelum (opsional)',
                suffixText: 'm',
                hintText: 'perkiraan ${widget.betonSebelumPerkiraan.toStringAsFixed(2).replaceAll('.', ',')}',
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: Ukuran.sentuhMinimum + 4,
              child: FilledButton(onPressed: _simpan, child: const Text('Simpan TM')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Data cor: mutu, pemasok, celah bawah tremie, catatan.
class _LembarHeader extends StatefulWidget {
  const _LembarHeader({required this.mutu, required this.mutuBawaan, required this.pemasok, required this.celah, required this.catatan});

  final double? mutu;
  final double? mutuBawaan;
  final String? pemasok;
  final double celah;
  final String? catatan;

  @override
  State<_LembarHeader> createState() => _LembarHeaderState();
}

class _LembarHeaderState extends State<_LembarHeader> {
  late final _mutu = TextEditingController(text: widget.mutu == null ? '' : _desimal(widget.mutu, d: 1));
  late final _pemasok = TextEditingController(text: widget.pemasok ?? '');
  late final _celah = TextEditingController(text: _desimal(widget.celah));
  late final _catatan = TextEditingController(text: widget.catatan ?? '');
  String? _galat;

  @override
  void dispose() {
    for (final c in [_mutu, _pemasok, _celah, _catatan]) {
      c.dispose();
    }
    super.dispose();
  }

  void _simpan() {
    final mutu = _mutu.text.trim().isEmpty ? null : bacaAngka(_mutu.text);
    if (_mutu.text.trim().isNotEmpty && (mutu == null || mutu <= 0 || mutu > 150)) {
      setState(() => _galat = "Mutu fc' tidak masuk akal.");
      return;
    }
    final celah = bacaAngka(_celah.text);
    if (celah == null || celah < 0 || celah > 5) {
      setState(() => _galat = 'Celah bawah tremie 0–5 m.');
      return;
    }
    String? kosong(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    Navigator.pop(context, {
      'concreteGrade': mutu == null ? null : angkaTeks(mutu, desimal: 1),
      'supplierName': kosong(_pemasok),
      'tremieBottomGapM': angkaTeks(celah),
      'note': kosong(_catatan),
    });
  }

  @override
  Widget build(BuildContext context) {
    const angka = TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: EdgeInsets.fromLTRB(Ukuran.tepi, 0, Ukuran.tepi, MediaQuery.viewInsetsOf(context).bottom + Ukuran.tepi),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Data cor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (_galat != null) BannerTerra(jenis: JenisBanner.bahaya, judul: _galat!),
            if (widget.mutuBawaan != null)
              BannerTerra(
                jenis: JenisBanner.info,
                judul: "Mutu bawaan fc' ${_desimal(widget.mutuBawaan, d: 1)} MPa",
                isi: 'Dari titik/proyek. Isi hanya bila beton yang datang berbeda.',
              ),
            TextField(controller: _mutu, keyboardType: angka, decoration: const InputDecoration(labelText: "Mutu fc'", suffixText: 'MPa')),
            const SizedBox(height: 12),
            TextField(controller: _pemasok, decoration: const InputDecoration(labelText: 'Pemasok beton (batching plant)')),
            const SizedBox(height: 12),
            TextField(controller: _celah, keyboardType: angka, decoration: const InputDecoration(labelText: 'Celah ujung tremie di atas dasar', suffixText: 'm')),
            const SizedBox(height: 12),
            TextField(controller: _catatan, maxLines: 3, decoration: const InputDecoration(labelText: 'Catatan')),
            const SizedBox(height: 18),
            SizedBox(height: Ukuran.sentuhMinimum + 4, child: FilledButton(onPressed: _simpan, child: const Text('Simpan'))),
          ],
        ),
      ),
    );
  }
}
