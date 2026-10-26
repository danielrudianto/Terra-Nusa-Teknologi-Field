import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
// `SkeletonCards` tinggal di motion.dart, BUKAN di view_states.dart.
import '../../core/theme/motion.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/view_states.dart';
import 'pile_point_data.dart';
import 'titik_denah.dart';

/// DENAH TITIK di HP — gambar yang sama dengan di web.
///
/// Perhitungan letak titiknya seluruhnya di `titik_denah.dart`; halaman ini
/// menggambar, menerima ketukan, dan mengatur zum/putar.
///
/// APA YANG MENGECIL SAAT DIZUM, DAN APA YANG TIDAK
///
/// Yang berskala hanya GEOMETRI: letak titik, dan garis rencana→aktual yang
/// panjangnya memang jarak sungguhan. Semua yang lain — bulatan penanda,
/// kode titik, ketebalan garis — digambar pada ukuran LAYAR yang tetap,
/// dengan membagi ukurannya oleh zum yang sedang berlaku.
///
/// Dulu tidak begitu, dan itulah sebabnya denah ini tidak terbaca: kode
/// titik digambar pada ukuran GAMBAR, jadi satu label selalu selebar dua
/// setengah bulatan, berapa pun zumnya. Menzum memperbesar label persis
/// sebanding dengan jarak antar titik, sehingga tumpukannya tidak pernah
/// terurai — gambarnya tertutup tulisan pada setiap tingkat zum, dan tidak
/// ada yang bisa dilakukan pemakainya untuk memperbaikinya.
///
/// Dengan label berukuran layar tetap, menzum MENGURAIKAN tumpukan: titiknya
/// menjauh, labelnya tidak ikut membesar. Itu yang membuat zum terasa
/// berguna, bukan hanya mungkin.
class TitikDenahPage extends ConsumerStatefulWidget {
  const TitikDenahPage({super.key, required this.projectId});

  final int projectId;

  @override
  ConsumerState<TitikDenahPage> createState() => _TitikDenahPageState();
}

class _TitikDenahPageState extends ConsumerState<TitikDenahPage> {
  bool _label = true;
  bool _simpangan = true;

  /// Putaran denah dalam langkah 90°, 0..3.
  ///
  /// Gambar kerja di lapangan jarang terpasang menghadap utara, dan denah
  /// yang arahnya tidak bisa disamakan dengan kertas di tangan harus
  /// dicocokkan sambil memutar kepala — yang di lapangan berarti tidak
  /// dicocokkan sama sekali. Arah utaranya ikut berputar, jadi denahnya
  /// tetap menyatakan arah yang benar pada posisi apa pun.
  int _putaran = 0;

  final _trafo = TransformationController();

  /// Zum yang sedang berlaku, dibaca dari [_trafo].
  ///
  /// Disimpan di state karena ukuran label, penanda dan batang skala
  /// bergantung padanya — bukan sekadar hiasan yang ikut terbawa transform.
  double _zum = 1.0;

  /// Kotak gambar — sama dengan web, supaya bentuknya sebanding.
  static const _lebar = 1000.0;
  static const _tinggi = 700.0;

  /// Denah yang sudah disusun, beserta daftar titik asalnya.
  ///
  /// KENAPA DISIMPAN, BUKAN DIHITUNG DI `build`
  ///
  /// `_zumBerubah` memanggil setState pada setiap perubahan zum sebesar
  /// 0,01 — puluhan kali per cubitan jari. Dihitung di `build`, `susunDenah`
  /// mengulang min/maks seluruh titik dan satu transform per titik sebanyak
  /// itu pula; pada dinding secant 744 titik, cubitan menjadi tersendat.
  ///
  /// Dan ada akibat kedua yang lebih halus: `Denah` tidak punya `==`, jadi
  /// objek baru setiap build membuat `old.denah != denah` pada
  /// `shouldRepaint` SELALU benar — seluruh kanvas digambar ulang bahkan
  /// ketika tidak ada yang berubah.
  ///
  /// Daftar titiknya datang dari `Provider.family` yang sinkron: selama
  /// datanya tidak berubah, `ref.watch` memulangkan daftar yang SAMA, jadi
  /// `identical` sudah cukup dan tidak perlu membandingkan isinya.
  List<FieldPilePoint>? _bahanTerakhir;
  bool _sudahMenyusun = false;
  Denah? _denahTersimpan;

