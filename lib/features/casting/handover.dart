import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/widgets/app_snack.dart';
import '../../core/widgets/terra_banner.dart';

/// Oper: hand a RUNNING log (bor or cor) to a colleague with a 6-digit code.
///
/// Holder side ([offerHandover]): the phone pushes first, so what moves is the
/// latest content, then shows the code to read out. Receiving side
/// ([redeemHandoverFlow]): type the code on the locked point, the server
/// answers with the whole body, and this phone continues the log. The old
/// phone's pushes are refused (DIOPER) and its screen turns read-only on the
/// next pull.
///
/// `entity` is 'drill_log' or 'casting' everywhere here — the server's names.

String _logLabel(String entity) => entity == 'drill_log' ? 'log bor' : 'log cor';

/// Holder taps "Oper ke rekan": push, ask the server for a code, show it big.
Future<void> offerHandover(
  BuildContext context,
  WidgetRef ref, {
  required String entity,
  required String uuid,
  required String pointCode,
}) async {
  final label = _logLabel(entity);
  // Everything typed so far must reach the server first — the body the
  // colleague receives comes from there, not from this phone.
  await _busy(context, 'Mengirim $label dulu…', () => ref.read(syncProvider.notifier).run());
  final row = await ref.read(dbProvider).getDocument(uuid);
  if (!context.mounted) return;
  if (row == null || row.version > row.syncedVersion || row.sendStatus != 'sent') {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.cloud_off, size: 32, color: c.colors.warnFg),
        title: const Text('Kirim dulu sebelum oper', textAlign: TextAlign.center),
        content: Text(
          'Isi $label ini belum sampai ke server, jadi belum bisa dioper. '
          'Cari sinyal sebentar, lalu coba lagi — rekan menerima persis isi terakhir.',
          style: TextStyle(color: c.colors.ink, height: 1.4),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Mengerti'))],
      ),
    );
    return;
  }

  final ({String code, int validMinutes}) answer;
  try {
    answer = await _busy(context, 'Meminta kode oper…', () => ref.read(apiProvider).handoverCode(entity, uuid));
  } on ApiError catch (e) {
    if (context.mounted) showSnack(context, e.message, icon: Icons.error_outline);
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (c) {
      final w = c.colors;
      return AlertDialog(
        icon: Icon(Icons.swap_horiz, size: 32, color: w.brand),
        title: Text('Oper ${_logLabel(entity)} $pointCode', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Minta rekan membuka titik $pointCode di HP-nya dan memilih '
                '"Lanjutkan di HP ini", lalu sebutkan kode ini:',
                style: TextStyle(color: w.ink, height: 1.4)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: w.brandSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: w.brand.withValues(alpha: 0.4)),
              ),
              child: Text(
                '${answer.code.substring(0, 3)} ${answer.code.substring(3)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                  color: w.brandStrong,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TerraBanner(
              kind: BannerKind.info,
              icon: Icons.timer_outlined,
              title: 'Berlaku ${answer.validMinutes} menit, sekali pakai',
              body: 'Begitu rekan memasukkannya, log pindah ke dia dan '
                  'HP ini hanya bisa melihat. Foto yang diambil di HP ini tetap terkirim dari sini.',
            ),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Selesai'))],
      );
    },
  );
}

/// Colleague types the code on the locked point. Returns true when the log is
/// now on this phone (the caller navigates to it).
Future<bool> redeemHandoverFlow(
  BuildContext context,
  WidgetRef ref, {
  required String entity,
  required String uuid,
  required String pointCode,
}) async {
  final code = await showDialog<String>(
    context: context,
    builder: (c) => _CodeDialog(title: 'Lanjutkan ${_logLabel(entity)} $pointCode'),
  );
  if (code == null || !context.mounted) return false;
  final p = ref.read(userProvider);
  if (p == null) return false;
  try {
    final answer = await _busy(
      context,
      'Mengambil ${_logLabel(entity)}…',
      () => ref.read(apiProvider).redeemHandover(entity, uuid, code),
    );
    await ref.read(dbProvider).saveSyncedDocument(
          uuid: answer.uuid,
          entity: entity,
          userId: p.id,
          body: answer.body,
          version: answer.version,
        );
    // Pull straight away: the point record then names THIS user as holder,
    // so the screen opens unlocked (and the old phone locks on its pull).
    await ref.read(syncProvider.notifier).run();
    if (context.mounted) {
      showSnack(context, '${_logLabel(entity)[0].toUpperCase()}${_logLabel(entity).substring(1)} $pointCode sekarang dipegang HP ini.');
    }
    return true;
  } on ApiError catch (e) {
    if (context.mounted) showSnack(context, e.message, icon: Icons.error_outline);
    return false;
  }
}

/// Run [task] behind a small blocking progress dialog.
Future<T> _busy<T>(BuildContext context, String text, Future<T> Function() task) async {
  var open = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 16),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      ),
    ).whenComplete(() => open = false),
  );
  try {
    return await task();
  } finally {
    if (open && context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

/// Six digits, numeric keyboard, big glove-friendly text.
class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.title});

  final String title;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _complete => _code.text.length == 6;

  void _submit() {
    if (_complete) Navigator.pop(context, _code.text);
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return AlertDialog(
      icon: Icon(Icons.pin_outlined, size: 32, color: w.brand),
      title: Text(widget.title, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Masukkan kode oper 6 angka yang disebutkan pemegang lognya '
              '(dia menekan "Oper ke rekan" di HP-nya).',
              style: TextStyle(color: w.ink, height: 1.4)),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 8),
            decoration: const InputDecoration(hintText: '······', counterText: ''),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _complete ? _submit : null, child: const Text('Ambil alih')),
      ],
    );
  }
}
