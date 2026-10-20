import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/view_states.dart';
import 'pile_point_data.dart';
import 'titik_denah.dart';

/// DENAH TITIK di HP — gambar yang sama dengan di web.
///
/// Perhitungannya seluruhnya di `titik_denah.dart`; halaman ini hanya
/// menggambar dan menerima ketukan.
///
/// DIZUM, bukan dimuat ulang pada ukuran lain. `InteractiveViewer`
/// memperbesar hasil gambar vektor yang sama, jadi kode titik tetap
/// terbaca pada proyek berisi ratusan titik — dan tidak ada permintaan
/// kedua ke mana pun.
class TitikDenahPage extends ConsumerStatefulWidget {
  const TitikDenahPage({super.key, required this.projectId});

  final int projectId;

  @override
  ConsumerState<TitikDenahPage> createState() => _TitikDenahPageState();
}

class _TitikDenahPageState extends ConsumerState<TitikDenahPage> {
  /// `null` = belum ditentukan pemakainya; nilai bawaannya baru dapat
  /// dihitung sesudah titiknya dimuat (lihat di bawah).
  bool? _label;
  bool _simpangan = true;

  /// Kotak gambar — sama dengan web, supaya bentuknya sebanding.
  static const _lebar = 1000.0;
  static const _tinggi = 700.0;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(fieldPilePointsProvider(widget.projectId));
    return Scaffold(
      appBar: AppBar(title: Text(t(context).denahTitle)),
      body: data.when(
        loading: () => const SkeletonCards(),
        error: (e, _) =>
            ErrorState(title: t(context).pointsLoadError, message: '$e'),
        data: (semua) {
          // Label kode MATI secara BAWAAN di atas 120 titik: pada proyek
          // sebesar itu labelnya saling menimpa menjadi bubur, dan denah
          // yang pertama kali dibuka sebagai bubur tidak dibuka kedua kali.
          //
          // Bawaan, bukan larangan: yang sudah menzum satu sudut justru
          // memerlukan kodenya, jadi saklarnya tetap dapat dinyalakan.
          final label = _label ?? semua.length <= 120;
          final denah = susunDenah(semua, lebar: _lebar, tinggi: _tinggi);
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
          return ListView(
            padding: pagePaddingAman(context),
            children: [
              _Legenda(hitungan: denah.hitungan),
              const SizedBox(height: 6),
              _Saklar(
                label: label,
                simpangan: _simpangan,
                onLabel: (v) => setState(() => _label = v),
                onSimpangan: (v) => setState(() => _simpangan = v),
              ),
              if (denah.tanpaKoordinat > 0) ...[
                const SizedBox(height: 8),
                TerraBanner(
                  kind: BannerKind.warning,
                  icon: Icons.location_off,
                  title: t(context)
                      .denahNoCoordTitle('${denah.tanpaKoordinat}'),
                  body: t(context).denahNoCoordBody,
                ),
              ],
              const SizedBox(height: 10),
              _Kanvas(
                denah: denah,
                label: label,
                simpangan: _simpangan,
                onKetuk: _buka,
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

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final k in KeadaanTitik.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size(14, 14),
                painter: _TandaPainter(gayaKeadaan[k]!),
              ),
              const SizedBox(width: 5),
              Text(nama(k), style: TextStyle(fontSize: 12.5, color: w.ink)),
              const SizedBox(width: 4),
              Text(
                '${hitungan[k] ?? 0}',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800, color: w.ink),
              ),
            ],
          ),
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

/// Kotak gambarnya, dapat dizum dan digeser.
class _Kanvas extends StatelessWidget {
  const _Kanvas({
    required this.denah,
    required this.label,
    required this.simpangan,
    required this.onKetuk,
  });

  final Denah denah;
  final bool label;
  final bool simpangan;
  final ValueChanged<TitikDenah> onKetuk;

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
        child: AspectRatio(
          aspectRatio: denah.lebar / denah.tinggi,
          child: InteractiveViewer(
            maxScale: 8,
            child: LayoutBuilder(
              builder: (context, kotak) {
                // Satuan gambar -> piksel. Satu angka untuk kedua sumbu:
                // `AspectRatio` sudah menjaga perbandingannya, dan dua
                // angka yang berbeda akan merusak justru skala yang
                // seluruh denah ini dibangun untuk menjaganya.
                final skala = kotak.maxWidth / denah.lebar;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final titik = _terdekat(d.localPosition / skala);
                    if (titik != null) onKetuk(titik);
                  },
                  child: CustomPaint(
                    size: Size(kotak.maxWidth, kotak.maxHeight),
                    painter: _DenahPainter(
                      denah: denah,
                      label: label,
                      simpangan: simpangan,
                      skala: skala,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Titik terdekat dalam radius ketuk, atau `null`.
  ///
  /// RADIUSNYA DALAM SATUAN GAMBAR dan jauh lebih lebar daripada
  /// bulatannya: pada proyek rapat, bulatan selebar 8 satuan tidak dapat
  /// ditekan dengan ujung jari, dan layar yang tidak menanggapi ketukan
  /// terbaca sebagai layar yang rusak. Yang TERDEKAT yang menang, jadi
  /// radius yang saling tumpang tidak membuka titik yang salah.
  TitikDenah? _terdekat(Offset di) {
    const radius = 24.0;
    TitikDenah? pilih;
    var jarakTerdekat = double.infinity;
    for (final t in denah.titik) {
      final jarak = (t.posisi - di).distance;
      if (jarak <= radius && jarak < jarakTerdekat) {
        jarakTerdekat = jarak;
        pilih = t;
      }
    }
    return pilih;
  }
}

class _DenahPainter extends CustomPainter {
  _DenahPainter({
    required this.denah,
    required this.label,
    required this.simpangan,
    required this.skala,
  });

  final Denah denah;
  final bool label;
  final bool simpangan;
  final double skala;

  static const _tinta = Color(0xFF5A6472);
  static const _redup = Color(0xFF9AA1AC);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(skala);

    // Bulatan mengecil pada proyek yang titiknya banyak, sama seperti web.
    final n = denah.titik.length;
    final jari = n <= 40
        ? 7.0
        : n <= 120
            ? 5.5
            : n <= 300
                ? 4.0
                : 3.0;

    // GARIS RENCANA→AKTUAL digambar LEBIH DULU, supaya ia lewat di
    // belakang dan tidak memotong tanda titiknya.
    if (simpangan) {
      final catGeser = Paint()
        ..color = _redup
        ..strokeWidth = 1;
      for (final t in denah.titik) {
        final r = t.rencana;
        if (r == null) continue;
        canvas.drawLine(r, t.posisi, catGeser);
        canvas.drawCircle(r, 1.8, Paint()..color = _redup);
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
          ..strokeWidth = 2,
      );
      if (label) {
        _teks(canvas, t.kode, t.posisi - Offset(0, jari + 13), _tinta);
      }
    }

    // Batang skala: gambar berskala tanpa batang skala tidak dapat dipakai
    // menakar jarak. Di sudut, di luar rombongan titik.
    final catSkala = Paint()
      ..color = _tinta
      ..strokeWidth = 1.4;
    final y = denah.tinggi - 18;
    canvas.drawLine(Offset(18, y), Offset(18 + denah.batangSkala, y), catSkala);
    canvas.drawLine(Offset(18, y - 5), Offset(18, y + 5), catSkala);
    canvas.drawLine(
      Offset(18 + denah.batangSkala, y - 5),
      Offset(18 + denah.batangSkala, y + 5),
      catSkala,
    );
    _teks(
      canvas,
      '${denah.meterBatang.toStringAsFixed(denah.meterBatang < 1 ? 1 : 0).replaceAll('.', ',')} m',
      Offset(18 + denah.batangSkala / 2, y - 22),
      _tinta,
    );

    // Arah utara: tanpa ini denahnya tidak dapat dicocokkan dengan
    // lapangan. Y survei bertambah ke utara, dan sumbu Y sudah dibalik di
    // `susunDenah`, jadi utara ADALAH atas.
    final xu = denah.lebar - 30;
    canvas.drawLine(Offset(xu, 48), Offset(xu, 20), catSkala);
    canvas.drawPath(
      Path()
        ..moveTo(xu, 14)
        ..lineTo(xu + 5, 24)
        ..lineTo(xu - 5, 24)
        ..close(),
      Paint()..color = _tinta,
    );
    _teks(canvas, 'U', Offset(xu, 52), _tinta);

    canvas.restore();
  }

  /// Teks berpusat di [di], dalam satuan gambar.
  void _teks(Canvas canvas, String teks, Offset di, Color warna) {
    final tp = TextPainter(
      text: TextSpan(
        text: teks,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: warna,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    tp.paint(canvas, di - Offset(tp.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant _DenahPainter old) =>
      old.denah != denah ||
      old.label != label ||
      old.simpangan != simpangan ||
      old.skala != skala;
}
