import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/device_power.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/widgets/terra_banner.dart';

/// This phone's battery / auto-start state. Re-read when the app comes back
/// to the front (FieldApp), i.e. right after the user changed it.
final powerStatusProvider = FutureProvider<PowerStatus?>((ref) => DevicePower.status());

/// Steps + buttons to let TerraBot Field run in the background, worded for
/// the brand of this phone. Shown from the Home banner and from Pengaturan.
Future<void> showPowerGuide(BuildContext context, PowerStatus status) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) {
      final w = c.colors;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, 0, Dimens.pagePadding, Dimens.pagePadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Biarkan TerraBot Field jalan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: w.ink)),
              const SizedBox(height: 6),
              Text(
                'HP ini mematikan aplikasi yang tidak sedang dibuka. Tanpa pengaturan di bawah, getar pengingat cor '
                '(20 menit, jeda) dan kirim otomatis TIDAK jalan saat layar mati.',
                style: TextStyle(color: w.muted, height: 1.4),
              ),
              const SizedBox(height: 14),
              for (final (i, s) in status.steps.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: w.brandSoft,
                        child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: w.brandStrong)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s, style: TextStyle(color: w.ink, height: 1.4))),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              if (status.hasAutostart) ...[
                SizedBox(
                  height: Dimens.minTouch,
                  child: FilledButton.icon(
                    onPressed: () async {
                      if (!await DevicePower.openAutostart()) await DevicePower.openAppSettings();
                    },
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Buka pengaturan Mulai otomatis'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                height: Dimens.minTouch,
                child: status.hasAutostart
                    ? OutlinedButton.icon(
                        onPressed: DevicePower.openAppSettings,
                        icon: const Icon(Icons.battery_charging_full),
                        label: const Text('Buka pengaturan Baterai aplikasi'),
                      )
                    : FilledButton.icon(
                        onPressed: DevicePower.openAppSettings,
                        icon: const Icon(Icons.battery_charging_full),
                        label: const Text('Buka pengaturan Baterai aplikasi'),
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Home banner while battery optimisation is still on for this app.
class PowerBanner extends ConsumerWidget {
  const PowerBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(powerStatusProvider).value;
    if (status == null || status.unrestricted) return const SizedBox.shrink();
    return TerraBanner(
      kind: BannerKind.warning,
      icon: Icons.battery_alert_outlined,
      title: 'Atur baterai HP sekali saja',
      body: 'Supaya getar pengingat cor dan kirim otomatis tetap jalan saat layar mati.',
      action: TextButton(onPressed: () => showPowerGuide(context, status), child: const Text('Atur')),
    );
  }
}