  Denah? _denah(List<FieldPilePoint> semua) {
    if (_sudahMenyusun && identical(_bahanTerakhir, semua)) {
      return _denahTersimpan;
    }
    _bahanTerakhir = semua;
    _denahTersimpan = susunDenah(semua, lebar: _lebar, tinggi: _tinggi);
    _sudahMenyusun = true;
    return _denahTersimpan;
  }

  @override
  void initState() {
    super.initState();
    _trafo.addListener(_zumBerubah);
  }

  @override
  void dispose() {
    _trafo.removeListener(_zumBerubah);
    _trafo.dispose();
    super.dispose();
  }

  void _zumBerubah() {
    final z = _trafo.value.getMaxScaleOnAxis();
    // Ambang kecil: setiap bingkai gerakan jari mengubah matriksnya, dan
    // setState pada perubahan sepersepuluh piksel hanya membakar baterai.
    if ((z - _zum).abs() > 0.01) setState(() => _zum = z);
  }

  void _pas() {
    _trafo.value = Matrix4.identity();
  }

  void _putar() {
    // Pandangannya dikembalikan ke pas-layar: matriks zum lama mengacu pada
    // kotak yang baru saja berubah bentuk, dan membiarkannya akan membuat
    // denah melompat ke luar layar tanpa sebab yang terlihat.
    // DI LUAR setState: `_pas()` mengubah `_trafo.value`, yang seketika
    // memanggil `_zumBerubah`, yang memanggil setState lagi. setState di
    // dalam setState tidak menggagalkan apa pun di sini, tetapi ia
    // masuk-ulang tanpa sebab — cukup ubah keadaannya dulu, lalu minta
    // satu gambar ulang.
    _putaran = (_putaran + 1) % 4;
    _pas();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(fieldPilePointsProvider(widget.projectId));
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context).denahTitle),
        actions: [
          IconButton(
            tooltip: t(context).denahRotate,
            onPressed: _putar,
            icon: const Icon(Icons.rotate_90_degrees_cw),
          ),
          IconButton(
            tooltip: t(context).denahFit,
            onPressed: _pas,
            icon: const Icon(Icons.fit_screen),
          ),
        ],
      ),
      body: data.when(
        loading: () => const SkeletonCards(),
        error: (e, _) =>
            ErrorState(title: t(context).pointsLoadError, message: '$e'),
        data: (semua) {
          final denah = _denah(semua);
          if (denah == null) {
            return Padding(
              padding: pagePaddingAman(context),
              child: TerraBanner(
                kind: BannerKind.info,
                icon: Icons.location_off,
                title: t(context).denahEmptyTitle,
                body: t(context).denahEmptyBody,
              ),
            );
          }
          // Kanvas MENGISI sisa layar, tidak lagi menjadi pita pendek di
          // dalam daftar yang menggulung. Dua alasan, dan keduanya nyata:
          // menzum di dalam jendela setinggi 250 piksel tidak ada gunanya,
          // dan `InteractiveViewer` di dalam `ListView` berebut gerakan
          // vertikal dengan daftarnya — geser ke atas menggulung halaman,
          // bukan menggeser denah. Itu penyebab zumnya terasa rusak.
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Satu baris yang digulung ke samping, bukan Wrap yang
                    // memakan tiga baris tinggi dari gambarnya.
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _Legenda(hitungan: denah.hitungan),
                    ),
                    const SizedBox(height: 4),
                    _Saklar(
                      label: _label,
                      simpangan: _simpangan,
                      onLabel: (v) => setState(() => _label = v),
                      onSimpangan: (v) => setState(() => _simpangan = v),
                    ),
                    if (denah.tanpaKoordinat > 0) ...[
                      const SizedBox(height: 6),
                      TerraBanner(
                        kind: BannerKind.warning,
                        icon: Icons.location_off,
                        title:
                            t(context).denahNoCoordTitle('${denah.tanpaKoordinat}'),
                        body: t(context).denahNoCoordBody,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _Kanvas(
                    denah: denah,
                    label: _label,
                    simpangan: _simpangan,
                    putaran: _putaran,
                    trafo: _trafo,
                    zum: _zum,
                    onKetuk: _buka,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Ketuk titik: yang SEDANG dikerjakan dibuka di Pantau, sisanya di
  /// riwayat — padanan yang sama dengan kartu kegiatan di layar utama,
  /// supaya dua jalan masuk tidak mendarat di tempat yang berbeda.
  void _buka(TitikDenah tt) {
    final id = tt.id;
    if (id == null) return;
    final berjalan = tt.keadaan == KeadaanTitik.sedangBor ||
        tt.keadaan == KeadaanTitik.sedangCor;
    final rute = berjalan ? 'watch' : 'history';
    context.push(
      '/casting/point/$id/$rute?code=${Uri.encodeQueryComponent(tt.kode)}',
    );
  }
}

// ---------------------------------------------------------------------------
// Transform gambar -> kotak layar
// ---------------------------------------------------------------------------

/// Matriks yang memasukkan kotak gambar ke dalam [kotak], sesudah diputar
/// [putaran] x 90°.
///
/// SATU matriks, dipakai dua kali: menggambar, dan — dibalik — menerjemahkan
/// ketukan kembali ke satuan gambar. Dua salinan trigonometri yang harus
/// selalu sepadan adalah cara paling pasti membuat ketukan mendarat di titik
/// yang salah begitu salah satunya diubah.
Matrix4 matriksDenah(Denah d, int putaran, Size kotak) {
  final f = skalaDenah(d, putaran, kotak);
  final sudut = putaran * math.pi / 2;
  final a = f * math.cos(sudut);
  final b = f * math.sin(sudut);
  final hx = d.lebar / 2;
  final hy = d.tinggi / 2;
  // Bentuk tertutup dari T(pusat kotak) . S(f) . R(sudut) . T(-pusat gambar):
  //   p' = A p + (pusat kotak - A . pusat gambar),  A = [[a,-b],[b,a]]
  return affine2D(
    a,
    b,
    kotak.width / 2 - (a * hx - b * hy),
    kotak.height / 2 - (b * hx + a * hy),
  );
}

/// `Matrix4` untuk affine 2D: bagian putar-skala [a],[b] dan geseran
/// [tx],[ty], disusun kolom demi kolom.
///
/// Dibangun dari nilainya LANGSUNG, bukan lewat
/// `Matrix4.identity()..translate(..)..scale(..)`. Pembangun berantai itu
/// memakai parameter bertipe dinamis yang sudah ditandai usang di `Matrix4`
/// dan digantikan `translateByDouble`/`scaleByDouble`; menuliskan angkanya
/// sendiri membuat berkas ini tidak bergantung pada mana di antara keduanya
/// yang masih ada di SDK berikutnya — dan sekaligus menaruh seluruh
/// hitungannya di satu tempat yang bisa diuji.
Matrix4 affine2D(double a, double b, double tx, double ty) => Matrix4(
      a, b, 0, 0, //
      -b, a, 0, 0, //
      0, 0, 1, 0, //
      tx, ty, 0, 1,
    );

/// Skala murni dari [matriksDenah] — gambar ke piksel kotak, tanpa zum.
double skalaDenah(Denah d, int putaran, Size kotak) {
  final genap = putaran % 2 == 0;
  final f = math.min(
    kotak.width / (genap ? d.lebar : d.tinggi),
    kotak.height / (genap ? d.tinggi : d.lebar),
  );
  // DIBATASI DI ATAS NOL. Di dalam `Expanded` + `LayoutBuilder`, satu
  // bingkai peralihan dapat memberi tinggi 0: `f` menjadi 0, `px` menjadi
  // tak hingga (geometri NaN), dan matriksnya singular — sehingga ketukan
  // berikutnya meledak di `Matrix4.inverted` dengan "Cannot invert a matrix
  // with a zero determinant".
  return f.isFinite && f > 1e-9 ? f : 1e-9;
}

/// Titik [p] lewat matriks affine 2D [m].
Offset _maju(Matrix4 m, Offset p) {
  final s = m.storage;
  return Offset(
    s[0] * p.dx + s[4] * p.dy + s[12],
    s[1] * p.dx + s[5] * p.dy + s[13],
  );
}

/// Titik [p] lewat kebalikan [m].
Offset _balik(Matrix4 m, Offset p) => _maju(Matrix4.inverted(m), p);

// ---------------------------------------------------------------------------
// Kanvas
// ---------------------------------------------------------------------------

/// Kotak gambarnya: dapat dizum, digeser, dan diketuk.
class _Kanvas extends StatefulWidget {
  const _Kanvas({
    required this.denah,
    required this.label,
    required this.simpangan,
    required this.putaran,
    required this.trafo,
    required this.zum,
    required this.onKetuk,
  });

  final Denah denah;
  final bool label;
  final bool simpangan;
  final int putaran;
  final TransformationController trafo;
  final double zum;
  final ValueChanged<TitikDenah> onKetuk;

  @override
  State<_Kanvas> createState() => _KanvasState();
}

class _KanvasState extends State<_Kanvas> {
  /// Letak ketukan ganda, direkam di `onDoubleTapDown` karena
  /// `onDoubleTap` sendiri tidak membawa posisi.
  Offset _dobel = Offset.zero;

  void _ketukGanda(Size kotak) {
    // Bolak-balik: sudah dizum -> kembali pas layar; masih pas layar ->
    // zum ke titik yang diketuk. Satu ketukan ganda untuk memeriksa satu
    // sudut, satu lagi untuk kembali melihat keseluruhan.
    if (widget.trafo.value.getMaxScaleOnAxis() > 1.8) {
      widget.trafo.value = Matrix4.identity();
      return;
    }
    const target = 3.0;
    final pusat = kotak.center(Offset.zero);
    // Titik yang diketuk dibawa ke tengah layar pada zum `target`:
    //   p' = target . p + (pusat - target . dobel)
    widget.trafo.value = affine2D(
      target,
      0,
      pusat.dx - target * _dobel.dx,
      pusat.dy - target * _dobel.dy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        // Latar PUTIH, bukan warna kartu — juga pada tema gelap. Denah ini
        // dibandingkan dengan gambar kerja yang juga putih, dan latar
        // berwarna menggeser tafsir warna bulatannya. Warna garis di
        // dalamnya karena itu warna TINTA, bukan token tema.
        color: const Color(0xFFFFFFFF),
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: w.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: LayoutBuilder(
          builder: (context, batas) {
            final kotak = Size(batas.maxWidth, batas.maxHeight);
            final m = matriksDenah(widget.denah, widget.putaran, kotak);
            final f = skalaDenah(widget.denah, widget.putaran, kotak);
            return Stack(
              children: [
                InteractiveViewer(
                  transformationController: widget.trafo,
                  // Boleh dizum KELUAR sampai separuh. Denah rapat yang
                  // sudah pas layar masih sering perlu dilihat lebih longgar
                  // untuk menakar sebaran, dan bawaan 0,8 menolaknya.
                  minScale: 0.5,
                  maxScale: 12,
                  // Ruang gerak di luar tepi. Tanpa ini, titik di sudut
                  // tidak dapat dibawa ke tengah layar pada zum tinggi — ia
                  // tersangkut di pinggir, tertutup jari yang menggesernya.
                  boundaryMargin: const EdgeInsets.all(600),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final titik = _terdekat(
                        _balik(m, d.localPosition),
                        f * widget.zum,
                      );
                      if (titik != null) widget.onKetuk(titik);
                    },
                    onDoubleTapDown: (d) => _dobel = d.localPosition,
                    onDoubleTap: () => _ketukGanda(kotak),
                    child: CustomPaint(
                      size: kotak,
                      painter: _DenahPainter(
                        denah: widget.denah,
                        label: widget.label,
                        simpangan: widget.simpangan,
                        matriks: m,
                        // Satu piksel LAYAR dalam satuan gambar. Seluruh
                        // ukuran yang harus tetap di layar dinyatakan dengan
                        // ini.
                        px: 1 / (f * widget.zum),
                        zum: widget.zum,
                        putaran: widget.putaran,
                      ),
                    ),
                  ),
                ),
                // Batang skala dan arah utara DIPAKU di sudut layar, di luar
                // InteractiveViewer. Digambar di dalam gambar, keduanya
                // menggeser keluar layar justru pada saat dibutuhkan — yaitu
                // ketika sedang dizum ke satu sudut.
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: _BatangSkala(
                    panjangPx: widget.denah.batangSkala * f * widget.zum,
                    meter: widget.denah.meterBatang,
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: _ArahUtara(putaran: widget.putaran),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Titik terdekat dalam radius ketuk, atau `null`.
  ///
  /// Radiusnya ditetapkan dalam PIKSEL LAYAR lalu diubah ke satuan gambar
  /// memakai [skalaLayar]: ujung jari tetap selebar ujung jari pada zum
  /// berapa pun, sedangkan radius tetap dalam satuan gambar akan menelan
  /// selusin titik begitu dizum keluar, dan membuka titik yang salah.
  TitikDenah? _terdekat(Offset di, double skalaLayar) {
    final radius = 22.0 / (skalaLayar <= 0 ? 1 : skalaLayar);
    TitikDenah? pilih;
    var jarakTerdekat = double.infinity;
    for (final t in widget.denah.titik) {
      final jarak = (t.posisi - di).distance;
      if (jarak <= radius && jarak < jarakTerdekat) {
        jarakTerdekat = jarak;
        pilih = t;
      }
    }
    return pilih;
  }
}

// ---------------------------------------------------------------------------
// Hiasan yang dipaku di sudut
// ---------------------------------------------------------------------------

class _BatangSkala extends StatelessWidget {
  const _BatangSkala({required this.panjangPx, required this.meter});

  final double panjangPx;
  final double meter;

  @override
  Widget build(BuildContext context) {
    // Dibatasi supaya tidak melebihi layar pada zum tinggi; angkanya ikut
    // dibagi, jadi yang tertulis tetap benar untuk panjang yang tergambar.
    const maks = 180.0;
    final terpakai = panjangPx.clamp(1.0, maks);
    final meterTerpakai = meter * terpakai / (panjangPx <= 0 ? 1 : panjangPx);
    final angka = meterTerpakai < 1
        ? meterTerpakai.toStringAsFixed(2)
        : meterTerpakai < 10
            ? meterTerpakai.toStringAsFixed(1)
            : meterTerpakai.toStringAsFixed(0);
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${angka.replaceAll('.', ',')} m',
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _tintaDenah,
            ),
          ),
          const SizedBox(height: 2),
          CustomPaint(
            size: Size(terpakai, 10),
            painter: _BatangPainter(),
          ),
        ],
      ),
    );
  }
}

class _BatangPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cat = Paint()
      ..color = _tintaDenah
      ..strokeWidth = 1.4;
    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), cat);
    canvas.drawLine(Offset(0, y - 5), Offset(0, y + 5), cat);
    canvas.drawLine(Offset(size.width, y - 5), Offset(size.width, y + 5), cat);
  }

  @override
  bool shouldRepaint(covariant _BatangPainter old) => false;
}

