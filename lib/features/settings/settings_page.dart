import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config/env.dart';
import '../../core/config/features.dart';
import '../../core/device/notifications.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme/appearance.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';
import '../../core/util/app_log.dart';
import '../../core/util/format.dart';
import '../../core/widgets/terra_banner.dart';
import 'power_guide.dart';

/// Settings, laid out like Pengaturan on m.terrabot (`mobile/pengaturan`):
/// big title, account card, then sections under small uppercase labels,
/// each made of full-width option tiles. The two apps sit side by side on
/// the same phones, so they should feel like one product.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final appContext = ref.watch(appContextProvider);
    final session = ref.watch(sessionProvider).value;
    final user = session?.user;
    final departments = session?.permissions.departments ?? const <String>[];
    final pendingDocs = ref.watch(pendingCountProvider).value ?? 0;
    final photo = ref.watch(pendingPhotoCountProvider).value ?? 0;

    return Scaffold(
      // Judulnya di bilah atas, bukan di badan — Pengaturan sekarang TAB,
      // dan halaman tab lain (Cor, Antrean) menaruh judulnya di situ. Bilah
      // kosong dengan judul di bawahnya adalah bentuk halaman yang DITUMPUK,
      // lengkap dengan ruang untuk panah balik yang tidak ada lagi.
      appBar: AppBar(title: Text(t(context).settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, 4, Dimens.pagePadding, 32),
        children: [

          // --- account ----------------------------------------------------
          _Box(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 23,
                  backgroundColor: w.brand,
                  child: Text(user?.initials ?? '?',
                      style: TextStyle(color: w.onBrand, fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.name ?? '–', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: w.ink)),
                      Text(user?.email ?? '', overflow: TextOverflow.ellipsis, style: TextStyle(color: w.muted, fontSize: 13)),
                      Text(
                        [t(context).settingsLevel('${session?.permissions.level ?? '–'}'), if (departments.isNotEmpty) departments.join(', ')].join(' · '),
                        style: TextStyle(color: w.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          _Section(t(context).sectionAppearance),
          const _AppearanceCard(),

          _Section(t(context).sectionMyProject),
          const _MyProjectOptions(),

          _Section(t(context).sectionNotifications),
          const _NotificationTile(),
          const _PowerTile(),

          _Section(t(context).sectionAccount),
          _Tile(
            icon: Icons.refresh,
            title: t(context).reloadPermissions,
            subtitle: t(context).reloadPermissionsBody,
            onTap: () async {
              await ref.read(sessionProvider.notifier).reloadPermissions();
              if (!context.mounted) return;
              _snack(context, t(context).permissionsReloaded);
            },
          ),
          const SizedBox(height: 8),
          if (pendingDocs > 0 || photo > 0)
            TerraBanner(
              kind: BannerKind.warning,
              title: t(context).logoutPendingTitle(pendingDocs, photo),
              body: t(context).logoutPendingBody,
            ),
          _LogoutButton(onPressed: () => _logout(context, ref)),

          _Section(t(context).sectionAbout),
          _Tile(
            icon: Icons.info_outline,
            title: t(context).appVersion,
            // VERSI APLIKASI DI BARIS SENDIRI, lengkap dengan nomor build.
            //
            // Sebelumnya versi dan alamat server berdempet satu baris —
            // "v1.0.12 · services.terrabot…" — dan terbaca seperti versi
            // SERVER, bukan versi aplikasi ini. Nomor build juga tidak ada,
            // padahal justru itu yang membedakan dua rilis bernama sama
            // ketika kru ditanya "HP-mu sudah versi berapa?".
            subtitle: 'v${Env.appVersion}\n'
                '${t(context).serverLabel(Env.apiUrl.replaceFirst('https://', ''))}\n'
                '${t(context).deviceIdLabel(appContext.deviceId.substring(0, 8))}',
          ),
          _Tile(
            icon: Icons.bug_report_outlined,
            title: t(context).sendLog,
            subtitle: t(context).sendLogBody,
            onTap: () => _sendLog(context, appContext.deviceId),
          ),
        ],
      ),
    );
  }

  /// Share the on-phone error log (WhatsApp, email…) so the admin can read
  /// what went wrong without touching the phone.
  Future<void> _sendLog(BuildContext context, String deviceId) async {
    final text = await AppLog.read();
    if (!context.mounted) return;
    if (text.trim().isEmpty) {
      _snack(context, t(context).noLogYet);
      return;
    }
    try {
      final file = File('${(await getTemporaryDirectory()).path}/terrabot-field-${deviceId.substring(0, 8)}.log');
      await file.writeAsString(
        'TerraBot Field v${Env.appVersion} · perangkat ${deviceId.substring(0, 8)} · ${Env.apiUrl}\n\n$text',
        flush: true,
      );
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'text/plain')], subject: 'Log TerraBot Field'),
      );
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, t(context).logShareFailed('$e'));
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.logout, size: 32),
        title: Text(t(context).logoutConfirm, textAlign: TextAlign.center),
        content: Text(t(context).logoutConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t(context).cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t(context).logout)),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(sessionProvider.notifier).logout();
    if (context.mounted) context.go('/login');
  }
}

