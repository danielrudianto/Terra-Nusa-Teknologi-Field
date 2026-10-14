import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/view_states.dart';
import '../../core/i18n.dart';
import '../drilling/bor_kurva.dart';
import '../drilling/bor_kurva_view.dart';

/// Riwayat satu titik, dibaca LANGSUNG dari server.
///
/// Alasan layar ini ada: satu titik hanya boleh punya satu log cor, dan log
/// itu hidup di HP yang membuatnya. Siapa pun yang membuka titik tersebut
/// dari HP lain — termasuk yang sudah selesai dicor kemarin — tidak dapat
/// melihat satu angka pun hasilnya. Yang tampil hanya angka RENCANA, dan
/// orang menyimpulkan datanya hilang.
///
/// Karena itu tidak ada apa pun di sini yang diambil dari basis data HP:
/// seluruhnya dari `/field/pile-points/{id}/riwayat`, dan tanpa sinyal
/// layar ini memang tidak bisa dibuka. Itu jujur, dan lebih baik daripada
/// menampilkan sebagian yang kebetulan ada.
final _historyProvider = FutureProvider.autoDispose.family<Map<String, Object?>, int>(
  (ref, pileId) => ref.read(apiProvider).pointHistory(pileId),
);

class PointHistoryPage extends ConsumerWidget {
  const PointHistoryPage({super.key, required this.pileId, required this.code});

  final int pileId;
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_historyProvider(pileId));
    return Scaffold(
      appBar: AppBar(title: Text(t(context).pointHistoryTitle(code))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_historyProvider(pileId)),
        child: data.when(
          loading: () => const LoadingState(),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(Dimens.pagePadding),
            children: [
              TerraBanner(
                kind: BannerKind.danger,
                icon: Icons.cloud_off,
                title: t(context).pointHistoryErrorTitle,
                body: t(context).pointHistoryErrorBody,
              ),
            ],
          ),
          data: (d) => _isi(context, d),
        ),
      ),
    );
  }

  Widget _isi(BuildContext context, Map<String, Object?> d) {
    final titik = ((d['titik'] as Map?) ?? const {}).cast<String, Object?>();
    final drillLogs = (d['drillLogs'] as List?) ?? const [];
    final castings = (d['castings'] as List?) ?? const [];
    final jejak = (d['jejak'] as List?) ?? const [];
    final dikonfirmasi = titik['checkedAt'] == null
        ? null
        : DateTime.tryParse('${titik['checkedAt']}');
    return ListView(
      padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, Dimens.pagePadding, Dimens.pagePadding, 40),
      children: [
        // Titik yang sudah dikonfirmasi tidak dapat lagi dibetulkan dari
        // mana pun. Itu harus terbaca sebelum angka-angkanya, bukan sesudah
        // orang mencoba mengubah sesuatu dan ditolak tanpa sebab yang jelas.
        if (dikonfirmasi != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TerraBanner(
              kind: BannerKind.ok,
              icon: Icons.verified,
              title: t(context).pointConfirmedTitle,
              body: t(context).pointConfirmedBody(
                titik['checkedByName']?.toString() ?? t(context).colleague,
                '${longDate(dikonfirmasi)} ${formatTime(dikonfirmasi)}',
              ),
            ),
          ),
        if (drillLogs.isNotEmpty) ...[
          _JudulBagian(t(context).drillSection),
          for (final b in drillLogs) _KartuBor(log: (b as Map).cast<String, Object?>()),
        ],
        if (castings.isEmpty)
          EmptyState(message: t(context).pointHistoryNoCasting)
        else ...[
          _JudulBagian(t(context).castSection),
          for (final c in castings) _KartuCor(cor: (c as Map).cast<String, Object?>()),
        ],
        if (jejak.isNotEmpty)
          _JejakLipat(
            jejak: [for (final j in jejak) (j as Map).cast<String, Object?>()],
          ),
      ],
    );
  }
}

/// Satu log cor beserta TM-nya.
class _KartuCor extends StatelessWidget {
  const _KartuCor({required this.cor});

  final Map<String, Object?> cor;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final h = ((cor['hitungan'] as Map?) ?? const {}).cast<String, Object?>();
    final tm = ((cor['trucks'] as List?) ?? const []).map((x) => (x as Map).cast<String, Object?>()).toList()
      ..sort((a, b) => (toIntOrNull(a['seq']) ?? 0).compareTo(toIntOrNull(b['seq']) ?? 0));
    final perTm = <int, Map<String, Object?>>{
      for (final x in ((h['perTm'] as List?) ?? const []))
        (toIntOrNull((x as Map)['seq']) ?? 0): x.cast<String, Object?>(),
    };
    final tremie = ((h['tremieRingkas'] as Map?) ?? const {}).cast<String, Object?>();
    final dihapus = cor['isDelete'] == true || cor['isDelete'] == 1;
    final dariKantor = '${cor['source']}' == 'kantor';
    final volume = toDoubleOrNull(h['volumeAktualM3']);
    final teoritis = toDoubleOrNull(h['volumeTeoritisAktualM3']) ?? toDoubleOrNull(h['volumeTeoritisRencanaM3']);
    final lebih = toDoubleOrNull(h['lebihPakaiPersen']);