class _ArahUtara extends StatelessWidget {
  const _ArahUtara({required this.putaran});

  final int putaran;

  @override
  Widget build(BuildContext context) {
    // Y survei bertambah ke utara dan sumbu Y sudah dibalik di
    // `susunDenah`, jadi utara ADALAH atas selama denahnya belum diputar.
    // Begitu diputar, panah ini harus ikut — denah yang arahnya berubah
    // tetapi panahnya tidak akan dipercaya sampai ada yang salah menggali.
    return IgnorePointer(
      // Kotaknya PERSEGI seukuran sisi terpanjang panahnya: Transform
      // tidak mengubah ukuran yang dipesan, jadi panah 22x40 yang diputar
      // 90° akan menjorok keluar dan terpotong oleh ClipRRect kanvasnya.
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Transform.rotate(
            angle: putaran * math.pi / 2,
            child: CustomPaint(
              size: const Size(22, 40),
              painter: _UtaraPainter(),
            ),
          ),
        ),
      ),
    );
  }
}

class _UtaraPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final cat = Paint()
      ..color = _tintaDenah
      ..strokeWidth = 1.4;
    canvas.drawLine(Offset(x, size.height), Offset(x, 10), cat);
    canvas.drawPath(
      Path()
        ..moveTo(x, 0)
        ..lineTo(x + 5, 11)
        ..lineTo(x - 5, 11)
        ..close(),
      Paint()..color = _tintaDenah,
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'U',
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _tintaDenah,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, size.height - 14));
  }

  @override
  bool shouldRepaint(covariant _UtaraPainter old) => false;
}

