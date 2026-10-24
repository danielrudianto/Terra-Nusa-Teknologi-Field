import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/device/drill_snooze.dart';
import '../../core/device/notifications.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';
import '../../core/util/app_log.dart';
import '../../core/util/decimal_input.dart';
import '../../core/util/format.dart';
import '../../core/util/reasons.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/blocked_action.dart';
import '../../core/widgets/confirm.dart';
import '../../core/widgets/time_wheel.dart';
import '../../core/widgets/view_states.dart';
import '../casting/handover.dart';
import '../casting/level_reference.dart';
import 'drill_readings.dart';
import 'koordinat_aktual.dart';
import 'operator_picker.dart';
import '../../core/i18n.dart';

/// Drill log of one pile point: "at this time the hole was this deep".
///
/// No stopwatch: the drilling crew taps "Catat kedalaman" whenever the
/// depth is read off the kelly bar, and the time is filled in for them.
/// "Selesai bor" marks the point drilled with the deepest reading, which is
/// what the casting log measures from.
class DrillLogPage extends ConsumerStatefulWidget {
  const DrillLogPage({super.key, required this.uuid, this.pilePointUuid});

  final String uuid;
  final String? pilePointUuid;

  @override
  ConsumerState<DrillLogPage> createState() => _DrillLogPageState();
}

