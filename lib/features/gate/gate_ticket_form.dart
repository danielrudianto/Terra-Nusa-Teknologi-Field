import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/camera.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/util/decimal_input.dart';
import '../../core/util/format.dart';
import '../../core/util/reasons.dart';
import '../../core/widgets/step_progress.dart';
import '../../core/widgets/terra_banner.dart';
import '../casting/calc/casting_state.dart';
import '../casting/concrete_suppliers.dart';
import '../casting/measure_diagram.dart';
import 'next_pile.dart';

/// Gate record for ONE concrete truck heading to one pile point.
///
/// Requested by Daniel, 17 Nov 2026. Casting is split between three people:
/// the one watching the drill, the one at the GATE (this form: truck number,
/// delivery note photo, slump, grade, volume) and the one at the hole (the
/// casting log: timer, tremie, concrete depth).
///
/// The document is its own entity, `gate_ticket`, and its body must be
/// EXACTLY `GateTicketData` in the backend's `schemas/field_schema.py`. The
/// server pairs it with the truck row of the same number on the same pile
/// point, in whichever order the two phones sync.
///
/// Works fully offline, like every other document here.
///
/// A NEW record is asked ONE QUESTION PER SCREEN, the same way the casting
/// log asks about a truck that has just arrived: the person at the gate is
/// holding a delivery note in one hand, often in the sun, and a long form
/// is where fields get skipped. An existing record opens as one sheet, for
/// correcting a single value.
class GateTicketForm extends ConsumerStatefulWidget {
  const GateTicketForm({super.key, required this.uuid, this.pilePointUuid, this.copyFromUuid});

  /// `null` for a new record.
  final String? uuid;

  /// Required for a new record; an existing one carries it in its body.
  final String? pilePointUuid;

  /// For a new record only: the gate record of the SAME truck on another
  /// pile point. One truck is sometimes split between two holes, and the
  /// truck number, delivery note photo, supplier, slump and grade are then
  /// the same on both — only the volume differs. They are copied from that
  /// record so the person at the gate does not fill them in twice.
  final String? copyFromUuid;

  @override
  ConsumerState<GateTicketForm> createState() => _GateTicketFormState();
}

class _GateTicketFormState extends ConsumerState<GateTicketForm> {
  final _truck = TextEditingController();
  final _volume = TextEditingController();
  final _slump = TextEditingController();
  final _grade = TextEditingController();
  final _rejectReason = TextEditingController();

  late final String _uuid = widget.uuid ?? newUuid();
  late String? _pilePointUuid = widget.pilePointUuid;

  /// Set once, when the record is first opened: the moment the truck was at
  /// the gate. Editing the record later must not move it.
  String _arrivedAt = isoWithOffset(DateTime.now());

  Map<String, Object?>? _pilePoint;
  List<Map<String, Object?>> _suppliers = const [];
  int? _supplierId;
  String? _photoUuid;
  String? _photoPath;
  bool _rejected = false;

  /// This new record continues a truck already recorded on another pile
  /// point: only the volume is asked.
  bool _copied = false;
  bool _loading = true;
  bool _saving = false;

  /// Why the server sent this record back, if it did.
  String? _serverRejection;