// ---------------------------------------------------------------------------
// Legenda & saklar
// ---------------------------------------------------------------------------

class _Legenda extends StatelessWidget {
  const _Legenda({required this.hitungan});

  final Map<KeadaanTitik, int> hitungan;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    String nama(KeadaanTitik k) => switch (k) {
          KeadaanTitik.belumBor => t(context).stageUndrilled,
          KeadaanTitik.sedangBor => t(context).stageDrilling,
          KeadaanTitik.sudahBor => t(context).denahDrilled,
          KeadaanTitik.sedangCor => t(context).stageCasting,
          KeadaanTitik.sudahCor => t(context).stageCast,
        };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final k in KeadaanTitik.values) ...[
          CustomPaint(
            size: const Size(13, 13),
            painter: _TandaPainter(gayaKeadaan[k]!),
          ),
          const SizedBox(width: 5),
          Text(nama(k), style: TextStyle(fontSize: 12, color: w.ink)),
          const SizedBox(width: 4),
          Text(
            '${hitungan[k] ?? 0}',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: w.ink),
          ),
          const SizedBox(width: 14),
        ],
      ],
    );
  }
}

class _TandaPainter extends CustomPainter {
  _TandaPainter(this.gaya);

  final GayaKeadaan gaya;

  @override
  void paint(Canvas canvas, Size size) {
    final pusat = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1.5;
    final isi = gaya.isi;
    if (isi != null) canvas.drawCircle(pusat, r, Paint()..color = isi);
    canvas.drawCircle(
      pusat,
      r,
      Paint()
        ..color = gaya.garis
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _TandaPainter old) => old.gaya != gaya;
}

class _Saklar extends StatelessWidget {
  const _Saklar({
    required this.label,
    required this.simpangan,
    required this.onLabel,
    required this.onSimpangan,
  });

