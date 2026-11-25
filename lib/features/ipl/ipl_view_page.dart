import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/widgets/view_states.dart';
import 'ipl_share.dart';

/// ONE EARLIER IPL, as the sheet the office sees (Daniel, 25 Nov 2026:
/// "di app bikin bisa lihat IPL IPL sebelumnya").
///
/// The sheet is drawn by the server — the same image as the web preview and
/// as "share", with the confirmer's signature once confirmed — so it needs
/// the internet. Pinch to zoom: the sheet is an A4 table, unreadable at
/// phone width without it.
class IplViewPage extends ConsumerStatefulWidget {
  const IplViewPage({
    super.key,
    required this.iplId,
    required this.title,
    required this.fileStem,
    required this.confirmed,
    required this.canShare,
  });

  final int iplId;
  final String title;
  final String fileStem;
  final bool confirmed;

  /// A rejected IPL can be looked at, not sent around.
  final bool canShare;

  @override
  ConsumerState<IplViewPage> createState() => _IplViewPageState();
}

class _IplViewPageState extends ConsumerState<IplViewPage> {
  late Future<Uint8List> _sheet = _load();

  Future<Uint8List> _load() async =>
      Uint8List.fromList(await ref.read(apiProvider).iplFile(widget.iplId, pdf: false));

  @override
  Widget build(BuildContext context) {
    final l = t(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.canShare)
            IconButton(
              tooltip: l.iplShare,
              icon: const Icon(Icons.ios_share),
              onPressed: () => shareIpl(
                context,
                iplId: widget.iplId,
                fileStem: widget.fileStem,
                confirmed: widget.confirmed,
              ),
            ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: _sheet,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingState();
          if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
            final e = snap.error;
            return ErrorState(
              title: l.iplViewFailed,
              message: e is ApiError ? e.message : (e == null ? null : '$e'),
              onRetry: () => setState(() => _sheet = _load()),
            );
          }
          return InteractiveViewer(
            maxScale: 5,
            child: Center(child: Image.memory(snap.data!, fit: BoxFit.contain)),
          );
        },
      ),
    );
  }
}