  /// What stops the save right now.
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_truck, _volume, _slump, _grade, _rejectReason]) {
      c.dispose();
    }
    super.dispose();
  }

  /// A stored decimal as the person would have typed it: "6", "5,5".
  static String _asTyped(Object? v) {
    final d = toDoubleOrNull(v);
    if (d == null) return '';
    var text = d.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceAll(RegExp(r'0+$'), '');
      text = text.replaceAll(RegExp(r'\.$'), '');
    }
    return text.replaceAll('.', ',');
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    if (widget.uuid != null) {
      final doc = await db.getDocument(_uuid);
      // Localizations are read AFTER the first await: `initState` may not
      // look up an inherited widget.
      if (!mounted) return;
      final l = t(context);
      if (doc != null) {
        final body = (jsonDecode(doc.body) as Map).cast<String, Object?>();
        if (doc.sendStatus == 'rejected') {
          _serverRejection = reasonTextOf(l, doc.reason, doc.detail);
        }
        _pilePointUuid = body['pilePointUuid']?.toString();
        _truck.text = '${body['truckNo'] ?? ''}';
        _volume.text = _asTyped(body['volumeM3']);
        _slump.text = _asTyped(body['slumpCm']);
        _grade.text = _asTyped(body['concreteGrade']);
        _supplierId = toIntOrNull(body['supplierID']);
        _photoUuid = body['ticketPhotoUuid']?.toString();
        _rejected = body['rejected'] == true;
        _rejectReason.text = '${body['rejectReason'] ?? ''}';
        final arrived = body['arrivedAt']?.toString();
        if (arrived != null && arrived.isNotEmpty) _arrivedAt = arrived;
        final photo = _photoUuid;
        if (photo != null) _photoPath = (await db.getPhoto(photo))?.path;
      }
    }
    final pileUuid = _pilePointUuid;
    if (pileUuid != null) {
      _pilePoint = await db.getMaster('pile_point', pileUuid);
    }
    // A new record offers the pile point's own grade; the person at the
    // gate corrects it if the delivery note says otherwise.
    if (widget.uuid == null) {
      _grade.text = _asTyped(_pilePoint?['concreteGrade']);
    }
    // The same truck, already recorded on another pile point: everything
    // read off the delivery note is copied. The volume is NOT — it is the
    // part poured into this hole, and copying it would count the same
    // concrete twice.
    final sourceUuid = widget.copyFromUuid;
    if (widget.uuid == null && sourceUuid != null) {
      final source = await db.getDocument(sourceUuid);
      if (source != null) {
        final body = (jsonDecode(source.body) as Map).cast<String, Object?>();
        _truck.text = '${body['truckNo'] ?? ''}';
        _slump.text = _asTyped(body['slumpCm']);
        _grade.text = _asTyped(body['concreteGrade']);
        _supplierId = toIntOrNull(body['supplierID']);
        _photoUuid = body['ticketPhotoUuid']?.toString();
        final arrived = body['arrivedAt']?.toString();
        if (arrived != null && arrived.isNotEmpty) _arrivedAt = arrived;
        final photo = _photoUuid;
        if (photo != null) _photoPath = (await db.getPhoto(photo))?.path;
        _copied = true;
      }
    }
    _suppliers = suppliersForProject(
      await db.listMaster('supplier'),
      toIntOrNull(_pilePoint?['projectID']),
      keepId: _supplierId,
    ).suppliers;
    if (mounted) setState(() => _loading = false);
  }

  bool get _canEdit {
    final session = ref.read(sessionProvider).value;
    if (session == null) return false;
    return session.allows('field_casting', 'create') || session.allows('field_casting', 'update');
  }

  Future<void> _takePhoto() async {
    final user = ref.read(userProvider);
    if (user == null) return;
    try {
      final photo = await takePhoto(db: ref.read(dbProvider), userId: user.id, kind: 'tiket_tm');
      if (photo == null) return;
      setState(() {
        _photoUuid = photo.uuid;
        _photoPath = photo.path;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).cameraFailed('$e'))));
      }
    }
  }

  /// The first thing that stops the save, in the order the form is filled.
  String? _problem() {
    final l = t(context);
    if (_truck.text.trim().isEmpty) return l.gateTruckRequired;
    if (_rejected) {
      if (_rejectReason.text.trim().length < 3) return l.gateRejectReasonRequired;
    } else {
      final volume = parseNumber(_volume.text);
      if (volume == null || volume <= 0 || volume > truckVolumeMaxM3) {
        return l.volumeInvalid(decimalText(truckVolumeMaxM3, decimals: 0));
      }
      if (_suppliers.isNotEmpty && _supplierId == null) return l.supplierMustBePicked;
      if (_photoUuid == null) return l.gatePhotoRequired;
    }
    if (_slump.text.trim().isNotEmpty) {
      final slump = parseNumber(_slump.text);
      if (slump == null || slump < 0 || slump > 40) return l.slumpInvalid;
    }
    if (_grade.text.trim().isNotEmpty) {
      final grade = parseNumber(_grade.text);
      if (grade == null || grade <= 0 || grade > 150) return l.gateGradeInvalid;
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _problem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final user = ref.read(userProvider);
    final pileUuid = _pilePointUuid;
    if (user == null || pileUuid == null) return;

    final truck = _truck.text.trim();
    final volume = parseNumber(_volume.text);
    final slump = _slump.text.trim().isEmpty ? null : parseNumber(_slump.text);
    final grade = _grade.text.trim().isEmpty ? null : parseNumber(_grade.text);
    final picked = _suppliers.where((s) => toIntOrNull(s['id']) == _supplierId).firstOrNull;
    final saved = t(context).gateSaved(truck);

    setState(() {
      _saving = true;
      _error = null;
    });
    await ref.read(dbProvider).saveDocument(
      uuid: _uuid,
      entity: 'gate_ticket',
      userId: user.id,
      // Exactly `GateTicketData`: the server refuses an unknown field.
      body: {
        'pilePointUuid': pileUuid,
        'truckNo': truck,
        'supplierID': picked == null ? null : toIntOrNull(picked['id']),
        'supplierName': picked == null ? null : '${picked['name']}',
        'concreteGrade': grade == null ? null : decimalText(grade, decimals: 1),
        'slumpCm': slump == null ? null : decimalText(slump, decimals: 1),
        // A rejected truck delivered nothing: no volume to pair.
        'volumeM3': _rejected || volume == null ? null : decimalText(volume),
        'arrivedAt': _arrivedAt,
        'ticketPhotoUuid': _photoUuid,
        'rejected': _rejected,
        'rejectReason': _rejected ? _rejectReason.text.trim() : null,
      },
    );
    ref.read(syncProvider.notifier).afterSave();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(saved)),
          ],
        ),
      ),
    );
    // A truck just recorded may be split between two holes: ask once, here,
    // while the delivery note is still in hand. Not asked for a rejected
    // truck (nothing is poured) nor when an existing record is corrected.
    if (widget.uuid == null && !_rejected) {
      final nextPile = await _pickNextPile(truck);
      if (!mounted) return;
      if (nextPile != null) {
        unawaited(context.pushReplacement('/gate/new?pilePoint=$nextPile&from=$_uuid'));
        return;
      }
    }
    context.pop();
  }

  /// Ask whether this truck also pours into another pile point; the rule
  /// for which ones are offered lives in `pilesForSameTruck`. `null` when
  /// the answer is no, or there is none to offer.
  Future<String?> _pickNextPile(String truck) async {
    final piles = pilesForSameTruck(
      await ref.read(dbProvider).listMaster('pile_point'),
      projectId: _pilePoint?['projectID'],
      currentUuid: _pilePointUuid,
    );
    if (piles.isEmpty || !mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NextPileSheet(truck: truck, piles: piles),
    );
  }

  Widget _photoField(bool canEdit) {
    final w = context.colors;
    final path = _photoPath;
    if (path == null || !File(path).existsSync()) {
      // A large target: the other hand is holding the delivery note.
      return FilledButton.tonalIcon(
        onPressed: canEdit ? _takePhoto : null,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(72)),
        icon: const Icon(Icons.photo_camera_outlined, size: 28),
        label: Text(t(context).photoTicket, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: w.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: w.line),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(path), height: 56, width: 56, fit: BoxFit.cover, cacheHeight: 168),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(t(context).deliveryNote)),
          if (canEdit) TextButton(onPressed: _takePhoto, child: Text(t(context).retake)),
        ],
      ),
    );
  }

  Widget _supplierField(bool canEdit) {
    final known = _suppliers.any((s) => toIntOrNull(s['id']) == _supplierId);
    return DropdownButtonFormField<int?>(
      initialValue: known ? _supplierId : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: t(context).truckSupplier),
      items: [
        for (final s in _suppliers)
          DropdownMenuItem<int?>(
            value: toIntOrNull(s['id']),
            child: Text('${s['name']}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: canEdit ? (v) => setState(() => _supplierId = v) : null,
    );
  }

  // ---------------------------------------------------------------------
  // Guided entry: one question per screen
  // ---------------------------------------------------------------------

  int _step = 0;

  /// The questions, in the order the delivery note is read. The supplier is
  /// only asked when there is a list to pick from.
  ///
  /// A record that continues a truck from another pile point asks ONE
  /// thing — the volume — then shows everything for a last look.
  List<({String key, List<Widget> Function() body})> get _steps => _copied
      ? [
          (key: 'volume', body: _stepVolume),
          (key: 'summary', body: _stepSummary),
        ]
      : _newSteps;

  List<({String key, List<Widget> Function() body})> get _newSteps => [
        (key: 'truck', body: _stepTruck),
        (key: 'photo', body: _stepPhoto),
        (key: 'volume', body: _stepVolume),
        if (_suppliers.isNotEmpty) (key: 'supplier', body: _stepSupplier),
        (key: 'slump', body: _stepSlump),
        (key: 'grade', body: _stepGrade),
        (key: 'summary', body: _stepSummary),
      ];

  Widget _question(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(text, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.3)),
      );

  static const _answerStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.w700);

  List<Widget> _stepTruck() => [
        _question(t(context).qTruckNo),
        TextField(
          controller: _truck,
          autofocus: true,
          style: _answerStyle,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _next(),
          decoration: InputDecoration(labelText: t(context).hullNoField),
        ),
        const SizedBox(height: 12),
        // Why the number matters, said once, where it is typed.
        TerraBanner(
          kind: BannerKind.info,
          icon: Icons.local_shipping_outlined,
          title: t(context).gateIntroTitle,
          body: t(context).gateIntroBody,
        ),
      ];

  List<Widget> _stepPhoto() => [
        _question(t(context).qPhoto),
        _photoField(true),
      ];

  List<Widget> _stepVolume() => [
        _question(t(context).qVolume),
        // The one mistake this screen invites on a split truck: typing the
        // whole load again. Said before the number is typed.
        if (_copied) ...[
          TerraBanner(
            kind: BannerKind.info,
            icon: Icons.call_split,
            title: t(context).gateCopiedTitle(_truck.text.trim()),
            body: t(context).gateCopiedBody,
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _volume,
          autofocus: true,
          style: _answerStyle,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalInput(maxIntDigits: 2),
          onSubmitted: (_) => _next(),
          decoration: InputDecoration(labelText: t(context).gateVolume, suffixText: 'm³'),
        ),
      ];

  /// Suppliers as large rows to tap — a dropdown hides the choices behind a
  /// second tap and a small target.
  List<Widget> _stepSupplier() {
    final w = context.colors;
    return [
      _question(t(context).qSupplier),
      for (final s in _suppliers)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            onTap: () => setState(() {
              _supplierId = toIntOrNull(s['id']);
              _error = null;
            }),
            tileColor: toIntOrNull(s['id']) == _supplierId ? w.brandSoft : w.surface2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Dimens.radiusBanner),
              side: BorderSide(color: toIntOrNull(s['id']) == _supplierId ? w.brand : w.line),
            ),
            leading: Icon(
              toIntOrNull(s['id']) == _supplierId ? Icons.check_circle : Icons.radio_button_unchecked,
              color: toIntOrNull(s['id']) == _supplierId ? w.brand : w.muted,
            ),
            title: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
    ];
  }

  List<Widget> _stepSlump() => [
        _question(t(context).qSlump),
        const SlumpDiagram(),
        const SizedBox(height: 12),
        TextField(
          controller: _slump,
          autofocus: true,
          style: _answerStyle,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalInput(maxIntDigits: 2, decimals: 1),
          onSubmitted: (_) => _next(),
          decoration: InputDecoration(labelText: t(context).slumpField, suffixText: 'cm'),
        ),
        const SizedBox(height: 20),
        // The slump test is where a truck is turned away, so the way to
        // say so is here — not on a screen the person has yet to reach.
        OutlinedButton.icon(
          onPressed: _saving ? null : _reject,
          style: OutlinedButton.styleFrom(
            foregroundColor: context.colors.badFg,
            side: BorderSide(color: context.colors.badFg),
            minimumSize: const Size.fromHeight(Dimens.minTouch + 4),
          ),
          icon: const Icon(Icons.block),
          label: Text(t(context).gateRejectAction),
        ),
      ];

  List<Widget> _stepGrade() => [
        _question(t(context).gateQGrade),
        TextField(
          controller: _grade,
          autofocus: true,
          style: _answerStyle,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalInput(maxIntDigits: 3, decimals: 1),
          onSubmitted: (_) => _next(),
          decoration: InputDecoration(labelText: t(context).gateGrade, suffixText: 'MPa'),
        ),
      ];

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: TextStyle(color: context.colors.muted))),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value.isEmpty ? '–' : value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );

  /// Everything once more before it is sent: the last look is where a
  /// swapped digit gets caught.
  List<Widget> _stepSummary() {
    final l = t(context);
    final supplier = _suppliers.where((s) => toIntOrNull(s['id']) == _supplierId).firstOrNull;
    return [
      _question(l.gateQSummary),
      _photoField(true),
      const SizedBox(height: 8),
      _summaryRow(l.hullNoField, _truck.text.trim()),
      _summaryRow(l.gateVolume, _volume.text.trim().isEmpty ? '' : '${_volume.text.trim()} m³'),
      if (_suppliers.isNotEmpty) _summaryRow(l.truckSupplier, supplier == null ? '' : '${supplier['name']}'),
      _summaryRow(l.slumpField, _slump.text.trim().isEmpty ? '' : '${_slump.text.trim()} cm'),
      _summaryRow(l.gateGrade, _grade.text.trim().isEmpty ? '' : '${_grade.text.trim()} MPa'),
    ];
  }

  /// What stops THIS step — said on the screen it concerns, not at the end.
  ///
  /// Written as `if`s, not a `switch`: the backend's contract check reads
  /// every quoted word followed by a colon in this file as a field of the
  /// document, and a `case` label looks exactly like one.
  String? _stepProblem(String key) {
    final l = t(context);
    if (key == 'truck') {
      return _truck.text.trim().isEmpty ? l.gateTruckRequired : null;
    }
    if (key == 'photo') {
      return _photoUuid == null ? l.gatePhotoRequired : null;
    }
    if (key == 'volume') {
      final volume = parseNumber(_volume.text);
      return volume == null || volume <= 0 || volume > truckVolumeMaxM3
          ? l.volumeInvalid(decimalText(truckVolumeMaxM3, decimals: 0))
          : null;
    }
    if (key == 'supplier') {
      return _supplierId == null ? l.supplierMustBePicked : null;
    }
    if (key == 'slump' && _slump.text.trim().isNotEmpty) {
      final slump = parseNumber(_slump.text);
      return slump == null || slump < 0 || slump > 40 ? l.slumpInvalid : null;
    }
    if (key == 'grade' && _grade.text.trim().isNotEmpty) {
      final grade = parseNumber(_grade.text);
      return grade == null || grade <= 0 || grade > 150 ? l.gateGradeInvalid : null;
    }
    return null;
  }

  void _next() {
    final steps = _steps;
    final i = _step.clamp(0, steps.length - 1);
    final problem = _stepProblem(steps[i].key);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (i == steps.length - 1) {
      _save();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _step = i + 1;
    });
  }

  /// The truck is turned away: ask why, then save the record as rejected.
  /// Only the truck number is needed — nothing was delivered.
  Future<void> _reject() async {
    final l = t(context);
    if (_truck.text.trim().isEmpty) {
      setState(() => _error = l.gateTruckRequired);
      return;
    }
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.block, size: 32, color: c.colors.badFg),
        title: Text(l.gateRejectedTitle, textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.gateRejectedBody),
            const SizedBox(height: 12),
            TextField(
              controller: _rejectReason,
              autofocus: true,
              maxLength: 255,
              decoration: InputDecoration(labelText: l.gateRejectReason),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(l.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(c, _rejectReason.text.trim()),
            child: Text(l.gateRejectAction),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    if (reason.length < 3) {
      setState(() => _error = l.gateRejectReasonRequired);
      return;
    }
    setState(() => _rejected = true);
    await _save();
  }

  Widget _guided(BuildContext context) {
    final l = t(context);
    final steps = _steps;
    final i = _step.clamp(0, steps.length - 1);
    final last = i == steps.length - 1;
    return ListView(
      padding: pagePaddingAman(context),
      children: [
        StepProgress(step: i + 1, total: steps.length),
        const SizedBox(height: 16),
        if (_error != null) ...[
          TerraBanner(kind: BannerKind.danger, title: _error!),
          const SizedBox(height: 12),
        ],
        AnimatedSwitcher(
          duration: Dimens.motionMedium,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: Column(
            key: ValueKey(steps[i].key),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: steps[i].body(),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            if (i > 0) ...[
              Expanded(
                child: SizedBox(
                  height: Dimens.minTouch + 4,
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _error = null;
                              _step = i - 1;
                            }),
                    child: Text(l.backStep),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: SizedBox(
                height: Dimens.minTouch + 4,
                child: FilledButton(
                  onPressed: _saving ? null : _next,
                  child: Text(last ? l.save : l.nextStep),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// One sheet with every field — for opening a record that already exists.
  Widget _sheet(BuildContext context, bool canEdit) {
    final l = t(context);
    return ListView(
      padding: pagePaddingAman(context),
      children: [
        if (_serverRejection != null) TerraBanner(kind: BannerKind.danger, title: l.needsFixing, body: _serverRejection),
        TextField(
          controller: _truck,
          enabled: canEdit,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: l.hullNoField),
        ),
        const SizedBox(height: 14),
        _photoField(canEdit),
        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _rejected,
          onChanged: canEdit ? (v) => setState(() => _rejected = v) : null,
          title: Text(l.gateRejected),
        ),
        if (_rejected) ...[
          TerraBanner(
            kind: BannerKind.warning,
            icon: Icons.block,
            title: l.gateRejectedTitle,
            body: l.gateRejectedBody,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _rejectReason,
            enabled: canEdit,
            maxLength: 255,
            decoration: InputDecoration(labelText: l.gateRejectReason),
          ),
        ] else ...[
          TextField(
            controller: _volume,
            enabled: canEdit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: decimalInput(maxIntDigits: 2),
            decoration: InputDecoration(labelText: l.gateVolume, suffixText: 'm³'),
          ),
          if (_suppliers.isNotEmpty) ...[
            const SizedBox(height: 14),
            _supplierField(canEdit),
          ],
        ],
        const SizedBox(height: 14),
        TextField(
          controller: _slump,
          enabled: canEdit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalInput(maxIntDigits: 2, decimals: 1),
          decoration: InputDecoration(labelText: l.slumpField, suffixText: 'cm'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _grade,
          enabled: canEdit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalInput(maxIntDigits: 3, decimals: 1),
          decoration: InputDecoration(labelText: l.gateGrade, suffixText: 'MPa'),
        ),
        const SizedBox(height: 20),
        if (_error != null) TerraBanner(kind: BannerKind.danger, title: l.needsFixing, body: _error),
        if (canEdit)
          SizedBox(
            height: Dimens.minTouch + 4,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(l.saveChanges),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = t(context);
    final canEdit = !_loading && _canEdit && _pilePointUuid != null;
    final code = '${_pilePoint?['code'] ?? ''}';
    return Scaffold(
      appBar: AppBar(title: Text(l.gateTitle(code))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : widget.uuid == null && canEdit
              ? _guided(context)
              : _sheet(context, canEdit),
    );
  }
}

/// Asked right after a gate record is saved: does the same truck also pour
/// into another pile point?
///
/// "No" is the large button on top — it is the answer nine times out of
/// ten, and it must not be hunted for. The pile points below are the
/// "yes": tapping one opens its gate record with the delivery note already
/// copied in.
class _NextPileSheet extends StatefulWidget {
  const _NextPileSheet({required this.truck, required this.piles});

  final String truck;
  final List<Map<String, Object?>> piles;

  @override
  State<_NextPileSheet> createState() => _NextPileSheetState();
}

class _NextPileSheetState extends State<_NextPileSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = t(context);
    final w = context.colors;
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final p in widget.piles)
        if (query.isEmpty || '${p['code']}'.toLowerCase().contains(query)) p,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.gateOtherPileTitle(widget.truck),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.3),
            ),
            const SizedBox(height: 10),
            TerraBanner(kind: BannerKind.info, icon: Icons.call_split, title: l.gateOtherPileBody),
            const SizedBox(height: 12),
            SizedBox(
              height: Dimens.minTouch + 4,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.gateOtherPileNo),
              ),
            ),
            const SizedBox(height: 18),
            Text(l.gateOtherPilePick, style: TextStyle(fontWeight: FontWeight.w700, color: w.muted)),
            const SizedBox(height: 8),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l.gateOtherPileSearch,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.36),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: shown.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => Navigator.pop(context, '${shown[i]['uuid']}'),
                    tileColor: w.surface2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Dimens.radiusBanner),
                      side: BorderSide(color: w.line),
                    ),
                    leading: Icon(Icons.add_circle_outline, color: w.brand),
                    title: Text('${shown[i]['code']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
