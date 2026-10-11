import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/device/notifications.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/util/decimal_input.dart';
import '../../core/util/format.dart';
import '../../core/util/reasons.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/time_wheel.dart';
import '../../core/widgets/view_states.dart';
import '../casting/level_reference.dart';
import 'drill_readings.dart';
import 'operator_picker.dart';

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
      setState(() => _error = 'Log bor tidak ditemukan di HP ini.');
      return;
    }
    final point = await db.getMaster('pile_point', pilePointUuid);
    if (point == null) {
      setState(() => _error = 'Titik bor tidak ditemukan. Tarik data terbaru dulu.');
      return;
    }
    if (doc == null) {
      // One point, one drill log: the server refuses a second one.
      final existing = point['drillLogUuid'];
      if (existing != null && '$existing' != widget.uuid) {
        setState(() => _error = 'Titik ${point['code']} sudah punya log bor'
            '${point['drillLogByName'] == null ? '' : ' dari ${point['drillLogByName']}'}. '
            'Satu titik hanya boleh satu log bor.');
        return;
      }
      if (point['status'] == 'sudah_cor') {
        setState(() => _error = 'Titik ${point['code']} sudah dicor.');
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
  }

  // -------------------------------------------------------------------------
  // Derived
  // -------------------------------------------------------------------------

  List<DrillReading> get _readings => readingsOf(_doc);
  bool get _finished => _doc!['status'] == 'selesai';
  String get _code => '${_pilePoint!['code']}';

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

  /// Buzz when this log goes an hour without a new reading; nothing once it
  /// is finished. A reminder must never break a save.
  Future<void> _updateIdleReminder() async {
    try {
      final readings = _readings;
      if (_finished || readings.isEmpty) {
        await Notifications.cancelDrillIdleReminders(widget.uuid);
        return;
      }
      final newest = readings.map((r) => r.at).reduce((a, b) => a.isAfter(b) ? a : b);
      await Notifications.scheduleDrillIdleReminders(logUuid: widget.uuid, pointCode: _code, lastReadingAt: newest);
    } catch (_) {}
  }

  Future<void> _update(void Function(Map<String, Object?> d) f) async {
    final p = ref.read(userProvider);
    if (p == null) return;
    setState(() => f(_doc!));
    final db = ref.read(dbProvider);
    await db.saveDocument(uuid: widget.uuid, entity: 'drill_log', userId: p.id, body: _doc!);
    _row = await db.getDocument(widget.uuid);
    ref.read(syncProvider.notifier).afterSave();
    await _updateIdleReminder();
    if (mounted) setState(() {});
  }

  List<Map<String, Object?>> get _entries =>
      [for (final e in (_doc!['entries'] as List?) ?? const []) (e as Map).cast<String, Object?>()];

  String? get _operatorUuid => _doc!['operatorUuid']?.toString();

  /// Choose (or change) the rig operator. Remembered on this phone as the
  /// default for the next log.
  Future<bool> _chooseOperator() async {
    final picked = await pickOperator(context, current: _operatorUuid);
    if (picked == null) return false;
    final u = ref.read(userProvider);
    if (u != null) await ref.read(dbProvider).writeMeta('lastOperator:${u.id}', picked);
    if (_readings.isEmpty) {
      // Nothing saved yet: keep it unsaved until the first reading.
      setState(() => _doc!['operatorUuid'] = picked);
    } else {
      await _update((d) => d['operatorUuid'] = picked);
      if (mounted) _snack('Operator bor disimpan.');
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
    await _update((d) {
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
    if (!mounted) return;
    _snack(result.delete ? 'Bacaan dihapus.' : 'Tercatat ${formatMeters(result.depthM)} jam ${formatTime(result.at)}.');
  }

  Future<void> _finish() async {
    if (_operatorUuid == null && !await _chooseOperator()) return;
    if (!mounted) return;
    final readings = _readings;
    final deepest = deepestM(readings);
    if (deepest == null) return;
    final result = await showDialog<({double? groundLevel})>(
      context: context,
      builder: (_) => _FinishDialog(
        code: _code,
        deepestM: deepest,
        plannedM: _plannedM,
        gsRequired: _groundLevel == null,
        tipLevel: toDoubleOrNull(_pilePoint!['tipLevel']),
        cutOffLevel: toDoubleOrNull(_pilePoint!['cutOffLevel']),
        groundLevel: _groundLevel,
      ),
    );
    if (result == null) return;
    await _update((d) {
      d['status'] = 'selesai';
      if (result.groundLevel != null) d['groundLevel'] = decimalText(result.groundLevel!, decimals: 3);
    });
    if (!mounted) return;
    _snack('$_code selesai dibor ${formatMeters(deepest)}.');
  }

  Future<void> _reopen() async {
    await _update((d) => d['status'] = 'berjalan');
    _snack('Log bor dibuka lagi.');
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
      return Scaffold(appBar: AppBar(title: const Text('Log bor')), body: ErrorState(title: _error!));
    }
    if (_doc == null) return const Scaffold(body: LoadingState());
    final w = context.colors;
    final readings = _readings;
    final cast = _pilePoint!['status'] == 'sudah_cor';
    final canEdit = !_finished && !cast;

    return Scaffold(
      appBar: AppBar(
        title: Text('Bor $_code'),
        actions: [
          if (_row != null) Padding(padding: const EdgeInsets.only(right: 12), child: StatusBadge.sendStatus(context, _row!.sendStatus)),
        ],
      ),
      body: ListView(
        // The action buttons live in bottomNavigationBar, which the body already
        // ends above: no extra room needed under the last card.
        padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, Dimens.pagePadding, Dimens.pagePadding, 8),
        children: [
          if (_row?.sendStatus == 'rejected')
            TerraBanner(kind: BannerKind.danger, title: 'Ditolak server', body: reasonText(_row!.reason, _row!.detail)),
          _DepthHero(readings: readings, plannedM: _plannedM, diameterMm: toIntOrNull(_pilePoint!['diameterMm']), finished: _finished),
          _OperatorRow(uuid: _operatorUuid, onChange: canEdit ? _chooseOperator : null),
          if (_finished)
            TerraBanner(
              kind: BannerKind.ok,
              title: 'Selesai dibor ${formatMeters(deepestM(readings))}',
              body: 'Titik ini sudah ditandai dibor; log cor bisa dimulai.',
              action: cast ? null : TextButton(onPressed: _reopen, child: const Text('Buka lagi')),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: Row(
              children: [
                Expanded(child: Text('Bacaan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: w.ink))),
                Text('${readings.length} kali', style: TextStyle(color: w.muted, fontSize: 13)),
              ],
            ),
          ),
          if (readings.isEmpty)
            const EmptyState(message: 'Belum ada bacaan. Tekan "Catat kedalaman" setiap kali kedalaman dibaca.'),
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
                  child: FilledButton.icon(
                    onPressed: cast
                        ? null
                        : () => context.pushReplacement('/casting/log/${newUuid()}?pilePoint=${_doc!['pilePointUuid']}'),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Mulai log cor'),
                  ),
                )
              : Row(
                  children: [
                    if (readings.isNotEmpty) ...[
                      Expanded(
                        child: SizedBox(
                          height: Dimens.minTouch + 4,
                          child: OutlinedButton(onPressed: canEdit ? _finish : null, child: const Text('Selesai bor')),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: Dimens.minTouch + 4,
                        child: FilledButton.icon(
                          onPressed: canEdit ? () => _addOrEdit() : null,
                          icon: const Icon(Icons.add),
                          label: const Text('Catat kedalaman'),
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
                Text('OPERATOR BOR', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: w.faint)),
                Text(name ?? 'Belum dipilih', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: name == null ? w.warnFg : w.ink)),
              ],
            ),
          ),
          if (onChange != null) Text(name == null ? 'Pilih' : 'Ganti', style: TextStyle(color: w.brand, fontWeight: FontWeight.w700)),
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
          Text(finished ? 'KEDALAMAN AKHIR' : 'KEDALAMAN SEKARANG',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: w.faint)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatMeters(deepest), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: w.ink, height: 1)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(planned == null ? 'rencana belum bisa dihitung' : 'dari ${formatMeters(planned)} rencana',
                    style: TextStyle(color: w.muted, fontSize: 13)),
              ),
            ],
          ),
          if (planned != null && planned > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (deepest / planned).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: w.line,
                color: over > 0.005 ? w.warnFg : w.brand,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            [
              if (diameterMm != null) 'D$diameterMm',
              if (started != null) 'mulai ${formatTime(started)}',
              if (started != null && last != null && last.isAfter(started)) 'sudah ${_hoursMinutes(last.difference(started))}',
              if (planned == null) 'GS belum diisi',
            ].join(' · '),
            style: TextStyle(color: w.muted, fontSize: 13),
          ),
          if (planned != null && over > 0.5)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${formatMeters(over)} lebih dalam dari rencana.',
                  style: TextStyle(color: w.warnFg, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

String _hoursMinutes(Duration d) => d.inHours > 0 ? '${d.inHours} j ${d.inMinutes % 60} m' : '${d.inMinutes} menit';

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
        : '+${formatMeters(reading.depthM - p.depthM)} dalam ${_hoursMinutes(reading.at.difference(p.at))}';
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
    final t = await showTimeWheel(context, initial: _followNow ? DateTime.now() : _at, title: 'Jam bacaan');
    if (t == null) return;
    final now = DateTime.now();
    setState(() {
      // Picking the current minute (e.g. "Sekarang") keeps following the clock.
      _followNow = widget.editing == null && t.hour == now.hour && t.minute == now.minute && t.day == now.day;
      _at = _followNow ? now : t;
      _problem = null;
    });
  }

  void _submit() {
    if (_followNow) _at = DateTime.now();
    final depth = parseNumber(_depth.text);
    if (depth == null || depth <= 0) {
      setState(() => _problem = 'Isi kedalaman (m), lebih dari 0.');
      return;
    }
    if (depth > maxDrillDepthM) {
      setState(() => _problem = 'Kedalaman paling dalam ${formatMeters(maxDrillDepthM, decimals: 0)}. Periksa angkanya.');
      return;
    }
    if (_at.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      setState(() => _problem = 'Jamnya di masa depan. Periksa jam bacaan.');
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
      padding: EdgeInsets.fromLTRB(Dimens.pagePadding, 0, Dimens.pagePadding, MediaQuery.viewInsetsOf(context).bottom + Dimens.pagePadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.editing == null ? 'Catat kedalaman' : 'Ubah bacaan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: w.ink)),
          Text(
            [
              if (widget.editing == null && last != null) 'Bacaan terakhir ${formatMeters(last.depthM)} jam ${formatTime(last.at)}',
              if (widget.plannedM != null) 'rencana ${formatMeters(widget.plannedM)}',
            ].join(' · '),
            style: TextStyle(color: w.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (problem != null) TerraBanner(kind: BannerKind.danger, title: 'Periksa isian', body: problem),
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
                      Text('sekarang', style: TextStyle(color: w.muted, fontWeight: FontWeight.w600)),
                    ],
                    const Spacer(),
                    Text('Ubah jam', style: TextStyle(color: w.brand, fontWeight: FontWeight.w700)),
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
            decoration: const InputDecoration(
              labelText: 'Kedalaman dari GS',
              suffixText: 'm',
            ),
            onChanged: (_) => setState(() => _problem = null),
            onSubmitted: (_) => _submit(),
          ),
          if (overPlan != null) ...[
            const SizedBox(height: 8),
            TerraBanner(
              kind: BannerKind.warning,
              title: 'Sudah lewat ${formatMeters(overPlan)} dari rencana',
              body: 'Rencana ${formatMeters(widget.plannedM)}. Lewat sedikit boleh; pastikan memang perlu dibor lebih dalam.',
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 255,
            decoration: const InputDecoration(labelText: 'Catatan (boleh kosong)', hintText: 'mis. ketemu batu, ganti mata bor'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: Dimens.minTouch + 4,
            child: FilledButton(onPressed: refusal == null ? _submit : null, child: const Text('Simpan')),
          ),
          if (widget.editing != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => Navigator.pop(
                context,
                _ReadingResult(at: widget.editing!.at, depthM: widget.editing!.depthM, delete: true),
              ),
              icon: Icon(Icons.delete_outline, color: w.badFg),
              label: Text('Hapus bacaan ini', style: TextStyle(color: w.badFg)),
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
  });

  final String code;
  final double deepestM;
  final double? plannedM;
  final bool gsRequired;
  final double? tipLevel;
  final double? cutOffLevel;

  /// Known GS of the point; null when it still has to be typed here.
  final double? groundLevel;

  @override
  State<_FinishDialog> createState() => _FinishDialogState();
}

class _FinishDialogState extends State<_FinishDialog> {
  final _gs = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _gs.dispose();
    super.dispose();
  }

  double? get _planned {
    if (widget.plannedM != null) return widget.plannedM;
    final gs = parseNumber(_gs.text);
    return gs == null || widget.tipLevel == null ? null : gs - widget.tipLevel!;
  }

  void _submit() {
    double? gs;
    if (widget.gsRequired) {
      gs = parseNumber(_gs.text);
      if (gs == null || gs < -500 || gs > 5000) {
        setState(() => _problem = 'Isi elevasi GS titik ini. Log cor tidak dapat dimulai tanpanya.');
        return;
      }
    }
    Navigator.pop(context, (groundLevel: gs));
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final planned = _planned;
    final short = planned == null ? 0.0 : planned - widget.deepestM;
    return AlertDialog(
      icon: Icon(Icons.flag_outlined, size: 32, color: w.brand),
      title: Text('Selesai bor ${widget.code}?', textAlign: TextAlign.center),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Kedalaman akhir ${formatMeters(widget.deepestM)} (bacaan terdalam). '
                'Titik ditandai sudah dibor dan log cor bisa dimulai.',
                style: TextStyle(color: w.ink, height: 1.4)),
            if (short > 0.5) ...[
              const SizedBox(height: 10),
              TerraBanner(
                kind: BannerKind.warning,
                title: 'Masih ${formatMeters(short)} lebih dangkal dari rencana',
                body: 'Rencana ${formatMeters(planned)}. Pastikan memang berhenti di sini.',
              ),
            ],
            const SizedBox(height: 10),
            LevelReferenceBanner(
              cutOffLevel: widget.cutOffLevel,
              tipLevel: widget.tipLevel,
              groundLevel: widget.groundLevel ?? parseNumber(_gs.text),
            ),
            if (widget.gsRequired) ...[
              if (_problem != null) ...[
                const SizedBox(height: 8),
                TerraBanner(kind: BannerKind.danger, title: 'Periksa isian', body: _problem),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _gs,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                inputFormatters: decimalInput(maxIntDigits: 4, decimals: 3, signed: true),
                decoration: const InputDecoration(labelText: 'Elevasi GS (m) — wajib', suffixText: 'm'),
                onChanged: (_) => setState(() => _problem = null),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _submit, child: const Text('Selesai bor')),
      ],
    );
  }
}
