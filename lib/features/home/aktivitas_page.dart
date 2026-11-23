import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';
import '../../core/util/format.dart';
import '../../core/widgets/quiet.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/network/api_error.dart';
import '../reports/daily_report_actions.dart';
import 'aktivitas_hari_ini.dart';

/// KEGIATAN LAPANGAN SATU HARI — hari mana pun, bukan hanya hari ini.
///
/// DIMINTA DANIEL, 20 Oktober 2026: "gw pengen ada halaman aktivitas deh di
/// app, jadi kelihatan. kalau hari ini kan kelihatan langsung di dashboard.
/// gw pengennya bisa lihat juga kemarin gimana, 2 hari lalu gimana dst".
///
/// Kartu beranda menjawab "sekarang bagaimana" dan dibatasi enam baris —
/// ia ringkasan, bukan laporan. Halaman ini menjawab "kemarin bagaimana",
/// menampilkan SELURUH barisnya, dan menambahkan satu hal yang tidak ada di
/// beranda: JUMLAH HARI ITU. Pertanyaan yang dibawa ke rapat bukan "titik
/// mana saja", melainkan "kemarin dapat berapa meter".
///
/// Barisnya memakai [BarisKegiatan] yang sama dengan beranda. Disusun
/// terpisah, dua layar yang menampilkan kejadian yang sama akan menua
/// sendiri-sendiri lalu menyebut jam atau satuan yang berbeda.
///
/// DIKELOMPOKKAN PER PROYEK (diminta Daniel, 20 Oktober 2026: "kayanya gw
/// minta dibagi per proyek deh. siapa tau suatu hari jalan beberapa proyek
/// sekaligus"). Hari ini hampir selalu satu proyek yang jalan, dan di hari
/// seperti itu kepalanya hanya menyebutkan proyeknya sekali — tidak ada
/// yang hilang. Yang ditolong adalah hari dengan dua rig di dua tempat:
/// satu daftar bercampur menuntut pembacanya mengingat titik mana milik
/// proyek mana, dan "kemarin dapat berapa meter" tidak terjawab sama
/// sekali karena jumlahnya tercampur.
class AktivitasPage extends ConsumerStatefulWidget {
  const AktivitasPage({super.key});

  @override
  ConsumerState<AktivitasPage> createState() => _AktivitasPageState();
}

class _AktivitasPageState extends ConsumerState<AktivitasPage> {
  late DateTime _hari = _polos(DateTime.now());