  final bool label;
  final bool simpangan;
  final ValueChanged<bool> onLabel;
  final ValueChanged<bool> onSimpangan;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      children: [
        FilterChip(
          selected: label,
          onSelected: onLabel,
          label: Text(t(context).denahLabelToggle),
        ),
        FilterChip(
          selected: simpangan,
          onSelected: onSimpangan,
          label: Text(t(context).denahDeviationToggle),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Penggambar
// ---------------------------------------------------------------------------

const _tintaDenah = Color(0xFF5A6472);

class _DenahPainter extends CustomPainter {
  _DenahPainter({
    required this.denah,
    required this.label,
    required this.simpangan,
    required this.matriks,
    required this.px,
    required this.zum,
    required this.putaran,
  });

  final Denah denah;
  final bool label;
  final bool simpangan;
  final Matrix4 matriks;

  /// Satu piksel layar, dalam satuan gambar.
  final double px;
  final double zum;
  final int putaran;

  static const _redup = Color(0xFF9AA1AC);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.transform(matriks.storage);

    // Bulatan penanda: ukuran LAYAR tetap, menipis sedikit pada proyek yang
    // sangat rapat supaya sebarannya masih terbaca saat pas layar.
    final n = denah.titik.length;
    final jariPx = n <= 120
        ? 7.0
        : n <= 300
            ? 6.0
            : 5.0;
    final jari = jariPx * px;

    // GARIS RENCANA→AKTUAL digambar LEBIH DULU, supaya ia lewat di
    // belakang dan tidak memotong tanda titiknya. Panjangnya BERSKALA —
    // ia menyatakan jarak sungguhan, bukan hiasan.
    if (simpangan) {
      final catGeser = Paint()
        ..color = _redup
        ..strokeWidth = px;
      for (final t in denah.titik) {
        final r = t.rencana;
        if (r == null) continue;
        canvas.drawLine(r, t.posisi, catGeser);
        canvas.drawCircle(r, 2 * px, Paint()..color = _redup);
      }
    }

    for (final t in denah.titik) {
      final gaya = gayaKeadaan[t.keadaan]!;
      final isi = gaya.isi;
      canvas.drawCircle(
        t.posisi,
        jari,
        Paint()..color = isi ?? const Color(0xFFFFFFFF),
      );
      canvas.drawCircle(
        t.posisi,
        jari,
        Paint()
          ..color = gaya.garis
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 * px,
      );
    }

    if (label) {
      for (final t in _labelTerpilih()) {
        _teks(canvas, t.kode, t.posisi, jari + 4 * px);
      }
    }

    canvas.restore();
  }

  /// Titik yang labelnya digambar: yang pertama pada setiap petak layar.
  ///
  /// Labelnya kini berukuran layar tetap, tetapi pada pas-layar proyek
  /// ratusan titik masih menumpuk — sekadar lebih kecil dari sebelumnya.
  /// Jadi ruang LAYAR dibagi petak sebesar satu label, dan tiap petak
  /// mendapat satu label saja.
  ///
  /// Hasilnya mengurai sendiri saat dizum: petaknya tetap sebesar label,
  /// tetapi titiknya menjauh, sehingga makin banyak titik mendapat petak
  /// sendiri sampai akhirnya seluruhnya berlabel. Dibanding mematikan
  /// label di atas 120 titik — yang dulu dilakukan — tidak ada tingkat zum
  /// yang gambarnya menjadi bubur, dan tidak ada yang perlu dimatikan.
  Iterable<TitikDenah> _labelTerpilih() {
    const petakX = 52.0;
    const petakY = 16.0;
    final diambil = <int>{};
    final hasil = <TitikDenah>[];
    for (final t in denah.titik) {
      final layar = _maju(matriks, t.posisi) * zum;
      // Kunci petak: satu bilangan dari dua indeks, tanpa objek per titik.
      final kunci = (layar.dx / petakX).floor() * 100003 +
          (layar.dy / petakY).floor();
      if (diambil.add(kunci)) hasil.add(t);
    }
    return hasil;
  }

  /// Teks berpusat mendatar di [di], berukuran LAYAR tetap dan selalu
  /// TEGAK.
  ///
  /// Matriks gambar memuat putaran denah, jadi teks yang digambar begitu
  /// saja akan ikut miring — pada 90° kode titiknya terbaca menyamping, dan
  /// pada 180° terbalik. Kanvasnya karena itu dilawan-putar di titik
  /// jangkarnya: sesudah itu sumbu setempat searah dengan layar, sehingga
  /// "di atas bulatan" berarti benar-benar di atas, bukan ke samping.
  void _teks(Canvas canvas, String teks, Offset jangkar, double naik) {
    final tp = TextPainter(
      text: TextSpan(
        text: teks,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 11 * px,
          fontWeight: FontWeight.w600,
          color: _tintaDenah,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    canvas.save();
    canvas.translate(jangkar.dx, jangkar.dy);
    canvas.rotate(-putaran * math.pi / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -naik - tp.height));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DenahPainter old) =>
      old.denah != denah ||
      old.label != label ||
      old.simpangan != simpangan ||
      old.matriks != matriks ||
      old.px != px ||
      old.zum != zum ||
      old.putaran != putaran;
}