    return ListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cor['date'] == null ? '–' : longDate(DateTime.parse('${cor['date']}')),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: w.ink),
                ),
              ),
              // Log yang DIHAPUS tetap ditampilkan, dan ditandai. Riwayat yang
              // hanya memuat baris hidup tidak dapat menjawab "kemarin
              // volumenya 12 m³, kok sekarang kosong" — dan pertanyaan itulah
              // yang dibawa ke rapat.
              if (dihapus) StatusBadge(text: t(context).deletedLabel, bg: w.badBg, fg: w.badFg),
              if (!dihapus && dariKantor)
                StatusBadge(text: t(context).fromOffice, bg: w.infoBg, fg: w.infoFg),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (cor['concreteGrade'] != null) '${cor['concreteGrade']}',
              if (cor['supplierName'] != null) '${cor['supplierName']}',
              t(context).trucksCount(tm.length),
            ].join(' · '),
            style: TextStyle(color: w.muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          _Baris(t(context).volumeUsed,
              volume == null ? '–' : '${_angka(volume)} m³'),
          _Baris(t(context).volumeTheoretical,
              teoritis == null ? '–' : '${_angka(teoritis)} m³'),
          if (lebih != null)
            _Baris(t(context).overusePercent, '${_angka(lebih, 1)}%',
                warna: lebih > 25 ? w.badFg : (lebih > 10 ? w.warnFg : null)),
          if (h['mulaiCor'] != null)
            _Baris(t(context).castStartEnd,
                '${formatTime(DateTime.parse('${h['mulaiCor']}'))} – '
                '${h['selesaiCor'] == null ? '…' : formatTime(DateTime.parse('${h['selesaiCor']}'))}'),
          if (tm.isNotEmpty) ...[
            const Divider(height: 22),
            for (final t0 in tm)
              _BarisTm(tm: t0, hitung: perTm[toIntOrNull(t0['seq']) ?? 0]),
          ],
          if ((toIntOrNull(tremie['jumlahSegmen']) ?? 0) > 0) ...[
            const Divider(height: 22),
            _SusunanTremie(ringkas: tremie),
          ],
          if (cor['note'] != null && '${cor['note']}'.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('${cor['note']}', style: TextStyle(color: w.muted, fontSize: 13, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

/// Satu TM di dalam kartu log cor.
class _BarisTm extends StatelessWidget {
  const _BarisTm({required this.tm, this.hitung});

  final Map<String, Object?> tm;

  /// Baris `perTm` dari server untuk TM ini, bila ada: tertanamnya ujung
  /// tremie dihitung di SANA, bukan di sini. Dua tempat yang menghitungnya
  /// sendiri-sendiri akan berselisih justru pada log yang sudah dikoreksi
  /// kantor — dan yang memeriksa tidak punya cara tahu mana yang benar.
  final Map<String, Object?>? hitung;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final mulai = tm['startAt'] == null ? null : DateTime.tryParse('${tm['startAt']}');
    final selesai = tm['endAt'] == null ? null : DateTime.tryParse('${tm['endAt']}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Text('TM ${tm['seq']}',
                style: TextStyle(fontWeight: FontWeight.w700, color: w.brandStrong, fontSize: 13)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (tm['volumeM3'] != null) '${_angka(toDoubleOrNull(tm['volumeM3']) ?? 0, 2)} m³',
                    if (tm['slumpCm'] != null) t(context).slumpOf(_angka(toDoubleOrNull(tm['slumpCm']) ?? 0, 1)),
                    if (tm['truckNo'] != null) '${tm['truckNo']}',
                  ].join(' · '),
                  style: TextStyle(color: w.ink, fontWeight: FontWeight.w600),
                ),
                if (mulai != null)
                  Text(
                    '${formatTime(mulai)} – ${selesai == null ? '…' : formatTime(selesai)}',
                    style: TextStyle(color: w.muted, fontSize: 13),
                  ),
                if (hitung != null) _Tertanam(hitung: hitung!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu log bor: ringkasan, kurva kedalaman vs waktu, lalu bacaannya.
///
/// Bentuknya SAMA dengan dialog riwayat di web — angka ringkasan di atas,
/// kurva, lalu daftar bacaan. Yang memeriksa membaca dua layar itu
/// bergantian untuk titik yang sama; dua susunan yang berbeda memaksanya
/// mencari ulang tiap kali ia berpindah.
class _KartuBor extends StatelessWidget {
  const _KartuBor({required this.log});

  final Map<String, Object?> log;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final bacaan = [
      for (final e in (log['entries'] as List?) ?? const [])
        (e as Map).cast<String, Object?>(),
    ];
    final titik = titikKurvaBor(bacaan);
    final ringkas = ringkasBor(bacaan);
    final baris = barisBacaan(bacaan);
    final dihapus = log['isDelete'] == true || log['isDelete'] == 1;
    final selesai = '${log['status']}' == 'selesai';

    return ListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  log['date'] == null ? '-' : longDate(DateTime.parse('${log['date']}')),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: w.ink),
                ),
              ),
              if (dihapus)
                StatusBadge(text: t(context).deletedLabel, bg: w.badBg, fg: w.badFg)
              else if (selesai)
                StatusBadge(text: t(context).statusDone, bg: w.okBg, fg: w.okFg)
              else
                StatusBadge(text: t(context).stageDrilling, bg: w.warnBg, fg: w.warnFg),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (log['operatorName'] != null) t(context).operatorShort('${log['operatorName']}'),
              if (log['groundLevel'] != null)
                'GS ${_angka(toDoubleOrNull(log['groundLevel']) ?? 0, 3)}',
              t(context).readingsCount(ringkas.jumlahBacaan),
            ].join(' · '),
            style: TextStyle(color: w.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          // Kurvanya butuh sedikitnya dua bacaan yang dapat digambar. Dengan
          // satu bacaan yang tergambar hanyalah satu titik, dan sumbu
          // waktunya tidak punya rentang sama sekali.
          if (titik.length >= 2)
            KurvaBor(titik: titik, ringkas: ringkas)
          else
            Text(t(context).curveNeedsTwo, style: TextStyle(color: w.faint, fontSize: 13)),
          if (baris.isNotEmpty) ...[
            const Divider(height: 22),
            for (final b in baris) _BarisBacaanBor(baris: b),
          ],
          if (log['note'] != null && '${log['note']}'.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('${log['note']}',
                style: TextStyle(color: w.muted, fontSize: 13, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

/// Satu bacaan kedalaman.
///
/// Bacaan yang JAM atau kedalamannya tidak terbaca tetap ditampilkan, dengan
/// warna galat. Dibuang dari daftar ini, ia tidak muncul di layar mana pun —
/// sehingga tidak ada yang dapat membetulkannya, dan kedalaman akhir titik
/// itu diam-diam tetap salah.
class _BarisBacaanBor extends StatelessWidget {
  const _BarisBacaanBor({required this.baris});

  final BarisBacaan baris;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    if (!baris.tergambar) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 15, color: w.badFg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(t(context).readingUnreadable,
                  style: TextStyle(color: w.badFg, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }
    final jam = DateTime.fromMillisecondsSinceEpoch(baris.waktu!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Text(formatTime(jam),
                style: TextStyle(fontWeight: FontWeight.w700, color: w.brandStrong, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              [
                formatMeters(baris.dalam),
                if (baris.deltaM != null) '+${_angka(baris.deltaM!)} m',
                if (baris.lajuMPerJam != null)
                  t(context).metresPerHour(_angka(baris.lajuMPerJam!, 1)),
              ].join(' · '),
              style: TextStyle(color: w.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Jejak koreksi yang dapat DIBENTANGKAN, tertutup sejak awal.
///
/// Sama dengan panel jejak di web. Dibentangkan sejak awal, lima puluh baris
/// audit mendorong angka-angka yang justru sedang dicari ke bawah layar —
/// dan jejaknya hanya dibuka ketika ada yang dipertanyakan.
class _JejakLipat extends StatefulWidget {
  const _JejakLipat({required this.jejak});

  final List<Map<String, Object?>> jejak;

  @override
  State<_JejakLipat> createState() => _JejakLipatState();
}

class _JejakLipatState extends State<_JejakLipat> {
  bool _terbuka = false;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _terbuka = !_terbuka),
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t(context).pointHistoryTrail,
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 17, color: w.ink)),
                      Text(t(context).trailCount(widget.jejak.length),
                          style: TextStyle(color: w.muted, fontSize: 13)),
                    ],
                  ),
                ),
                Icon(_terbuka ? Icons.expand_less : Icons.expand_more, color: w.muted),
              ],
            ),
          ),
        ),
        if (_terbuka)
          for (final j in widget.jejak) _BarisJejak(jejak: j),
      ],
    );
  }
}

