import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/i18n.dart';

/// Shown INSTEAD of the whole app while the server refuses this version
/// (`FIELD_MIN_APP_VERSION`). Nothing can be entered in the old format any
/// more; what is already on the phone stays and goes out after the update.
class UpdateRequiredPage extends ConsumerStatefulWidget {
  const UpdateRequiredPage({super.key, required this.info});

  final AppOutdated info;

  @override
  ConsumerState<UpdateRequiredPage> createState() => _UpdateRequiredPageState();
}

class _UpdateRequiredPageState extends ConsumerState<UpdateRequiredPage> {
  bool _checking = false;

  Future<void> _open() async {
    final url = Uri.tryParse(widget.info.downloadUrl ?? '');
    if (url == null) return;
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  /// Ask the server again: the minimum may have been lowered meanwhile.
  Future<void> _check() async {
    setState(() => _checking = true);
    await ref.read(syncProvider.notifier).run();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final pending = (ref.watch(pendingCountProvider).value ?? 0) + (ref.watch(pendingPhotoCountProvider).value ?? 0);
    final hasLink = (widget.info.downloadUrl ?? '').isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Dimens.pagePadding * 1.5),
          children: [
            const SizedBox(height: 40),
            Center(
              child: CircleAvatar(
                radius: 44,
                backgroundColor: w.brandSoft,
                child: Icon(Icons.system_update, size: 44, color: w.brand),
              ),
            ),
            const SizedBox(height: 24),
            Text(t(context).updateTitle,
                textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: w.ink)),
            const SizedBox(height: 8),
            Text(
              t(context).updateBody(Env.appVersion, widget.info.minVersion),
              textAlign: TextAlign.center,
              style: TextStyle(color: w.muted, height: 1.45),
            ),
            const SizedBox(height: 24),
            TerraBanner(
              kind: pending > 0 ? BannerKind.warning : BannerKind.info,
              icon: Icons.lock_outline,
              title: pending > 0 ? t(context).unsentSafeHere(pending) : t(context).dataSafeHere,
              body: t(context).installOverBody,
            ),
            const SizedBox(height: 16),
            if (hasLink)
              SizedBox(
                height: Dimens.minTouch + 4,
                child: FilledButton.icon(
                  onPressed: _open,
                  icon: const Icon(Icons.download),
                  label: Text(t(context).downloadNew),
                ),
              )
            else
              TerraBanner(
                kind: BannerKind.info,
                title: t(context).askAdminApk,
                body: t(context).askAdminApkBody,
              ),
            const SizedBox(height: 10),
            SizedBox(
              height: Dimens.minTouch,
              child: OutlinedButton.icon(
                onPressed: _checking ? null : _check,
                icon: _checking
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: Text(t(context).checkAgain),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
