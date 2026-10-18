import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/notifications.dart';
import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/widgets/app_snack.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/i18n.dart';

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

String _logLabel(BuildContext context, String entity) =>
    entity == 'drill_log' ? t(context).drillLogWord : t(context).castLogWord;

/// Holder taps "Oper ke rekan": push, ask the server for a code, show it big.
Future<void> offerHandover(
  BuildContext context,
  WidgetRef ref, {
  required String entity,
  required String uuid,
  required String pointCode,
}) async {
  final label = _logLabel(context, entity);
  // Everything typed so far must reach the server first — the body the
  // colleague receives comes from there, not from this phone.
  await _busy(context, t(context).sendingFirst(label), () => ref.read(syncProvider.notifier).run(diminta: true));
  final row = await ref.read(dbProvider).getDocument(uuid);
  if (!context.mounted) return;
  if (row == null || row.version > row.syncedVersion || row.sendStatus != 'sent') {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.cloud_off, size: 32, color: c.colors.warnFg),
        title: Text(t(c).sendBeforeHandoverTitle, textAlign: TextAlign.center),
        content: Text(
          t(c).sendBeforeHandoverBody(label),
          style: TextStyle(color: c.colors.ink, height: 1.4),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(t(c).understood))],
      ),
    );
    return;
  }

  final ({String code, int validMinutes}) answer;
  try {
    answer = await _busy(context, t(context).askingCode, () => ref.read(apiProvider).handoverCode(entity, uuid));
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
        title: Text(t(c).handoverTitle(label, pointCode), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t(c).handoverBody(pointCode), style: TextStyle(color: w.ink, height: 1.4)),
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
              title: t(c).codeValidFor(answer.validMinutes),
              body: t(c).codeValidBody,
            ),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(t(c).done))],
      );
    },
  );
}

/// The log is ALREADY this account's — it just is not on this phone (a new
/// phone, a reinstall, or it was handed back). There is nobody to read a code
/// out, so none is asked: the server hands the body back to its own holder
/// without touching the holder or the code.
Future<bool> resumeOwnLogFlow(
  BuildContext context,
  WidgetRef ref, {
  required String entity,
  required String uuid,
  required String pointCode,
}) async {
  final label = _logLabel(context, entity);
  final go = await showDialog<bool>(
    context: context,
    builder: (c) {
      final w = c.colors;
      return AlertDialog(
        icon: Icon(Icons.phonelink_setup, size: 32, color: w.brand),
        title: Text(t(c).takeLogHere(label, pointCode), textAlign: TextAlign.center),
        content: Text(
          t(c).takeLogHereBody('${label[0].toUpperCase()}${label.substring(1)}'),
          style: TextStyle(color: w.ink, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t(c).cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t(c).takeToThisPhone)),
        ],
      );
    },
  );
  if (go != true || !context.mounted) return false;
  // Six digits are required by the contract, but the server never reads them
  // when the caller already holds the log.
  return _takeOver(context, ref, entity: entity, uuid: uuid, pointCode: pointCode, code: '000000');
}

/// Minta log ini kepada pemegangnya, tanpa kode.
///
/// Melengkapi [redeemHandoverFlow], tidak menggantikannya: kode melayani dua
/// orang yang berdiri berdekatan, sedangkan ini melayani keadaan sebaliknya —
/// rekan sudah di titik, pemegangnya tidak di sampingnya. Yang memindahkan
/// pegangan tetap pemegangnya; di sini ia hanya diberi tahu.
Future<bool> requestHandoverFlow(
  BuildContext context,
  WidgetRef ref, {
  required String entity,
  required String uuid,
  required String pointCode,
  String? holderName,
}) async {
  final siapa = holderName ?? t(context).colleague;
  try {
    await _busy(context, t(context).sendingRequest, () => ref.read(apiProvider).requestHandover(entity, uuid));
  } on ApiError catch (e) {
    // Sama seperti di _takeOver: 404 di sini berarti salinan titiknya usang.
    if (e.status == 404) {
      if (!context.mounted) return false;
      return _lenyap(context, ref);
    }
    if (context.mounted) showSnack(context, e.message, icon: Icons.error_outline);
    return false;
  }
  if (!context.mounted) return true;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(Icons.schedule_send, size: 32, color: c.colors.brand),
      title: Text(t(c).requestSentTitle, textAlign: TextAlign.center),
      content: Text(t(c).requestSentBody(siapa), style: TextStyle(color: c.colors.ink, height: 1.4)),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(t(c).understood))],
    ),
  );
  return true;
}

