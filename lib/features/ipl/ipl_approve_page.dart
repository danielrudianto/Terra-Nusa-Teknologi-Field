import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_snack.dart';
import '../../core/widgets/confirm.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/view_states.dart';
import '../casting/level_reference.dart';

/// IPLs waiting for confirmation, straight from the server (no offline copy:
/// a decision taken on yesterday's list could confirm what someone else has
/// already rejected).
final pendingIplProvider = FutureProvider.autoDispose<Map<String, Object?>>(
  (ref) => ref.read(apiProvider).pendingIpl(),
);

/// Whether this user may see the "Confirm IPL" entry: level 4 and up or the
/// Engineering division — the same rule the server applies (`boleh_laporan`)
/// — and the `field_ipl` approve right.
bool canApproveIpl(SessionState? session) {
  if (session == null) return false;
  final level = session.permissions.level;
  final engineering = session.permissions.departments.contains('engineering');
  return (level >= 4 || engineering) && session.allows('field_ipl', 'approve');
}

List<Map<String, Object?>> _ipls(Map<String, Object?> data) => [
  for (final i in (data['ipl'] as List? ?? const [])) (i as Map).cast<String, Object?>(),
];

/// CONFIRM IPL FROM THE PHONE (Daniel, 24 Nov 2026: "confirm IPL kita bikin
/// di HP boleh ga bang? khusus level 4+").
///
/// The list of waiting IPLs, nearest date first, one card each; a card opens
/// the IPL with its points and the Confirm / Reject buttons. Same endpoints
/// and same rules as the web, so a decision here is exactly a decision there.
class IplApprovePage extends ConsumerWidget {
  const IplApprovePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = t(context);
    final w = context.colors;
    final async = ref.watch(pendingIplProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.iplApproveTitle)),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pendingIplProvider.future),
        child: async.when(
          loading: () => const LoadingState(),
          error: (e, _) => ListView(
            padding: pagePaddingAman(context),
            children: [
              ErrorState(
                title: l.iplApproveLoadFailed,
                message: e is ApiError ? e.message : '$e',
                onRetry: () => ref.invalidate(pendingIplProvider),
              ),
            ],
          ),
          data: (data) {
            final ipls = _ipls(data);
            final canDecide = data['canDecide'] == true;
            if (ipls.isEmpty) {
              return ListView(
                padding: pagePaddingAman(context),
                children: [EmptyState(message: l.iplApproveNone, icon: Icons.task_alt)],
              );
            }
            return ListView(
              padding: pagePaddingAman(context),
              children: [
                if (!canDecide) ...[
                  TerraBanner(kind: BannerKind.info, title: l.iplApproveNoRight, body: l.iplApproveNoRightBody),
                  const SizedBox(height: 12),
                ],
                for (final ipl in ipls) ...[
                  ListCard(
                    edgeColor: ipl['own'] == true ? w.muted : w.brand,
                    onTap: () async {
                      final decided = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => _IplDetailPage(
                            ipl: ipl,
                            canDecide: canDecide,
                            // An older server does not say: assume a signature.
                            hasSignature: data['hasSignature'] != false,
                          ),
                        ),
                      );
                      if (decided == true) ref.invalidate(pendingIplProvider);
                    },
                    child: _IplSummary(ipl: ipl),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

String _dateOf(Map<String, Object?> ipl) {
  final d = DateTime.tryParse('${ipl['date']}');
  return d == null ? '${ipl['date']}' : longDate(d);
}

String _projectOf(Map<String, Object?> ipl) {
  final code = '${ipl['projectCode'] ?? ''}'.trim();
  final name = '${ipl['projectName'] ?? ''}'.trim();
  return [code, name].where((s) => s.isNotEmpty).join(' — ');
}

List<Map<String, Object?>> _lines(Map<String, Object?> ipl) => [
  for (final b in (ipl['lines'] as List? ?? const [])) (b as Map).cast<String, Object?>(),
];

class _IplSummary extends StatelessWidget {
  const _IplSummary({required this.ipl});

  final Map<String, Object?> ipl;

  @override
  Widget build(BuildContext context) {
    final l = t(context);
    final w = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_dateOf(ipl), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: w.ink)),
        const SizedBox(height: 2),
        Text(_projectOf(ipl), style: TextStyle(color: w.ink, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          l.iplApproveMeta('${ipl['createdByName'] ?? '-'}', '${_lines(ipl).length}'),
          style: TextStyle(color: w.muted, fontSize: 13),
        ),
        if (ipl['own'] == true) ...[
          const SizedBox(height: 4),
          Text(l.iplApproveOwnShort, style: TextStyle(color: w.warnFg, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

class _IplDetailPage extends ConsumerStatefulWidget {
  const _IplDetailPage({required this.ipl, required this.canDecide, required this.hasSignature});

  final Map<String, Object?> ipl;
  final bool canDecide;

  /// Whether this user has a registered signature. The IPL PDF stamps the
  /// confirmer's signature; without one the box prints empty, so say so
  /// BEFORE confirming (24 Nov 2026).
  final bool hasSignature;

  @override
  ConsumerState<_IplDetailPage> createState() => _IplDetailPageState();
}

class _IplDetailPageState extends ConsumerState<_IplDetailPage> {
  bool _busy = false;

  int get _id => int.parse('${widget.ipl['id']}');

  Future<void> _confirm() async {
    final l = t(context);
    final ok = await askConfirm(
      context,
      title: l.iplApproveConfirmTitle(_dateOf(widget.ipl)),
      body: l.iplApproveConfirmBody('${_lines(widget.ipl).length}'),
      confirmLabel: l.iplApproveConfirm,
      icon: Icons.verified_outlined,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).confirmIpl(_id);
      if (!mounted) return;
      final skipped = [for (final c in (r['skipped'] as List? ?? const [])) '$c'];
      showSnack(context, skipped.isEmpty ? l.iplApproveDone : l.iplApproveDoneSkipped(skipped.join(', ')));
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (mounted) showSnack(context, e.message, icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _RejectDialog());
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).rejectIpl(_id, reason);
      if (!mounted) return;
      showSnack(context, t(context).iplApproveRejectedDone);
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (mounted) showSnack(context, e.message, icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _signed(double v) {
    final s = formatElevation(v.abs(), decimals: 3).replaceFirst('+', '');
    return '${v > 0.0005 ? '+' : v < -0.0005 ? '−' : '±'}$s';
  }

  @override
  Widget build(BuildContext context) {
    final l = t(context);
    final w = context.colors;
    final ipl = widget.ipl;
    final lines = _lines(ipl);
    final own = ipl['own'] == true;
    final mayDecide = widget.canDecide && !own;
    final note = '${ipl['note'] ?? ''}'.trim();

    return Scaffold(
      appBar: AppBar(title: Text(l.iplApproveTitle)),
      body: ListView(
        padding: pagePaddingAman(context),
        children: [
          _IplSummary(ipl: ipl),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(l.iplApproveNote(note), style: TextStyle(color: w.ink, height: 1.4)),
          ],
          const SizedBox(height: 14),
          if (own)
            TerraBanner(kind: BannerKind.warning, title: l.iplApproveOwn, body: l.iplApproveOwnBody)
          else if (!widget.canDecide)
            TerraBanner(kind: BannerKind.info, title: l.iplApproveNoRight, body: l.iplApproveNoRightBody),
          if (own || !widget.canDecide) const SizedBox(height: 14),
          if (mayDecide && !widget.hasSignature) ...[
            TerraBanner(
              kind: BannerKind.warning,
              icon: Icons.draw_outlined,
              title: l.iplApproveNoSignature,
              body: l.iplApproveNoSignatureBody,
            ),
            const SizedBox(height: 14),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: w.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (final (i, b) in lines.indexed) ...[
                  if (i > 0) Divider(height: 1, color: w.line),
                  _line(context, i, b),
                ],
              ],
            ),
          ),
          const SizedBox(height: 96),
        ],
      ),
      bottomNavigationBar: mayDecide
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _reject,
                        icon: const Icon(Icons.undo),
                        label: Text(l.iplApproveReject),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _confirm,
                        icon: _busy
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.verified_outlined),
                        label: Text(l.iplApproveConfirm),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _line(BuildContext context, int i, Map<String, Object?> b) {
    final l = t(context);
    final w = context.colors;
    final gs = toDoubleOrNull(b['groundLevel']);
    final design = toDoubleOrNull(b['pileGroundLevel']);
    final diff = gs == null || design == null ? null : gs - design;
    final kind = switch (b['kind']) {
      'lanjut' => l.iplKindLanjut,
      'cor' => l.iplKindCor,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 26, child: Text('${i + 1}', style: TextStyle(color: w.muted, fontSize: 13))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${b['pilePointCode'] ?? '-'}', style: TextStyle(fontWeight: FontWeight.w800, color: w.ink)),
                if (kind != null)
                  Text(
                    kind,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: b['kind'] == 'lanjut' ? w.warnFg : w.brand,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                gs == null ? '-' : formatElevation(gs, decimals: 3),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: w.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (diff != null)
                Text(
                  l.iplConfirmDiff(_signed(diff)),
                  style: TextStyle(
                    fontSize: 12,
                    color: diff.abs() > 0.30 ? w.warnFg : w.muted,
                    fontWeight: diff.abs() > 0.30 ? FontWeight.w700 : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The reason for a rejection — required, at least 5 characters, the same
/// rule as the server (`AlasanSaja`).
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _text = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = t(context);
    final reason = _text.text.trim();
    final short = reason.length < 5;
    return AlertDialog(
      icon: const Icon(Icons.undo, size: 32),
      title: Text(l.iplApproveRejectTitle, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.iplApproveRejectBody),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: 255,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l.iplApproveReasonLabel,
              errorText: _tried && short ? l.iplApproveReasonShort : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () {
            if (short) {
              setState(() => _tried = true);
              return;
            }
            Navigator.pop(context, reason);
          },
          child: Text(l.iplApproveReject),
        ),
      ],
    );
  }
}