void _snack(BuildContext context, String text) {
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

/// Small uppercase label above a group (`.mst-seksi`).
/// Tema, warna aksen, ukuran teks. Saved as one meta value, applied live
/// by [appearanceProvider]; defaults when nothing is saved yet.
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  Future<void> _save(WidgetRef ref, Appearance a) =>
      ref.read(dbProvider).writeMeta(appearanceKey, a.encode());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final a = ref.watch(appearanceProvider).value ?? const Appearance();
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: w.surface,
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
        boxShadow: w.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label(t(context).settingsTheme),
          Row(
            children: [
              for (final (i, (mode, text, icon)) in [
                (ThemeMode.system, t(context).themeSystem, Icons.smartphone),
                (ThemeMode.light, t(context).themeLight, Icons.light_mode_outlined),
                (ThemeMode.dark, t(context).themeDark, Icons.dark_mode_outlined),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _ChoiceButton(
                    selected: a.mode == mode,
                    icon: icon,
                    text: text,
                    onTap: () => _save(ref, a.copyWith(mode: mode)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          label(t(context).settingsAccent),
          Row(
            children: [
              for (final (i, opt) in accentOptions.indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: _accentLabel(context, opt.id),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Dimens.radiusBanner),
                      onTap: () => _save(ref, a.copyWith(accentId: opt.id)),
                      child: Column(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).brightness == Brightness.dark ? opt.darkBrand : opt.lightBrand,
                              border: a.accentId == opt.id ? Border.all(color: w.ink, width: 2.5) : null,
                            ),
                            child: a.accentId == opt.id
                                ? Icon(Icons.check,
                                    size: 20,
                                    color: Theme.of(context).brightness == Brightness.dark ? w.pageBg : Colors.white)
                                : null,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _accentLabel(context, opt.id),
                            style: TextStyle(fontSize: 12, color: a.accentId == opt.id ? w.ink : w.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          // Four across would be cramped on a small phone, so the languages
          // wrap instead of being squeezed into equal columns.
          label(t(context).settingsLanguage),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (code, text) in [
                (null, t(context).languageSystem),
                ('id', t(context).languageIndonesian),
                ('en', t(context).languageEnglish),
                ('zh', t(context).languageChinese),
              ])
                SizedBox(
                  width: 112,
                  child: _ChoiceButton(
                    selected: a.languageCode == code,
                    text: text,
                    onTap: () => _save(ref, a.withLanguage(code)),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(t(context).settingsLanguageBody, style: TextStyle(color: w.muted, fontSize: 13, height: 1.35)),
          ),
          const SizedBox(height: 16),
          label(t(context).settingsTextSize),
          Row(
            children: [
              for (final (i, (_, scale)) in textScaleOptions.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _ChoiceButton(
                    selected: a.textScale == scale,
                    text: _textSizeLabel(context, i),
                    onTap: () => _save(ref, a.copyWith(textScale: scale)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One option in a row of equals: outlined, filled soft when selected.
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({required this.selected, required this.text, required this.onTap, this.icon});

  final bool selected;
  final String text;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(Dimens.radiusBanner),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: Dimens.minTouch),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? w.brandSoft : w.surface,
          borderRadius: BorderRadius.circular(Dimens.radiusBanner),
          border: Border.all(color: selected ? w.brand : w.border, width: selected ? 1.6 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) Icon(icon, size: 20, color: selected ? w.brandStrong : w.muted),
            if (icon != null) const SizedBox(height: 2),
            FittedBox(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? w.brandStrong : w.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 22, 0, 9),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: context.colors.faint),
        ),
      );
}

/// White rounded box with a hairline border (`.mst-akun`).
class _Box extends StatelessWidget {
  const _Box({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: w.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: w.border),
        boxShadow: const [BoxShadow(color: Color(0x0D090C12), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: child,
    );
  }
}

/// Full-width option tile (`.mst-tema__opsi`). [selected] turns it brand-tinted
/// with a check, like the chosen theme on m.terrabot.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.selected = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      // Menyusut saat ditekan, sama seperti ListCard. Riaknya tetap ada —
      // TapScale memantau pointer, bukan gestur, jadi tap tetap milik
      // InkWell di dalamnya.
      child: TapScale(
        child: Material(
        color: selected ? w.brandSoft : w.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? w.brand : w.border, width: selected ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Dimens.motionFast,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: selected ? w.brand : w.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: selected ? w.brandStrong : w.ink,
                          )),
                      if (subtitle != null)
                        Text(subtitle!, style: TextStyle(color: w.muted, fontSize: 13, height: 1.35)),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else if (selected)
                  Icon(Icons.check_circle, color: w.brand),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}

/// "Proyek saya": the site this user works on for the coming weeks.
///
/// One tile per ongoing project, like the theme choice on m.terrabot — one
/// tap, no dropdown to open and scroll. Tapping the chosen one again clears it.
class _MyProjectOptions extends ConsumerWidget {
  const _MyProjectOptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final mine = ref.watch(myProjectProvider).value;
    final projects = ref.watch(projectsProvider);
    final all = projects.value ?? const <Map<String, Object?>>[];
    final choices = [
      for (final p in all)
        if (!isRetentionProject(p) || '${p['id']}' == '$mine') p,
    ];

    Future<void> choose(int? id) async {
      await ref.read(myProjectProvider.notifier).choose(id);
      if (!context.mounted) return;
      _snack(context, id == null ? t(context).myProjectCleared : t(context).myProjectSaved);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text(
              Features.attendance
                  ? t(context).myProjectBodyAttendance
                  : t(context).myProjectBody,
              style: TextStyle(color: w.muted, height: 1.4)),
        ),
        if (projects.hasError)
          TerraBanner(kind: BannerKind.danger, title: t(context).projectsLoadFailed, body: '${projects.error}')
        else if (projects.hasValue && choices.isEmpty)
          TerraBanner(
            kind: BannerKind.info,
            title: t(context).projectsMissingTitle,
            body: t(context).projectsMissingBody,
          ),
        for (final p in choices)
          _Tile(
            icon: Icons.location_city_outlined,
            title: '${p['code']}',
            subtitle: '${p['name']}',
            selected: '${p['id']}' == '$mine',
            onTap: () {
              final id = toIntOrNull(p['id']);
              choose(id == mine ? null : id);
            },
          ),
      ],
    );
  }
}

/// Whether the casting reminders can buzz. Off = the reminders after 20
/// minutes and during a pause never reach the user.
class _NotificationTile extends ConsumerWidget {
  const _NotificationTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final on = ref.watch(notificationsEnabledProvider).value ?? true;
    return _Tile(
      icon: on ? Icons.notifications_active : Icons.notifications_off,
      title: t(context).notifTitle,
      subtitle: on
          ? t(context).notifOn
          : t(context).notifOff,
      selected: on,
      trailing: Icon(on ? Icons.toggle_on : Icons.toggle_off, size: 34, color: on ? w.brand : w.muted),
      onTap: on
          ? null
          : () async {
              await Notifications.requestPermission();
              ref.invalidate(notificationsEnabledProvider);
            },
    );
  }
}

/// Battery saving for this app: "Tanpa batasan" or not, and the brand's
/// steps to fix it.
class _PowerTile extends ConsumerWidget {
  const _PowerTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final status = ref.watch(powerStatusProvider).value;
    if (status == null) return const SizedBox.shrink();
    final ok = status.unrestricted;
    return _Tile(
      icon: ok ? Icons.battery_full : Icons.battery_alert_outlined,
      title: t(context).powerTitle,
      subtitle: ok
          ? t(context).powerOk
          : t(context).powerRestricted,
      selected: ok,
      trailing: Icon(Icons.chevron_right, color: w.muted),
      onTap: () => showPowerGuide(context, status),
    );
  }
}

/// Red-tinted full-width button (`.mst-keluar`).
class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Material(
      color: w.badBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: w.badFg.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout, size: 20, color: w.badFg),
              const SizedBox(width: 8),
              Text('Keluar', style: TextStyle(color: w.badFg, fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nama warna aksen dan ukuran teks, diterjemahkan.
///
/// Datanya (`accentOptions`, `textScaleOptions`) tetap berisi nilai, bukan
/// kalimat: yang disimpan di HP adalah id dan angkanya, jadi mengganti
/// bahasa tidak boleh mengubah apa pun yang tersimpan.
String _accentLabel(BuildContext context, String id) => switch (id) {
      'jingga' => t(context).accentOrange,
      'teal' => t(context).accentTeal,
      'ungu' => t(context).accentPurple,
      _ => t(context).accentBlue,
    };

String _textSizeLabel(BuildContext context, int i) => switch (i) {
      1 => t(context).textSizeLarge,
      2 => t(context).textSizeHuge,
      _ => t(context).textSizeNormal,
    };