/// Pemegang menjawab permintaan yang masuk. True = log sudah BUKAN miliknya
/// lagi, dan layarnya harus ditutup.
Future<bool> answerHandoverFlow(
  BuildContext context,
  WidgetRef ref, {
  required String entity,
  required String uuid,
  required String pointCode,
  required String requesterName,
  required bool agree,
}) async {
  if (agree) {
    // Semua yang diketik di HP ini harus sampai server LEBIH DULU: isi log
    // yang diterima rekan datang dari server, bukan dari HP ini.
    await _busy(context, t(context).sendingFirst(_logLabel(context, entity)),
        () => ref.read(syncProvider.notifier).run(diminta: true));
    if (!context.mounted) return false;
  }
  try {
    await _busy(
      context,
      agree ? t(context).handingOver : t(context).rejectingRequest,
      () => ref.read(apiProvider).answerHandover(entity, uuid, agree: agree),
    );
  } on ApiError catch (e) {
    if (context.mounted) showSnack(context, e.message, icon: Icons.error_outline);
    return false;
  }
  // Tarik lagi supaya titiknya menyebut pemegang barunya; tanpa ini layar
  // sebelumnya masih menganggap log ini miliknya.
  await ref.read(syncProvider.notifier).run(diminta: true);
  try {
    await Notifications.clearHandoverRequest();
  } catch (_) {
    // Tidak ada plugin notifikasi (misalnya dalam uji).
  }
  if (context.mounted) {
    showSnack(
      context,
      agree
          ? t(context).logHandedTo(requesterName, pointCode)
          : t(context).requestRejected(requesterName),
      icon: agree ? Icons.swap_horiz : Icons.block,
    );
  }
  return agree;
}

/// Colleague types the code on the locked point. Returns true when the log is
/// now on this phone (the caller navigates to it).
Future<bool> redeemHandoverFlow(
  BuildContext context,
  WidgetRef ref, {
  required String entity,
  required String uuid,
  required String pointCode,
  String? holderName,
}) async {
  final code = await showDialog<String>(
    context: context,
    builder: (c) => _CodeDialog(
      title: t(c).continueLog(_logLabel(c, entity), pointCode),
      holderName: holderName,
      canRequest: holderName != null,
    ),
  );
  if (code == null || !context.mounted) return false;
  if (code == _minta) {
    await requestHandoverFlow(context, ref, entity: entity, uuid: uuid, pointCode: pointCode, holderName: holderName);
    return false;
  }
  return _takeOver(context, ref, entity: entity, uuid: uuid, pointCode: pointCode, code: code);
}