/// Satu baris jejak audit.
class _BarisJejak extends StatelessWidget {
  const _BarisJejak({required this.jejak});

  final Map<String, Object?> jejak;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final kapan = jejak['createdAt'] == null ? null : DateTime.tryParse('${jejak['createdAt']}');
    final siapa = jejak['actorName']?.toString() ?? jejak['userName']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history, size: 15, color: w.faint),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    ?siapa,
                    if (kapan != null) '${longDate(kapan)} ${formatTime(kapan)}',
                  ].join(' · '),
                  style: TextStyle(fontWeight: FontWeight.w600, color: w.ink),
                ),
                if (jejak['note'] != null)
                  Text('${jejak['note']}', style: TextStyle(color: w.muted, fontSize: 13, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tertanamnya ujung bawah tremie, sebelum dan sesudah satu TM.
///
/// Dua baris label-nilai seperti di kartu TM pada form cor, bukan bentuk
/// sendiri: yang memeriksa membaca dua layar itu bergantian.
///
/// Diwarnai, bukan hanya ditulis — yang memeriksa sedang menyisir puluhan TM
/// dan tidak akan membandingkan tiap angka dengan ambang di kepalanya.
class _Tertanam extends StatelessWidget {
  const _Tertanam({required this.hitung});

  final Map<String, Object?> hitung;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final awal = toDoubleOrNull(hitung['terbenamAwalM']);
    final akhir = toDoubleOrNull(hitung['terbenamAkhirM']);
    if (awal == null && akhir == null) return const SizedBox.shrink();
    final warna = switch (hitung['terbenamStatus']?.toString()) {
      'kurang' => w.badFg,
      'lebih' => w.warnFg,
      _ => null,
    };
    return Column(
      children: [
        if (awal != null)
          _Baris(t(context).embedBeforeLabel, '${_angka(awal)} m', warna: warna),
        if (akhir != null)
          _Baris(t(context).embedAfterLabel, '${_angka(akhir)} m', warna: warna),
      ],
    );
  }
}

/// Susunan tremie satu log cor: berapa batang, panjang masing-masing, dan
/// yang mana sudah dicabut setelah TM ke berapa.
///
/// Angka "Tremie terpasang 28,3 m" saja tidak dapat dibantah maupun
/// dibenarkan oleh siapa pun yang tidak ada di lokasi. Susunannya bisa.
class _SusunanTremie extends StatelessWidget {
  const _SusunanTremie({required this.ringkas});

  final Map<String, Object?> ringkas;

  @override
  Widget build(BuildContext context) {
    final segmen = ((ringkas['segmen'] as List?) ?? const [])
        .map((x) => (x as Map).cast<String, Object?>())
        .toList();
    final jarak = toDoubleOrNull(ringkas['jarakBottomM']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _JudulBagian(
          t(context).tremieSection,
          t(context).tremieSummary(
            segmen.length,
            _angka(toDoubleOrNull(ringkas['totalPanjangM']) ?? 0, 1),
            jarak == null ? '-' : '${_angka(jarak, 2)} m',
          ),
        ),
        // Dari paling bawah ke atas, sama dengan urutan pemasangannya di
        // lapangan — supaya yang membaca dapat mencocokkannya dengan apa
        // yang ia ingat menyusunnya.
        for (final sg in segmen)
          _Baris(
            [
              '#${sg['posisi']}',
              if (sg['jenis'] == 'bottom') t(context).tremieBottomTitle,
            ].join(' · '),
            [
              '${_angka(toDoubleOrNull(sg['panjangM']) ?? 0, 1)} m',
              sg['dicabutSetelahTm'] == null
                  ? t(context).tremieStillFitted
                  : t(context).tremiePulledAfter(toIntOrNull(sg['dicabutSetelahTm']) ?? 0),
            ].join(' · '),
          ),
      ],
    );
  }
}

/// Baris label-nilai. Gayanya DISALIN dari `value()` di `casting_form.dart`
/// — padding, ukuran, dan tebalnya sama persis, supaya layar ini tidak
/// terbaca sebagai aplikasi lain.
class _Baris extends StatelessWidget {
  const _Baris(this.label, this.value, {this.warna});

  final String label;
  final String value;
  final Color? warna;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: w.muted, fontSize: 13))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: warna ?? w.ink)),
        ],
      ),
    );
  }
}

/// Judul bagian. Gayanya DISALIN dari `_SectionTitle` di `casting_form.dart`;
/// bedanya hanya `body` boleh kosong, sebab tidak setiap bagian di sini
/// punya kalimat penjelas.
class _JudulBagian extends StatelessWidget {
  const _JudulBagian(this.title, [this.body]);

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: w.ink)),
          if (body != null) Text(body!, style: TextStyle(color: w.muted, fontSize: 13)),
        ],
      ),
    );
  }
}

String _angka(double v, [int d = 2]) => v.toStringAsFixed(d).replaceAll('.', ',');
