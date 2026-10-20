import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';
import '../../core/util/format.dart';
import '../../core/widgets/terra_banner.dart';
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
                  padding: const EdgeInsets.all(Dimens.pagePadding),
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
                        padding: const EdgeInsets.all(Dimens.pagePadding),
                        children: [
                          TerraBanner(
                            kind: BannerKind.info,
                            icon: Icons.event_busy,
                            title: t(context).activityEmptyTitle,
                            body: t(context).activityEmptyBody,
                          ),
                        ],
                      )
                    : _Daftar(daftar: daftar, onKetuk: _buka),
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
  const _Daftar({required this.daftar, required this.onKetuk});

  final List<Kegiatan> daftar;
  final void Function(Kegiatan) onKetuk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
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
      padding: const EdgeInsets.all(Dimens.pagePadding),
      children: [
        // JUMLAH SELURUH HARI, hanya ketika ada lebih dari satu proyek:
        // dengan satu proyek, angkanya sama dengan angka kelompoknya dan
        // ditulis dua kali berturut-turut.
        if (kelompok.length > 1) ...[
          _Ringkas(daftar: daftar, judul: t(context).activityAllProjects),
          const SizedBox(height: 14),
        ],
        for (final (i, e) in kelompok.entries.indexed) ...[
          if (i > 0) const SizedBox(height: 18),
          if (!tanpaProyek)
            _KepalaProyek(nama: _namaProyek(context, proyek, e.key)),
          _Ringkas(daftar: e.value),
          const SizedBox(height: 12),
          for (final k in e.value) ...[
            BarisKegiatan(k: k, onKetuk: () => onKetuk(k)),
            Divider(height: 14, color: w.line),
          ],
        ],
      ],
    );
  }

  /// "TNT-24-001 · Gudang Cikarang", sama dengan layar lain.
  ///
  /// Proyek yang TIDAK ADA di telepon tetap disebut dengan nomornya —
  /// sama dengan halaman absensi. Ia tetap keliru bila nomornya tidak
  /// dikenal, tetapi keliru yang dapat ditanyakan ke kantor, bukan baris
  /// kegiatan yang hilang tanpa jejak.
  static String _namaProyek(
    BuildContext context,
    List<Map<String, Object?>> proyek,
    int? id,
  ) {
    if (id == null) return t(context).activityNoProject;
    for (final p in proyek) {
      if ('${p['id']}' == '$id') return '${p['code']} \u00b7 ${p['name']}';
    }
    return 'Proyek #$id';
  }
}

/// Kepala satu kelompok proyek.
///
/// Sengaja TENANG — satu baris kecil berhuruf tebal, bukan kartu berwarna:
/// yang dibaca di layar ini adalah kegiatannya, dan kepala yang mencolok
/// akan bersaing dengan isinya.
class _KepalaProyek extends StatelessWidget {
  const _KepalaProyek({required this.nama});

  final String nama;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.business_outlined, size: 15, color: w.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              nama,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: w.muted,
              ),
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
/// melainkan "kemarin dapat berapa meter dan berapa kubik".
class _Ringkas extends StatelessWidget {
  const _Ringkas({required this.daftar, this.judul});

  final List<Kegiatan> daftar;

  /// Diisi hanya untuk jumlah SELURUH proyek; jumlah per proyek sudah
  /// berjudul oleh kepala kelompoknya sendiri.
  final String? judul;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final bor = daftar.where((k) => k.bor).length;
    final cor = daftar.where((k) => !k.bor).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: w.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: w.line),
      ),
      child: Column(
        children: [
          if (judul != null) ...[
            Text(
              judul!,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: w.muted,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: _Angka(
                  ikon: Icons.construction,
                  warna: w.warnFg,
                  nilai: '$bor',
                  label: t(context).activityDrilled,
                ),
              ),
              Container(width: 1, height: 30, color: w.line),
              Expanded(
                child: _Angka(
                  ikon: Icons.local_shipping,
                  warna: w.brand,
                  nilai: '$cor',
                  label: t(context).activityPoured,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Angka extends StatelessWidget {
  const _Angka({
    required this.ikon,
    required this.warna,
    required this.nilai,
    required this.label,
  });

  final IconData ikon;
  final Color warna;
  final String nilai;
  final String label;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Column(
      children: [
        Icon(ikon, size: 18, color: warna),
        const SizedBox(height: 4),
        Text(nilai,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: w.ink)),
        Text(label, style: TextStyle(fontSize: 12, color: w.muted)),
      ],
    );
  }
}