  /// Tengah malam: tanggalnya saja yang menentukan, dan jam yang ikut
  /// terbawa membuat dua tanggal yang sama menjadi dua kunci provider yang
  /// berbeda — satu permintaan jaringan untuk setiap kali layar digambar.
  static DateTime _polos(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get _hariIni => _polos(DateTime.now()) == _hari;

  void _geser(int hari) {
    final baru = _hari.add(Duration(days: hari));
    // TIDAK BOLEH ke masa depan: hari yang belum terjadi selalu kosong, dan
    // layar kosong tanpa sebab terbaca sebagai data yang hilang.
    if (baru.isAfter(_polos(DateTime.now()))) return;
    setState(() => _hari = baru);
  }

  Future<void> _pilihTanggal() async {
    final kini = _polos(DateTime.now());
    final pilih = await showDatePicker(
      context: context,
      initialDate: _hari,
      firstDate: kini.subtract(const Duration(days: 365)),
      lastDate: kini,
      locale: Localizations.localeOf(context),
    );
    if (pilih != null) setState(() => _hari = _polos(pilih));
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final data = ref.watch(aktivitasTanggalProvider(_hari));

    return Scaffold(
      appBar: AppBar(title: Text(t(context).activityTitle)),
      body: Column(
        children: [
          _PemilihHari(
            hari: _hari,
            hariIni: _hariIni,
            onMundur: () => _geser(-1),
            onMaju: _hariIni ? null : () => _geser(1),
            onPilih: _pilihTanggal,
          ),
          Divider(height: 1, color: w.line),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(aktivitasTanggalProvider(_hari)),
              child: data.when(
                loading: () => const SkeletonCards(),
                error: (e, _) => ListView(
                  padding: pagePaddingAman(context),
                  children: [
                    TerraBanner(
                      kind: BannerKind.danger,
                      icon: Icons.cloud_off,
                      title: t(context).watchOfflineTitle,
                      body: t(context).watchOfflineBody,
                    ),
                  ],
                ),
                data: (daftar) => daftar.isEmpty
                    ? ListView(
                        padding: pagePaddingAman(context),
                        children: [
                          TerraBanner(
                            kind: BannerKind.info,
                            icon: Icons.event_busy,
                            title: t(context).activityEmptyTitle,
                            body: t(context).activityEmptyBody,
                          ),
                        ],
                      )
                    : _Daftar(daftar: daftar, hari: _hari, onKetuk: _buka),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Masih jalan → Pantau. Sudah beres → riwayat. Padanan yang SAMA dengan
  /// kartu beranda: dua jalan masuk tidak boleh mendarat di tempat berbeda.
  void _buka(Kegiatan k) {
    final id = k.pilePointID;
    if (id == null) return;
    final rute = k.selesai ? 'history' : 'watch';
    context.push('/casting/point/$id/$rute?code=${Uri.encodeComponent(k.kode)}');
  }
}

/// Kegiatan lapangan pada SATU TANGGAL.
///
/// `family` menurut tanggal: berpindah hari lalu kembali tidak menarik
/// ulang apa pun, dan hari yang sudah lewat tidak akan berubah lagi.
final aktivitasTanggalProvider =
    FutureProvider.autoDispose.family<List<Kegiatan>, DateTime>(
  (ref, hari) async {
    final jawaban = await ref.read(apiProvider).report(hari, hari);
    return susunKegiatan(jawaban, hari);
  },
);

/// Daftar kegiatan, DIKELOMPOKKAN PER PROYEK.
///
/// Urutan kelompoknya mengikuti kegiatan TERBARU di dalamnya, bukan nama
/// proyeknya: yang baru saja bergerak itulah yang dicari orang saat membuka
/// layar ini, dan urutan menurut nama membuat proyek yang diam duduk di
/// pucuk daftar hanya karena kodenya berawalan "A".
///
/// Nama proyeknya diambil dari [projectsProvider] — data yang sudah ada di
/// telepon — bukan dari jawaban laporan. Lihat [Kegiatan.projectID].
class _Daftar extends ConsumerWidget {
  const _Daftar({required this.daftar, required this.hari, required this.onKetuk});

  final List<Kegiatan> daftar;

  /// The day shown — the daily report buttons make THIS day's picture.
  final DateTime hari;
  final void Function(Kegiatan) onKetuk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proyek = ref.watch(projectsProvider).value ?? const [];

    // `daftar` SUDAH terurut terbaru di atas, dan `Map` di Dart menjaga
    // urutan penyisipan — jadi kelompoknya ikut terurut menurut kegiatan
    // terbarunya tanpa perlu diurutkan lagi.
    final kelompok = <int?, List<Kegiatan>>{};
    for (final k in daftar) {
      (kelompok[k.projectID] ??= []).add(k);
    }

    // SERVER LAMA belum mengirimkan `projectID`: satu kelompok tanpa nama.
    // Kepala kosong di atas daftar lebih buruk daripada tidak ada kepala.
    final tanpaProyek = kelompok.length == 1 && kelompok.keys.first == null;

    return ListView(
      padding: pagePaddingAman(context),
      children: [
        // JUMLAH SELURUH HARI, hanya ketika ada lebih dari satu proyek:
        // dengan satu proyek, angkanya sama dengan angka kelompoknya dan
        // ditulis dua kali berturut-turut.
        if (kelompok.length > 1) ...[
          _Ringkas(daftar: daftar, judul: t(context).activityAllProjects),
          const SizedBox(height: 28),
        ],
        for (final (i, e) in kelompok.entries.indexed) ...[
          if (i > 0) const SizedBox(height: 32),
          if (!tanpaProyek) _KepalaProyek(proyek: _proyek(proyek, e.key), id: e.key),
          // Summary + the day's report buttons. Without a project id (an old
          // server) there is no report to make, so the buttons stay away.
          _Ringkas(daftar: e.value, projectId: e.key, hari: hari),
          const SizedBox(height: 18),
          QuietPanel(
            padding: const EdgeInsets.fromLTRB(12, 20, 16, 8),
            child: Column(
              children: [
                for (final k in e.value)
                  BarisKegiatan(k: k, onKetuk: () => onKetuk(k), last: k == e.value.last),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static Map<String, Object?>? _proyek(List<Map<String, Object?>> proyek, int? id) {
    for (final p in proyek) {
      if ('${p['id']}' == '$id') return p;
    }
    return null;
  }
}

/// Kepala satu kelompok proyek: KODE tebal, nama di sebelahnya redup.
///
/// Proyek yang TIDAK ADA di telepon tetap disebut dengan nomornya — sama
/// dengan halaman absensi: keliru yang dapat ditanyakan ke kantor, bukan
/// baris kegiatan yang hilang tanpa jejak.
class _KepalaProyek extends StatelessWidget {
  const _KepalaProyek({required this.proyek, required this.id});

  final Map<String, Object?>? proyek;
  final int? id;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final kode = id == null ? t(context).activityNoProject : '${proyek?['code'] ?? 'Proyek #$id'}';
    final nama = proyek == null ? '' : '${proyek!['name'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(kode, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: w.ink)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nama,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: w.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _PemilihHari extends StatelessWidget {
  const _PemilihHari({
    required this.hari,
    required this.hariIni,
    required this.onMundur,
    required this.onMaju,
    required this.onPilih,
  });

  final DateTime hari;
  final bool hariIni;
  final VoidCallback onMundur;
  final VoidCallback? onMaju;
  final VoidCallback onPilih;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: t(context).activityPrevDay,
            onPressed: onMundur,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onPilih,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Text(
                      longDate(hari),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: w.ink,
                      ),
                    ),
                    Text(
                      hariIni ? t(context).activityToday : t(context).activityPick,
                      style: TextStyle(fontSize: 12, color: w.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            // Mati di hari ini: hari yang belum terjadi selalu kosong.
            tooltip: t(context).activityNextDay,
            onPressed: onMaju,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// JUMLAH HARI ITU — satu-satunya hal yang tidak ada di kartu beranda.
///
/// Pertanyaan yang dibawa ke rapat bukan "titik mana saja yang dikerjakan",
/// melainkan "kemarin dapat berapa meter dan berapa kubik" — jadi METER dan
/// KUBIK yang paling besar, jumlah titiknya keterangan (redesign 22 Nov
/// 2026). Di bawahnya tombol laporan harian proyek itu untuk hari itu.
class _Ringkas extends ConsumerStatefulWidget {
  const _Ringkas({required this.daftar, this.judul, this.projectId, this.hari});

  final List<Kegiatan> daftar;

  /// Diisi hanya untuk jumlah SELURUH proyek; jumlah per proyek sudah
  /// berjudul oleh kepala kelompoknya sendiri.
  final String? judul;

  /// With both: the "Simpan" and "Kirim ke WA" buttons for this project's
  /// daily report on [hari].
  final int? projectId;
  final DateTime? hari;

  @override
  ConsumerState<_Ringkas> createState() => _RingkasState();
}

class _RingkasState extends ConsumerState<_Ringkas> {
  /// Which button is working: 'save' | 'share' | null. One at a time — the
  /// picture is made from the server each time.
  String? _busy;

  Future<void> _run(String which) async {
    final id = widget.projectId;
    final day = widget.hari;
    if (id == null || day == null || _busy != null) return;
    final l = t(context);
    final lang = Localizations.localeOf(context).languageCode;
    final m = ScaffoldMessenger.of(context);
    setState(() => _busy = which);
    try {
      final made = await makeDailyReport(ref, l, lang, id, day);
      if (!mounted) return;
      final png = made.png;
      if (png == null) {
        m
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l.drEmpty(longDate(day)))));
        return;
      }
      if (which == 'save') {
        await saveDailyReport(context, png, made.report.fileName);
      } else {
        await shareDailyReport(context, png, made.report.fileName);
      }
    } catch (e) {
      m
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e is ApiError ? e.message : l.drLoadFailed)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final daftar = widget.daftar;
    final bor = daftar.where((k) => k.bor).toList();
    // A pile still in preparation has not been poured: counting it here
    // would claim a pour that has not happened.
    final cor = daftar.where((k) => !k.bor && !k.preparing).toList();
    // Metres drilled THAT DAY: a hole continued from yesterday adds only
    // its difference (SP.B73, 23 Nov 2026).
    final meter = bor.fold<double>(0, (s, k) => s + (k.metersM ?? k.depthM ?? 0));
    final kubik = cor.fold<double>(0, (s, k) => s + (k.volumeM3 ?? 0));
    final tm = cor.fold<int>(0, (s, k) => s + k.trucks);
    final buttons = widget.projectId != null && widget.hari != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.judul != null)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Text(
              widget.judul!,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: w.ink),
            ),
          ),
        QuietPanel(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: QuietFigure(
                        dot: w.warnFg,
                        label: t(context).drDrilling,
                        value: reportNumber(_lang(context), meter, 1),
                        unit: 'm',
                        sub: '${bor.length} ${t(context).activityDrilled}',
                      ),
                    ),
                    Container(width: 1, color: w.line),
                    Expanded(
                      child: QuietFigure(
                        dot: w.brand,
                        label: t(context).drCasting,
                        value: reportNumber(_lang(context), kubik, 1),
                        unit: 'm³',
                        sub: '${cor.length} ${t(context).activityPoured} · $tm TM',
                      ),
                    ),
                  ],
                ),
              ),
              if (buttons) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: Dimens.minTouch,
                          child: OutlinedButton.icon(
                            onPressed: _busy == null ? () => _run('save') : null,
                            icon: _busy == 'save' ? const _Spin() : const Icon(Icons.download, size: 18),
                            label: Text(t(context).drSave),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: Dimens.minTouch,
                          child: FilledButton.icon(
                            style: quietPrimary(context),
                            onPressed: _busy == null ? () => _run('share') : null,
                            icon: _busy == 'share' ? const _Spin() : const Icon(Icons.share, size: 18),
                            label: Text(t(context).activitySendWa),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _lang(BuildContext context) => Localizations.localeOf(context).languageCode;
}

class _Spin extends StatelessWidget {
  const _Spin();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
}