class _DrillLogPageState extends ConsumerState<DrillLogPage> {
  Map<String, Object?>? _doc;
  Map<String, Object?>? _pilePoint;
  DocumentRow? _row;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final row = await db.getDocument(widget.uuid);
    Map<String, Object?>? doc;
    var pilePointUuid = widget.pilePointUuid;
    if (row != null) {
      doc = (jsonDecode(row.body) as Map).cast<String, Object?>();
      pilePointUuid = '${doc['pilePointUuid']}';
    }
    if (pilePointUuid == null) {
      setState(() => _error = t(context).drillLogNotOnPhone);
      return;
    }
    final point = await db.getMaster('pile_point', pilePointUuid);
    if (point == null) {
      setState(() => _error = t(context).pointNotFoundPull);
      return;
    }
    if (doc == null) {
      // One point, one drill log: the server refuses a second one.
      final existing = point['drillLogUuid'];
      if (existing != null && '$existing' != widget.uuid) {
        setState(() => _error = t(context).pointHasDrillLog(
              '${point['code']}',
              point['drillLogByName'] == null ? '' : t(context).byWhom('${point['drillLogByName']}'),
            ));
        return;
      }
      if (point['status'] == 'sudah_cor') {
        setState(() => _error = t(context).pointAlreadyCast('${point['code']}'));
        return;
      }
      // Not saved until the first reading, so opening and leaving again
      // leaves nothing behind in the send queue.
      // The operator of the last log on this phone: usually the same rig crew.
      final u = ref.read(userProvider);
      final lastOperator = u == null ? null : await db.readMeta('lastOperator:${u.id}');
      doc = {
        'pilePointUuid': pilePointUuid,
        'date': isoDate(DateTime.now()),
        'status': 'berjalan',
        'groundLevel': null,
        'operatorUuid': lastOperator,
        'note': null,
        'entries': <Object?>[],
      };
    }
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _pilePoint = point;
      _row = row;
    });
    // Koreksi GS dilakukan sesaat SEBELUM bor dimulai, bukan sesudahnya.
    // Sebelum ini GS baru diminta di dialog "Selesai bor", sehingga sepanjang
    // pengeboran panjang bor rencana (GS − tip) tidak ada di layar — persis
    // saat operator membutuhkannya — dan GS diketik dari ingatan berjam-jam
    // kemudian. Satu GS yang meleset menggeser semua turunannya: panjang bor
    // rencana, kedalaman cut-off, volume teoritis, lalu overbreak.
    // Titik terkonfirmasi tidak dimintai GS: tidak ada yang boleh ditulis
    // lagi di situ, jadi dialognya cuma menghalangi orang membaca.
    if (_groundLevel == null &&
        !_finished &&
        !_handedAway &&
        _pilePoint!['checkedAt'] == null &&
        _pilePoint!['status'] != 'sudah_cor') {
      await _mintaGs(pertamaKali: true);
    }
    // Handed over: the colleague's phone buzzes now, not this one.
    if (_handedAway) {
      try {
        await Notifications.cancelDrillIdleReminders(widget.uuid);
      } catch (e) {
        // Dicatat, tidak ditampilkan: log ini sudah dioper, dan yang
        // mengopernya tidak sedang menunggu apa pun dari layar ini.
        // Bila pembatalannya gagal, akibatnya pengingat yang masih
        // berbunyi untuk log milik orang lain — menjengkelkan, tetapi
        // tidak dapat ditindaklanjuti dari sini. Catatannya yang
        // membuatnya dapat ditelusuri.
        AppLog.error('pengingat', e);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Derived
  // -------------------------------------------------------------------------

  List<DrillReading> get _readings => readingsOf(_doc);
  bool get _finished => _doc!['status'] == 'selesai';
  String get _code => '${_pilePoint!['code']}';

  /// Handed over (Oper): the server names someone else as holder of THIS log,
  /// so this phone only looks on — its pushes would be refused (DIOPER).
  ///
  /// The holder on the point describes the drill log the SERVER has for that
  /// point. If that is not this document, it says NOTHING about this log —
  /// reading it as a handover would lock a normal log read-only and make every
  /// save do nothing.
  bool get _handedAway {
    if (_row == null) return false;
    final serverUuid = _pilePoint?['drillLogUuid'];
    if (serverUuid == null || '$serverUuid' != widget.uuid) return false;
    final holder = toIntOrNull(_pilePoint?['drillLogHolderID']);
    final me = ref.read(userProvider)?.id;
    return holder != null && me != null && holder != me;
  }

  String? get _holderName => _pilePoint?['drillLogHolderName']?.toString();

  /// Rekan yang sedang menunggu jawaban atas permintaan opernya, bila ada dan
  /// bila log ini memang dipegang HP ini.
  String? get _peminta {
    if (_handedAway) return null;
    final siapa = toIntOrNull(_pilePoint?['drillLogRequestBy']);
    final me = ref.read(userProvider)?.id;
    if (siapa == null || me == null || siapa == me) return null;
    return _pilePoint?['drillLogRequestName']?.toString() ?? t(context).colleague;
  }

  /// Setujui atau tolak. Disetujui = log ini bukan milik HP ini lagi, jadi
  /// layarnya ditutup — membiarkannya terbuka berarti orangnya terus mencatat
  /// ke log yang setiap simpanannya akan ditolak server.
  Future<void> _jawabOper(bool setuju) async {
    final siapa = _peminta;
    if (siapa == null) return;
    final pindah = await answerHandoverFlow(
      context,
      ref,
      entity: 'drill_log',
      uuid: widget.uuid,
      pointCode: _code,
      requesterName: siapa,
      agree: setuju,
    );
    if (!mounted) return;
    if (pindah) {
      context.pop();
    } else {
      await _load();
    }
  }

  /// GS: the one entered in this log, else the point's.
  double? get _groundLevel => toDoubleOrNull(_doc!['groundLevel']) ?? toDoubleOrNull(_pilePoint!['groundLevel']);

  /// Planned drill length GS − tip; null while GS is unknown.
  double? get _plannedM {
    final gs = _groundLevel;
    final tip = toDoubleOrNull(_pilePoint!['tipLevel']);
    return gs == null || tip == null ? null : gs - tip;
  }

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  /// Buzz when this log goes 45 minutes without a new reading; nothing once it
  /// is finished. A reminder must never break a save.
  Future<void> _updateIdleReminder() async {
    try {
      final readings = _readings;
      if (_finished || readings.isEmpty) {
        await Notifications.cancelDrillIdleReminders(widget.uuid);
        return;
      }
      final newest = readings.map((r) => r.at).reduce((a, b) => a.isAfter(b) ? a : b);
      // Penundaan "sampai besok" tetap berlaku walau bacaan baru disimpan.
      //
      // Yang menekannya menyatakan "jangan ganggu saya sampai besok", bukan
      // "sampai saya menyentuh log ini lagi" — dan mencatat satu bacaan di
      // sela istirahat tidak membatalkan istirahatnya.
      final tunda = DrillSnooze.decode(await ref.read(dbProvider).readMeta('drill_snooze'));
      final kini = DateTime.now();
      await Notifications.scheduleDrillIdleReminders(
        logUuid: widget.uuid,
        pointCode: _code,
        lastReadingAt: newest,
        snoozeUntil: (tunda != null && tunda.menunda(kini)) ? tunda.until : null,
      );
    } catch (e, st) {
      // DICATAT — ini jaring pengamannya sendiri yang gagal.
      //
      // Penjadwalan inilah yang membuat pengingat jam 7 pagi berbunyi
      // untuk log bor yang belum ditutup. Gagal diam-diam, jaring itu
      // hilang tanpa satu pun tanda: layarnya tetap terlihat normal,
      // pengingatnya tidak pernah datang, dan yang lupa menutup lognya
      // baru tahu berhari-hari kemudian.
      //
      // Tidak dimunculkan ke layar: yang sedang mengebor tidak dapat
      // berbuat apa pun atas kegagalan penjadwalan, dan dialog di tengah
      // pencatatan kedalaman lebih berbahaya daripada pengingat yang
      // hilang. Catatannya yang membuatnya dapat ditemukan.
      AppLog.error('pengingat', e, st);
    }
  }

  /// Change and save the log. Returns FALSE when nothing was written, so a
  /// caller never reports success over unchanged data.
  Future<bool> _update(void Function(Map<String, Object?> d) f) async {
    if (_handedAway) {
      if (mounted) _snack(t(context).drillHeldByOther(_holderName ?? t(context).colleague));
      return false;
    }
    final p = ref.read(userProvider);
    if (p == null) {
      if (mounted) _snack(t(context).notSignedIn);
      return false;
    }
    setState(() => f(_doc!));
    final db = ref.read(dbProvider);
    await db.saveDocument(uuid: widget.uuid, entity: 'drill_log', userId: p.id, body: _doc!);
    _row = await db.getDocument(widget.uuid);
    ref.read(syncProvider.notifier).afterSave();
    await _updateIdleReminder();
    if (mounted) setState(() {});
    return true;
  }

  List<Map<String, Object?>> get _entries =>
      [for (final e in (_doc!['entries'] as List?) ?? const []) (e as Map).cast<String, Object?>()];

  String? get _operatorUuid => _doc!['operatorUuid']?.toString();

  /// Choose (or change) the rig operator. Remembered on this phone as the
  /// default for the next log.
  /// Minta atau koreksi GS titik ini.
  ///
  /// [pertamaKali] = konfirmasi wajib sebelum bor: dibatalkan berarti keluar
  /// dari log, sebab mengebor tanpa GS menghasilkan catatan yang tidak bisa
  /// dihitung dan log cornya pun ditolak server.
  ///
  /// Tidak disimpan ke antrean selama log ini belum punya pembacaan: membuka
  /// lalu menutup log tidak boleh meninggalkan apa pun (lihat `_load`).
  Future<void> _mintaGs({bool pertamaKali = false}) async {
    final gs = await showDialog<double>(
      context: context,
      barrierDismissible: !pertamaKali,
      builder: (_) => _GsSheet(
        code: _code,
        pertamaKali: pertamaKali,
        tipLevel: toDoubleOrNull(_pilePoint!['tipLevel']),
        cutOffLevel: toDoubleOrNull(_pilePoint!['cutOffLevel']),
        groundLevel: _groundLevel,
      ),
    );
    if (gs == null) {
      if (pertamaKali && mounted) context.pop();
      return;
    }
    final teks = decimalText(gs, decimals: 3);
    if (_row == null) {
      setState(() => _doc!['groundLevel'] = teks);
    } else {
      await _update((d) => d['groundLevel'] = teks);
    }
  }

  Future<bool> _chooseOperator() async {
    final picked = await pickOperator(context, current: _operatorUuid);
    if (picked == null) return false;
    final u = ref.read(userProvider);
    if (u != null) await ref.read(dbProvider).writeMeta('lastOperator:${u.id}', picked);
    if (_readings.isEmpty) {
      // Nothing saved yet: keep it unsaved until the first reading.
      setState(() => _doc!['operatorUuid'] = picked);
    } else {
      if (!await _update((d) => d['operatorUuid'] = picked)) return false;
      if (mounted) _snack(t(context).operatorSaved);
    }
    return true;
  }

  Future<void> _addOrEdit([DrillReading? editing]) async {
    // Who drilled it is part of the record (weekly metres per operator):
    // asked before the first reading, not forgotten until the end.
    if (_operatorUuid == null && !await _chooseOperator()) return;
    if (!mounted) return;
    final result = await showModalBottomSheet<_ReadingResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReadingSheet(readings: _readings, editing: editing, plannedM: _plannedM),
    );
    if (result == null) return;
    final saved = await _update((d) {
      final list = _entries;
      if (editing != null) list.removeWhere((e) => e['uuid'] == editing.uuid);
      if (!result.delete) {
        list.add({
          'uuid': editing?.uuid ?? newUuid(),
          'at': isoWithOffset(result.at),
          'depthM': decimalText(result.depthM),
          'note': result.note,
        });
      }
      d['entries'] = list;
    });
    if (!saved || !mounted) return;
    _snack(result.delete
        ? t(context).readingDeleted
        : t(context).readingRecorded(formatMeters(result.depthM), formatTime(result.at)));
  }

  /// Toleransi simpangan proyek titik ini, dalam milimeter. `null` = tidak
  /// diketahui, dan tidak ada yang dinyatakan di luar batas ketika tidak
  /// diketahui.
  double? get _toleranceMm {
    final id = _pilePoint?['projectID'];
    final p = (ref.read(projectsProvider).value ?? const [])
        .where((e) => '${e['id']}' == '$id')
        .firstOrNull;
    return toDoubleOrNull(p?['pileToleranceMm']);
  }

  /// Nilai AWAL isian koordinat — ikut berkelompok ribuan, sama dengan
  /// yang dihasilkan `KoordinatInputFormatter` saat diketik. Dibiarkan
  /// polos, angka yang sudah tersimpan tampil berbeda dari angka yang baru
  /// diketik di isian yang sama.
  static String _koordText(double? v) => v == null ? '' : formatKoordinat(v);

  Future<void> _finish() async {
    if (_operatorUuid == null && !await _chooseOperator()) return;
    if (!mounted) return;
    final readings = _readings;
    final deepest = deepestM(readings);
    if (deepest == null) return;
    final aktualX = toDoubleOrNull(_pilePoint!['actualX']);
    final aktualY = toDoubleOrNull(_pilePoint!['actualY']);
    final result = await showDialog<({double? groundLevel, double? actualX, double? actualY})>(
      context: context,
      builder: (_) => _FinishDialog(
        code: _code,
        deepestM: deepest,
        plannedM: _plannedM,
        gsRequired: _groundLevel == null,
        tipLevel: toDoubleOrNull(_pilePoint!['tipLevel']),
        cutOffLevel: toDoubleOrNull(_pilePoint!['cutOffLevel']),
        groundLevel: _groundLevel,
        initialX: _koordText(aktualX),
        initialY: _koordText(aktualY),
        xyRequired: aktualX == null || aktualY == null,
        designX: toDoubleOrNull(_pilePoint!['designX']),
        designY: toDoubleOrNull(_pilePoint!['designY']),
        toleranceMm: _toleranceMm,
      ),
    );
    if (result == null) return;
    final saved = await _update((d) {
      d['status'] = 'selesai';
      if (result.groundLevel != null) d['groundLevel'] = decimalText(result.groundLevel!, decimals: 3);
      // Hanya bila ADA ISINYA: kunci kosong membuat jejak auditnya mencatat
      // koordinat "berubah" pada penutupan yang tidak menyentuhnya.
      if (result.actualX != null) d['actualX'] = decimalText(result.actualX!, decimals: 3);
      if (result.actualY != null) d['actualY'] = decimalText(result.actualY!, decimals: 3);
    });
    // Read it back: "selesai dibor" must never be announced over a log that
    // is still running.
    if (!saved) return;
    final stored = await ref.read(dbProvider).getDocument(widget.uuid);
    if (stored == null || (jsonDecode(stored.body) as Map)['status'] != 'selesai') {
      if (mounted) _snack(t(context).drillFinishNotStored);
      return;
    }
    if (!mounted) return;
    _snack(t(context).drillFinished(_code, formatMeters(deepest)));
  }

  Future<void> _reopen() async {
    final l = t(context);
    // Membuka log yang SUDAH ditutup, tanpa ditanya apa pun, hanya dari satu
    // ketukan pada tombol teks di dalam banner hijau — persis tempat jempol
    // mendarat setelah membaca "Sudah dibor sampai 22,00 m". Log bor adalah
    // bukti; yang membukanya kembali harus menyatakan niatnya.
    if (!await askConfirm(
      context,
      icon: Icons.lock_open_outlined,
      title: l.drillReopenConfirmTitle,
      body: l.drillReopenConfirmBody,
      confirmLabel: l.reopen,
    )) {
      return;
    }
    if (!mounted) return;
    if (!await _update((d) => d['status'] = 'berjalan')) return;
    _snack(l.drillReopened);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(appBar: AppBar(title: Text(t(context).entityDrillLog)), body: ErrorState(title: _error!));
    }
    if (_doc == null) return const Scaffold(body: LoadingState());
    final w = context.colors;
    final readings = _readings;
    final cast = _pilePoint!['status'] == 'sudah_cor';
    // Titik yang sudah dikonfirmasi kantor: server menolak setiap kiriman
    // untuk log bor ini (TITIK_DIKONFIRMASI), jadi layarnya hanya dibaca.
    final dikonfirmasi = _pilePoint!['checkedAt'] != null;
    // Tanpa GS tidak ada yang boleh dicatat: itulah arti "GS wajib dulu".
    final canEdit = !_finished && !cast && !dikonfirmasi && !_handedAway && _groundLevel != null;
    /*
     * MENUTUP log boleh walau titiknya sudah dicor. MENAMBAH bacaan tidak.
     *
     * Sampai 15 Okt 2026 keduanya memakai `canEdit` yang sama, dan itu
     * menjebak: begitu titiknya dicor — dari HP lain, atau dari kantor —
     * tombol "Selesai bor" ikut mati, sedangkan dari kantor log bor yang
     * titiknya sudah punya log cor juga TIDAK boleh dihapus. Lognya
     * tertinggal terbuka selamanya, dan titiknya terbaca "sedang dibor"
     * padahal betonnya sudah mengeras. Kejadian di PP.B48.
     *
     * Bedanya masuk akal kalau dibaca sebagai pernyataan tentang lubang:
     * bacaan kedalaman BARU di lubang yang sudah terisi beton tidak mungkin
     * benar, sedangkan menutup catatan pengeboran yang memang sudah selesai
     * hanya merapikan yang sudah terjadi.
     *
     * Server menerima ini — `simpan_log_bor` menolak `SUDAH_DICOR` hanya
     * saat log DIBUAT, bukan saat diperbarui — dan tidak menurunkan status
     * titiknya: `if data.status == "selesai" and titik["status"] !=
     * "sudah_cor"`. Jadi titik yang sudah dicor tetap `sudah_cor`.
     *
     * Empat syarat lain tetap: server benar-benar menolak kiriman dari log
     * yang sudah ditutup, titik yang dikonfirmasi kantor, log yang sudah
     * dioper, dan penyelesaian tanpa GS (GS_KOSONG).
     */
    final canFinish = !_finished && !dikonfirmasi && !_handedAway && _groundLevel != null;
    final canOffer = _row != null && !_finished && !cast && !dikonfirmasi && !_handedAway;
    // SATU sebab, yang paling menentukan — tidak daftar.
    //
    // `canEdit` di atas digabung dari LIMA syarat, dan sampai 15 Okt 2026
    // tidak satu pun dari kelimanya pernah disebut: tombolnya sekadar mati.
    // Yang paling sering kena adalah dua yang paling tidak kelihatan —
    // kantor sudah mengonfirmasi titiknya, dan ground level belum diisi —
    // dan keduanya tidak ada hubungannya dengan apa pun yang terlihat di
    // layar ini. Urutannya dari yang paling permanen: yang sudah dicor tidak
    // bisa dibuka oleh siapa pun, yang belum ber-GS bisa diselesaikan
    // sendiri dalam satu ketukan.
    final String? halangan = cast
        ? t(context).blockedCast
        : dikonfirmasi
            ? t(context).blockedConfirmed
            : _handedAway
                ? t(context).handedOverTo(_holderName ?? t(context).colleague)
                : _groundLevel == null
                    ? t(context).blockedNeedGs
                    : null;
    /*
     * Sebab untuk tombol SELESAI — tanpa cabang "sudah dicor", sebab bagi
     * tombol itu dicor bukan lagi halangan. Memakai `halangan` yang sama
     * akan menerangkan tombol yang hidup dengan kalimat yang menyatakan ia
     * mati.
     */
    final String? halanganSelesai = dikonfirmasi
        ? t(context).blockedConfirmed
        : _handedAway
            ? t(context).handedOverTo(_holderName ?? t(context).colleague)
            : _groundLevel == null
                ? t(context).blockedNeedGs
                : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(t(context).drillOf(_code)),
        actions: [
          if (canOffer)
            IconButton(
              tooltip: t(context).handOverToMate,
              icon: const Icon(Icons.swap_horiz),
              onPressed: () => offerHandover(context, ref, entity: 'drill_log', uuid: widget.uuid, pointCode: _code),
            ),
          if (_row != null) Padding(padding: const EdgeInsets.only(right: 12), child: StatusBadge.sendStatus(context, _row!.sendStatus)),
        ],
      ),
      body: ListView(
        // The action buttons live in bottomNavigationBar, which the body already
        // ends above: no extra room needed under the last card.
        padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, Dimens.pagePadding, Dimens.pagePadding, 8),
        children: [
          if (_peminta != null)
            TerraBanner(
              kind: BannerKind.warning,
              icon: Icons.pan_tool_alt_outlined,
              title: t(context).handoverRequestTitle(_peminta!),
              body: t(context).handoverRequestPrompt(_peminta!, _code),
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: () => _jawabOper(false), child: Text(t(context).reject)),
                  const SizedBox(width: 4),
                  FilledButton(onPressed: () => _jawabOper(true), child: Text(t(context).approve)),
                ],
              ),
            ),
          if (_handedAway)
            TerraBanner(
              kind: BannerKind.info,
              icon: Icons.swap_horiz,
              title: t(context).handedOverTo(_holderName ?? t(context).colleague),
              body: t(context).drillHandedOverBody(_holderName ?? t(context).colleague),
            ),
          if (_row?.sendStatus == 'rejected' && !_handedAway)
            TerraBanner(kind: BannerKind.danger, title: t(context).rejectedByServer, body: reasonText(context, _row!.reason, _row!.detail)),
          // Terkunci dari LUAR layar ini. Keduanya mematikan setiap tombol
          // dan tidak meninggalkan jejak apa pun yang bisa dibaca: tanpa
          // banner ini, satu-satunya keterangan yang didapat pengguna adalah
          // bahwa aplikasinya tidak menanggapi.
          if (cast)
            TerraBanner(
              kind: BannerKind.info,
              icon: Icons.lock_outline,
              title: t(context).drillLockedCastTitle,
              body: t(context).drillLockedCastBody,
            )
          else if (dikonfirmasi)
            TerraBanner(
              kind: BannerKind.info,
              icon: Icons.verified_outlined,
              title: t(context).drillLockedConfirmedTitle,
              body: t(context).drillLockedConfirmedBody,
            ),
          _DepthHero(readings: readings, plannedM: _plannedM, diameterMm: toIntOrNull(_pilePoint!['diameterMm']), finished: _finished),
          _GsRow(
            groundLevel: _groundLevel,
            plannedM: _plannedM,
            onChange: _finished || cast || _handedAway ? null : () => _mintaGs(),
          ),
          // DI BAWAH barisnya, bukan di atas: isinya menyuruh mengetuk baris
          // itu, dan petunjuk yang menyebut "di atas" harus benar-benar ada
          // di bawah yang ditunjuknya.
          if (_groundLevel == null && !cast && !dikonfirmasi && !_handedAway)
            TerraBanner(
              kind: BannerKind.warning,
              icon: Icons.height,
              title: t(context).drillNeedGsTitle,
              body: t(context).drillNeedGsBody,
            ),
          _OperatorRow(uuid: _operatorUuid, onChange: canEdit ? _chooseOperator : null),
          if (_finished)
            TerraBanner(
              kind: BannerKind.ok,
              title: t(context).drilledToDepth(formatMeters(deepestM(readings))),
              body: t(context).drilledBodyOk,
              action: cast ? null : TextButton(onPressed: _reopen, child: Text(t(context).reopen)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: Row(
              children: [
                Expanded(child: Text(t(context).readingsSection, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: w.ink))),
                Text(t(context).readingsCount(readings.length), style: TextStyle(color: w.muted, fontSize: 13)),
              ],
            ),
          ),
          if (readings.isEmpty)
            EmptyState(message: t(context).noReadingsYet),
          // Newest first: the one just written is the one being looked at.
          for (var i = readings.length - 1; i >= 0; i--)
            _ReadingCard(
              reading: readings[i],
              previous: i == 0 ? null : readings[i - 1],
              onTap: canEdit ? () => _addOrEdit(readings[i]) : null,
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, 8, Dimens.pagePadding, 12),
          child: _finished
              ? SizedBox(
                  height: Dimens.minTouch + 4,
                  child: BlockedAction(
                    reason: cast ? t(context).blockedCast : null,
                    child: FilledButton.icon(
                      onPressed: cast
                          ? null
                          : () => context.pushReplacement('/casting/log/${newUuid()}?pilePoint=${_doc!['pilePointUuid']}'),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(t(context).startCastLog),
                    ),
                  ),
                )
              : Row(
                  children: [
                    if (readings.isNotEmpty) ...[
                      Expanded(
                        child: SizedBox(
                          height: Dimens.minTouch + 4,
                          child: BlockedAction(
                            reason: canFinish ? null : halanganSelesai,
                            child: OutlinedButton(onPressed: canFinish ? _finish : null, child: Text(t(context).finishDrilling)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: Dimens.minTouch + 4,
                        child: BlockedAction(
                          reason: canEdit ? null : halangan,
                          child: FilledButton.icon(
                            onPressed: canEdit ? () => _addOrEdit() : null,
                            icon: const Icon(Icons.add),
                            label: Text(t(context).recordDepth),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// GS titik ini berikut panjang bor rencana yang mengikutinya.
///
/// Sengaja sejajar dengan baris operator: dua hal yang dikonfirmasi sebelum
/// mata bor menyentuh tanah, dan dua-duanya bisa dibetulkan selama log masih
/// terbuka — surveyor kadang merevisi tembakannya.
class _GsRow extends StatelessWidget {
  const _GsRow({required this.groundLevel, required this.plannedM, required this.onChange});

  final double? groundLevel;
  final double? plannedM;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final gs = groundLevel;
    return ListCard(
      onTap: onChange == null ? null : () async => onChange!(),
      child: Row(
        children: [
          Icon(Icons.height, color: gs == null ? w.warnFg : w.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t(context).gsRowLabel,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: w.faint)),
                Text(gs == null ? t(context).notSet : formatElevation(gs),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: gs == null ? w.warnFg : w.ink)),
                if (plannedM != null)
                  Text(t(context).plannedDrillOf(formatMeters(plannedM!)),
                      style: TextStyle(color: w.muted, fontSize: 13)),
              ],
            ),
          ),
          if (onChange != null)
            Text(gs == null ? t(context).fill : t(context).correct,
                style: TextStyle(color: w.brand, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Konfirmasi GS sebelum bor, dan koreksinya di kemudian hari.
class _GsSheet extends StatefulWidget {
  const _GsSheet({
    required this.code,
    required this.pertamaKali,
    required this.tipLevel,
    required this.cutOffLevel,
    required this.groundLevel,
  });

  final String code;
  final bool pertamaKali;
  final double? tipLevel;
  final double? cutOffLevel;
  final double? groundLevel;

  @override
  State<_GsSheet> createState() => _GsSheetState();
}

class _GsSheetState extends State<_GsSheet> {
  late final _gs = TextEditingController(
      text: widget.groundLevel == null ? '' : formatElevation(widget.groundLevel!, decimals: 3).replaceAll('+', ''));
  String? _problem;

  @override
  void dispose() {
    _gs.dispose();
    super.dispose();
  }

  double? get _diketik => parseNumber(_gs.text);

  void _submit() {
    final gs = _diketik;
    if (gs == null || gs < -500 || gs > 5000) {
      setState(() => _problem = t(context).gsRequiredMsg);
      return;
    }
    Navigator.pop(context, gs);
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final gs = _diketik;
    final col = widget.cutOffLevel;
    // Cut-off di ATAS muka tanah: bukan penghalang — kadang memang begitu —
    // tetapi hampir selalu tanda GS salah ketik, jadi harus terbaca sekarang.
    final colDiAtas = gs != null && col != null && col > gs;
    return AlertDialog(
      icon: Icon(Icons.height, size: 32, color: w.brand),
      title: Text(widget.pertamaKali ? t(context).confirmBeforeDrilling(widget.code) : t(context).correctGsTitle,
          textAlign: TextAlign.center),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.pertamaKali ? t(context).confirmBeforeDrillingBody : t(context).correctGsBody,
                style: TextStyle(color: w.ink, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: _gs,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: decimalInput(maxIntDigits: 4, decimals: 3, signed: true),
              decoration: InputDecoration(labelText: t(context).gsFieldRequired, suffixText: 'm'),
              onChanged: (_) => setState(() => _problem = null),
            ),
            const SizedBox(height: 12),
            // Angka turunannya ikut berubah sambil diketik: salah ketik satu
            // digit langsung terlihat sebagai panjang bor yang mustahil.
            LevelReferenceBanner(cutOffLevel: col, tipLevel: widget.tipLevel, groundLevel: gs),
            if (colDiAtas) ...[
              const SizedBox(height: 8),
              TerraBanner(
                kind: BannerKind.warning,
                title: t(context).cutOffAboveGsTitle,
                body: t(context).cutOffAboveGsBody(formatElevation(col)),
              ),
            ],
            if (_problem != null) ...[
              const SizedBox(height: 8),
              TerraBanner(kind: BannerKind.danger, title: t(context).checkInput, body: _problem),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.pertamaKali ? t(context).backOut : t(context).cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(t(context).save)),
      ],
    );
  }
}

/// The rig operator of this log, with "Ganti" while it is still open.
class _OperatorRow extends ConsumerWidget {
  const _OperatorRow({required this.uuid, required this.onChange});

  final String? uuid;
  final Future<bool> Function()? onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final name = (ref.watch(workersProvider).value ?? const <Worker>[]).where((k) => k.uuid == uuid).firstOrNull?.name;
    return ListCard(
      onTap: onChange,
      child: Row(
        children: [
          Icon(Icons.engineering, color: name == null ? w.warnFg : w.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t(context).drillOperatorLabel, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: w.faint)),
                Text(name ?? t(context).notPicked, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: name == null ? w.warnFg : w.ink)),
              ],
            ),
          ),
          if (onChange != null) Text(name == null ? t(context).pick : t(context).change, style: TextStyle(color: w.brand, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Big current depth against the plan, like the tremie total.
class _DepthHero extends StatelessWidget {
  const _DepthHero({required this.readings, required this.plannedM, required this.diameterMm, required this.finished});

  final List<DrillReading> readings;
  final double? plannedM;
  final int? diameterMm;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final deepest = deepestM(readings) ?? 0;
    final planned = plannedM;
    final over = planned == null ? 0.0 : deepest - planned;
    final started = readings.isEmpty ? null : readings.first.at;
    final last = readings.isEmpty ? null : readings.last.at;
    return ListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(finished ? t(context).finalDepthLabel : t(context).currentDepthLabel,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: w.faint)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedFigure(formatMeters(deepest),
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: w.ink, height: 1)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(planned == null ? t(context).planNotComputable : t(context).ofPlanned(formatMeters(planned)),
                    style: TextStyle(color: w.muted, fontSize: 13)),
              ),
            ],
          ),
          if (planned != null && planned > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              // The bar fills to the new reading instead of teleporting, so a
              // 3 m jump looks like 3 m of drilling.
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: (deepest / planned).clamp(0.0, 1.0)),
                duration: Dimens.motionMedium,
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: w.line,
                  color: over > 0.005 ? w.warnFg : w.brand,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            [
              if (diameterMm != null) 'D$diameterMm',
              if (started != null) t(context).startedAt(formatTime(started)),
              if (started != null && last != null && last.isAfter(started))
                t(context).runningFor(_hoursMinutes(context, last.difference(started))),
              if (planned == null) t(context).gsMissingShort,
            ].join(' · '),
            style: TextStyle(color: w.muted, fontSize: 13),
          ),
          if (planned != null && over > 0.5)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(t(context).deeperThanPlan(formatMeters(over)),
                  style: TextStyle(color: w.warnFg, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

String _hoursMinutes(BuildContext context, Duration d) =>
    d.inHours > 0 ? t(context).hoursMinutes(d.inHours, d.inMinutes % 60) : t(context).minutesOnly(d.inMinutes);

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.reading, required this.previous, this.onTap});

  final DrillReading reading;
  final DrillReading? previous;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final p = previous;
    final progress = p == null
        ? null
        : t(context).depthGain(formatMeters(reading.depthM - p.depthM), _hoursMinutes(context, reading.at.difference(p.at)));
    return ListCard(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(formatTime(reading.at),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: w.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatMeters(reading.depthM), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: w.ink)),
                if (progress != null) Text(progress, style: TextStyle(color: w.muted, fontSize: 13)),
                if (reading.note != null) Text(reading.note!, style: TextStyle(color: w.ink, fontSize: 13)),
              ],
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right, color: w.faint),
        ],
      ),
    );
  }
}

