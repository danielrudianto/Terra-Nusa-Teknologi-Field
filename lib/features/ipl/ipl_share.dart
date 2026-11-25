import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n.dart';
import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';

/// SHARE AN IPL from the phone (Daniel, 25 Nov 2026: "IPL bisa di share
/// dari app ga sih?").
///
/// Asks image or PDF, fetches that sheet from the server, and opens the
/// share sheet (WhatsApp, e-mail…). The sheet comes from the server and not
/// from the phone because only the server holds the confirmer's signature —
/// the same rule as the web. That also means it needs the internet at the
/// moment of sharing; the error says so in a sentence.
///
/// [fileStem] names the file the recipient sees, e.g. `IPL-R501-2026-11-25`.
Future<void> shareIpl(
  BuildContext context, {
  required int iplId,
  required String fileStem,
  required bool confirmed,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _ShareSheet(iplId: iplId, fileStem: fileStem, confirmed: confirmed),
  );
}

/// `IPL-<project code>-<yyyy-mm-dd>`, without characters a file name or
/// WhatsApp would choke on.
String iplFileStem(String projectCode, String date) {
  final code = projectCode.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '');
  final day = date.length >= 10 ? date.substring(0, 10) : date;
  return ['IPL', if (code.isNotEmpty) code, day].join('-');
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.iplId, required this.fileStem, required this.confirmed});

  final int iplId;
  final String fileStem;
  final bool confirmed;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  /// Which choice is fetching: 'png' | 'pdf' | null. One at a time.
  String? _busy;

  /// Shown INSIDE the sheet: a snack bar would sit underneath it, unseen.
  String? _error;

  Future<void> _share({required bool pdf}) async {
    final l = t(context);
    final nav = Navigator.of(context);
    setState(() {
      _busy = pdf ? 'pdf' : 'png';
      _error = null;
    });
    try {
      final bytes = await ref.read(apiProvider).iplFile(widget.iplId, pdf: pdf);
      final f = File('${(await getTemporaryDirectory()).path}/${widget.fileStem}.${pdf ? 'pdf' : 'png'}');
      await f.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      nav.pop();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(f.path, mimeType: pdf ? 'application/pdf' : 'image/png')],
          subject: widget.fileStem,
        ),
      );
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = l.iplShareFailed(e.message);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = l.iplShareFailed('$e');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = t(context);
    final w = context.colors;
    Widget tail(String which) => _busy == which
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Icon(Icons.chevron_right, color: w.muted);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l.iplShare, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: w.ink)),
            ),
            // Before confirmation there is no signature to send: say so
            // BEFORE the sheet goes out, not after someone asks.
            if (!widget.confirmed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 20, color: w.warnFg),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l.iplShareDraftNote, style: TextStyle(color: w.ink, height: 1.35))),
                  ],
                ),
              ),
            ListTile(
              leading: Icon(Icons.image_outlined, color: w.brand),
              title: Text(l.iplShareImage, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(l.iplShareImageHint),
              trailing: tail('png'),
              enabled: _busy == null,
              onTap: () => _share(pdf: false),
            ),
            ListTile(
              leading: Icon(Icons.picture_as_pdf_outlined, color: w.brand),
              title: Text(l.iplSharePdf, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(l.iplSharePdfHint),
              trailing: tail('pdf'),
              enabled: _busy == null,
              onTap: () => _share(pdf: true),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 20, color: w.badFg),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: TextStyle(color: w.badFg, height: 1.35))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