/// Ask the server for the whole body, store it as already-sent, then pull so
/// the point record names this phone's user as holder.
Future<bool> _takeOver(
  BuildContext context,
  WidgetRef ref, {
  required String entity,
  required String uuid,
  required String pointCode,
  required String code,
}) async {
  final p = ref.read(userProvider);
  if (p == null) return false;
  try {
    final answer = await _busy(
      context,
      t(context).takingLog(_logLabel(context, entity)),
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
    await ref.read(syncProvider.notifier).run(diminta: true);
    if (context.mounted) {
      final label = _logLabel(context, entity);
      showSnack(context, t(context).logNowHere('${label[0].toUpperCase()}${label.substring(1)}', pointCode));
    }
    return true;
  } on ApiError catch (e) {
    if (e.status == 404) {
      if (!context.mounted) return false;
      return _lenyap(context, ref);
    }
    if (context.mounted) showSnack(context, e.message, icon: Icons.error_outline);
    return false;
  }
}

/// Log yang sudah tidak ada di server: tarik titiknya lagi, lalu katakan apa
/// adanya.
///
/// ──────────────────────────────────────────────────────────────────────────
/// KENAPA INI ADA — SP.B42, 18 Oktober 2026
/// ──────────────────────────────────────────────────────────────────────────
///
/// Log bor SP.B42 dihapus dari kantor pada 15 Okt. Baris titiknya TIDAK ikut
/// maju (layanan di server saat itu menjalankan kode lama), sehingga tarikan
/// berbasis kursor tidak pernah mengirimkan versi terbarunya. HP memegang
/// salinan sebelum penghapusan — lengkap dengan uuid log yang sudah mati —
/// dan terus menawarkan "Ambil ke HP ini" untuk log yang tidak ada lagi.
///
/// Setiap ketukan menjawab 404, dan pesan "Log tidak ditemukan" terbaca
/// seperti kerusakan aplikasi. Butuh tiga jam dan pembedahan basis data
/// untuk menemukan bahwa HP-nya memang benar — salinannya saja yang usang.
///
/// 404 di jalur ini SELALU berarti salinan titik di HP ini sudah usang, jadi
/// HP memperbaiki dirinya sendiri: tarik, lalu tombolnya hilang sendiri.
/// Tanpa ini, keadaan yang sama hanya bisa dipulihkan lewat SQL.
Future<bool> _lenyap(BuildContext context, WidgetRef ref) async {
  await ref.read(syncProvider.notifier).run(diminta: true);
  if (context.mounted) {
    showSnack(context, t(context).logGoneResynced, icon: Icons.sync_problem);
  }
  return false;
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
/// Dikembalikan dialog kode saat penggunanya memilih meminta, bukan mengetik.
const _minta = '__minta__';

class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.title, this.holderName, this.canRequest = false});

  final String title;

  /// Siapa yang memegang log ini sekarang. Tanpa nama, layar ini jadi jalan
  /// buntu: ada kotak kode tetapi tidak ada petunjuk dari mana kodenya
  /// datang, dan tidak ada notifikasi apa pun yang dikirim ke pemegangnya —
  /// memang tidak dirancang begitu (lihat [offerHandover]).
  final String? holderName;

  /// Meminta hanya bisa ditawarkan kalau pemegangnya diketahui — tanpa nama,
  /// permintaannya tidak punya tujuan yang bisa disebutkan ke penggunanya.
  final bool canRequest;

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
      // scrollable: papan ketik angka menutup separuh layar begitu TextField
      // autofocus. Tanpa ini isinya tidak muat, meluber, dan tombol aksi
      // tergambar menimpa teks. Dilaporkan Daniel 18 Okt 2026 (SP.B42).
      scrollable: true,
      icon: Icon(Icons.pin_outlined, size: 32, color: w.brand),
      title: Text(widget.title, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.holderName != null) ...[
            TerraBanner(
              kind: BannerKind.info,
              icon: Icons.person_pin_circle_outlined,
              title: t(context).codeHeldBy(widget.holderName!),
              body: t(context).codeHeldByBody(widget.holderName!),
            ),
            const SizedBox(height: 10),
          ],
          Text(t(context).enterHandoverCode, style: TextStyle(color: w.ink, height: 1.4)),
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
          // "Minta ke pemegang" turun ke isi, bukan baris aksi: tiga tombol
          // tidak muat sebaris, dan OverflowBar menumpuknya ke bawah persis
          // di ruang yang sudah direbut papan ketik.
          if (widget.canRequest) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => Navigator.pop(context, _minta),
              icon: const Icon(Icons.schedule_send, size: 18),
              label: Text(t(context).askHolder),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t(context).cancel)),
        FilledButton(onPressed: _complete ? _submit : null, child: Text(t(context).takeOver)),
      ],
    );
  }
}