class _ReadingResult {
  const _ReadingResult({required this.at, required this.depthM, this.note, this.delete = false});

  final DateTime at;
  final double depthM;
  final String? note;
  final bool delete;
}

/// Enter (or correct) one reading. Owns its text controllers.
class _ReadingSheet extends StatefulWidget {
  const _ReadingSheet({required this.readings, required this.editing, required this.plannedM});

  final List<DrillReading> readings;
  final DrillReading? editing;
  final double? plannedM;

  @override
  State<_ReadingSheet> createState() => _ReadingSheetState();
}

class _ReadingSheetState extends State<_ReadingSheet> {
  late DateTime _at = widget.editing?.at.toLocal() ?? DateTime.now();

  /// A new reading follows the clock until the time is changed by hand, so
  /// the minutes spent typing the depth do not make it stale: what is saved
  /// is the moment "Simpan" is pressed.
  late bool _followNow = widget.editing == null;

  Timer? _clock;

  @override
  void initState() {
    super.initState();
    if (_followNow) {
      _clock = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted && _followNow) setState(() => _at = DateTime.now());
      });
    }
  }
  late final _depth = TextEditingController(
    text: widget.editing == null ? '' : widget.editing!.depthM.toStringAsFixed(2).replaceAll('.', ','),
  );
  late final _note = TextEditingController(text: widget.editing?.note ?? '');
  String? _problem;

  @override
  void dispose() {
    _clock?.cancel();
    _depth.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimeWheel(context, initial: _followNow ? DateTime.now() : _at, title: t(context).readingTime);
    if (picked == null) return;
    final now = DateTime.now();
    setState(() {
      // Picking the current minute (e.g. "Sekarang") keeps following the clock.
      _followNow =
          widget.editing == null && picked.hour == now.hour && picked.minute == now.minute && picked.day == now.day;
      _at = _followNow ? now : picked;
      _problem = null;
    });
  }

  void _submit() {
    if (_followNow) _at = DateTime.now();
    final depth = parseNumber(_depth.text);
    if (depth == null || depth <= 0) {
      setState(() => _problem = t(context).depthInvalid);
      return;
    }
    if (depth > maxDrillDepthM) {
      setState(() => _problem = t(context).drillDepthTooDeep(formatMeters(maxDrillDepthM, decimals: 0)));
      return;
    }
    if (_at.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      setState(() => _problem = t(context).timeInFuture);
      return;
    }
    final wrong = readingProblem(widget.readings, _at, depth, replacing: widget.editing?.uuid);
    if (wrong != null) {
      setState(() => _problem = wrong);
      return;
    }
    final planned = widget.plannedM;
    if (planned != null && farBeyondPlan(depth, planned)) {
      setState(() => _problem = farBeyondPlanText(depth, planned));
      return;
    }
    final note = _note.text.trim();
    Navigator.pop(context, _ReadingResult(at: _at, depthM: depth, note: note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final last = widget.readings.isEmpty ? null : widget.readings.last;
    final typed = parseNumber(_depth.text);
    // A depth that can never be saved: red banner and a disabled button,
    // right while typing.
    final refusal = depthRefusal(typed, widget.plannedM);
    final problem = _problem ?? refusal;
    final overPlan = typed == null || refusal != null ? null : beyondPlanM(typed, widget.plannedM);
    return Padding(
      padding: sheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.editing == null ? t(context).recordDepth : t(context).editReading,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: w.ink)),
          Text(
            [
              if (widget.editing == null && last != null)
                t(context).lastReadingWas(formatMeters(last.depthM), formatTime(last.at)),
              if (widget.plannedM != null) t(context).plannedIs(formatMeters(widget.plannedM)),
            ].join(' · '),
            style: TextStyle(color: w.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (problem != null) TerraBanner(kind: BannerKind.danger, title: t(context).checkInput, body: problem),
          // The time is filled in; changing it is the exception.
          Material(
            color: w.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: w.border)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _pickTime,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.schedule, color: w.muted),
                    const SizedBox(width: 10),
                    Text(formatTime(_at),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: w.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                    if (_followNow) ...[
                      const SizedBox(width: 8),
                      Text(t(context).now, style: TextStyle(color: w.muted, fontWeight: FontWeight.w600)),
                    ],
                    const Spacer(),
                    Text(t(context).editTime, style: TextStyle(color: w.brand, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _depth,
            autofocus: widget.editing == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: decimalInput(maxIntDigits: 3),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: t(context).depthFromGs,
              suffixText: 'm',
            ),
            onChanged: (_) => setState(() => _problem = null),
            onSubmitted: (_) => _submit(),
          ),
          if (overPlan != null) ...[
            const SizedBox(height: 8),
            TerraBanner(
              kind: BannerKind.warning,
              title: t(context).beyondPlanTitle(formatMeters(overPlan)),
              body: t(context).beyondPlanBody(formatMeters(widget.plannedM)),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 255,
            decoration: InputDecoration(labelText: t(context).noteOptional, hintText: t(context).drillNoteHint),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: Dimens.minTouch + 4,
            child: FilledButton(onPressed: refusal == null ? _submit : null, child: Text(t(context).save)),
          ),
          if (widget.editing != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => Navigator.pop(
                context,
                _ReadingResult(at: widget.editing!.at, depthM: widget.editing!.depthM, delete: true),
              ),
              icon: Icon(Icons.delete_outline, color: w.badFg),
              label: Text(t(context).deleteThisReading, style: TextStyle(color: w.badFg)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Confirm finishing; asks GS when the point has none. Owns its controller.
class _FinishDialog extends StatefulWidget {
  const _FinishDialog({
    required this.code,
    required this.deepestM,
    required this.plannedM,
    required this.gsRequired,
    required this.tipLevel,
    required this.cutOffLevel,
    required this.groundLevel,
    required this.initialX,
    required this.initialY,
    required this.xyRequired,
    required this.designX,
    required this.designY,
    required this.toleranceMm,
  });

  final String code;
  final double deepestM;
  final double? plannedM;
  final bool gsRequired;
  final double? tipLevel;
  final double? cutOffLevel;

  /// Known GS of the point; null when it still has to be typed here.
  final double? groundLevel;

  final String initialX;
  final String initialY;
  final bool xyRequired;
  final double? designX;
  final double? designY;
  final double? toleranceMm;

  @override
  State<_FinishDialog> createState() => _FinishDialogState();
}

class _FinishDialogState extends State<_FinishDialog> {
  final _gs = TextEditingController();
  late final _xInput = TextEditingController(text: widget.initialX);
  late final _yInput = TextEditingController(text: widget.initialY);
  String? _problem;

  @override
  void dispose() {
    _gs.dispose();
    _xInput.dispose();
    _yInput.dispose();
    super.dispose();
  }

  double? get _planned {
    if (widget.plannedM != null) return widget.plannedM;
    final gs = parseNumber(_gs.text);
    return gs == null || widget.tipLevel == null ? null : gs - widget.tipLevel!;
  }

  Future<void> _submit() async {
    double? gs;
    if (widget.gsRequired) {
      gs = parseNumber(_gs.text);
      if (gs == null || gs < -500 || gs > 5000) {
        setState(() => _problem = t(context).gsRequiredMsg);
        return;
      }
    }
    final salahKoord = koordinatBelumSah(
      context,
      _xInput.text,
      _yInput.text,
      wajib: widget.xyRequired,
    );
    if (salahKoord != null) {
      setState(() => _problem = salahKoord);
      return;
    }
    // PERINGATAN KERAS simpangan — sesudah seluruh pemeriksaan lain lulus.
    //
    // Ditanya lebih awal, yang GS-nya masih salah ketik sudah terlanjur
    // menjawab pertanyaan berat soal simpangan, lalu harus menjawabnya
    // lagi sesudah membetulkan hal lain.
    if (!await lanjutkanMeskiSimpang(
      context,
      designX: widget.designX,
      designY: widget.designY,
      xText: _xInput.text,
      yText: _yInput.text,
      toleranceMm: widget.toleranceMm,
    )) {
      return;
    }
    // `mounted` MILIK STATE, bukan `context.mounted`.
    //
    // Keduanya tampak setara, tetapi penganalisis menolak yang kedua di
    // dalam `State`: yang menentukan boleh-tidaknya memakai `context`
    // sesudah `await` adalah hidup-matinya State-nya, dan `context.mounted`
    // menjawab pertanyaan yang berbeda.
    if (!mounted) return;
    Navigator.pop(context, (
      groundLevel: gs,
      actualX: parseKoordinat(_xInput.text),
      actualY: parseKoordinat(_yInput.text),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final planned = _planned;
    final short = planned == null ? 0.0 : planned - widget.deepestM;
    return AlertDialog(
      icon: Icon(Icons.flag_outlined, size: 32, color: w.brand),
      title: Text(t(context).finishDrillingOf(widget.code), textAlign: TextAlign.center),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t(context).finishDrillBody(formatMeters(widget.deepestM)),
                style: TextStyle(color: w.ink, height: 1.4)),
            if (short > 0.5) ...[
              const SizedBox(height: 10),
              TerraBanner(
                kind: BannerKind.warning,
                title: t(context).shallowerThanPlan(formatMeters(short)),
                body: t(context).shallowerBody(formatMeters(planned)),
              ),
            ],
            const SizedBox(height: 10),
            LevelReferenceBanner(
              cutOffLevel: widget.cutOffLevel,
              tipLevel: widget.tipLevel,
              groundLevel: widget.groundLevel ?? parseNumber(_gs.text),
            ),
            // Banner galat DI LUAR `if (gsRequired)`.
            //
            // Di dalamnya, titik yang GS-nya sudah ada tidak pernah
            // memperlihatkan galat koordinat: tombolnya ditekan, dialognya
            // tidak tertutup, dan tidak ada satu pun kalimat yang muncul.
            if (_problem != null) ...[
              const SizedBox(height: 8),
              TerraBanner(kind: BannerKind.danger, title: t(context).checkInput, body: _problem),
            ],
            if (widget.gsRequired) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _gs,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                inputFormatters: decimalInput(maxIntDigits: 4, decimals: 3, signed: true),
                decoration: InputDecoration(labelText: t(context).gsFieldRequired, suffixText: 'm'),
                onChanged: (_) => setState(() => _problem = null),
              ),
            ],
            KoordinatAktualFields(
              xInput: _xInput,
              yInput: _yInput,
              wajib: widget.xyRequired,
              designX: widget.designX,
              designY: widget.designY,
              toleranceMm: widget.toleranceMm,
              onChanged: () => setState(() => _problem = null),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t(context).cancel)),
        FilledButton(onPressed: _submit, child: Text(t(context).finishDrilling)),
      ],
    );
  }
}
