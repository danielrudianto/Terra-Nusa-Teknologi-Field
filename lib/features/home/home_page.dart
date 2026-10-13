import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/features.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';
import '../../core/util/format.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/list_card.dart';
import 'status_banners.dart';
import 'watched_logs.dart';
import '../settings/power_guide.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final session = ref.watch(sessionProvider).value;
    final user = session?.user;
    final projects = ref.watch(projectsProvider).value ?? const [];
    // HP yang sudah digantikan dan lewat masa tenggang hanya boleh
    // mengirim sisa antreannya; pintu masuk pekerjaan baru ditutup di
    // sini, dan sebabnya sudah terbaca di banner atas.
    final canRecord = ref.watch(canRecordProvider);
    final canAttend = canRecord && Features.attendance && (session?.allows('field_attendance', 'create') ?? false);
    final canCast = canRecord && (session?.allows('field_casting', 'create') ?? false);
    final canViewWorkers = Features.attendance && (session?.allows('field_worker', 'read') ?? false);
    // What was drilled and cast across projects: directors (level 5+) and
    // Engineering from level 3 — the same rule as GET /field/reports.
    final level = session?.permissions.level ?? 0;
    final engineering = session?.permissions.departments.contains('engineering') ?? false;
    final canReport = (level >= 5 || (level >= 3 && engineering)) && (session?.allows('field_casting', 'read') ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TerraBot Field'),
        actions: [
          IconButton(
            tooltip: t(context).settingsTitle,
            onPressed: () => context.push('/settings'),
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: w.brandSoft,
              child: Text(user?.initials ?? '?', style: TextStyle(fontSize: 12, color: w.brandStrong, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncProvider.notifier).run(diminta: true),
        child: ListView(
          padding: const EdgeInsets.all(Dimens.pagePadding),
          children: [
            _Hero(name: user?.name.split(' ').first ?? ''),
            const SizedBox(height: 18),
            const StatusBanners(),
            const PowerBanner(),
            const _WatchedCard(),
            if (projects.isEmpty)
              TerraBanner(
                kind: BannerKind.info,
                title: t(context).projectsMissingTitle,
                body: t(context).projectsMissingHome,
              ),
            if (!canAttend && !canCast)
              TerraBanner(
                kind: BannerKind.warning,
                title: t(context).noFieldAccess,
                body: t(context).noFieldAccessBody,
              ),
            if (canAttend)
              _Shortcut(
                icon: Icons.how_to_reg,
                title: t(context).shortcutAttendance,
                body: t(context).shortcutAttendanceBody,
                onTap: () => context.push('/attendance/new'),
              ),
            if (canCast)
              _Shortcut(
                icon: Icons.foundation,
                title: t(context).shortcutCasting,
                body: t(context).shortcutCastingBody,
                onTap: () => context.go('/casting'),
              ),
            if (canViewWorkers)
              _Shortcut(
                icon: Icons.groups_outlined,
                title: t(context).shortcutWorkers,
                body: t(context).shortcutWorkersBody,
                onTap: () => context.push('/workers'),
              ),
            if (canReport)
              _Shortcut(
                icon: Icons.insights,
                title: t(context).shortcutReports,
                body: t(context).shortcutReportsBody,
                onTap: () => context.push('/reports'),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Sedang dipantau": the running drill and casting logs THIS user holds, one
/// tap back into each. Gone once a log is finished or handed over (Oper).
class _WatchedCard extends ConsumerWidget {
  const _WatchedCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final items = ref.watch(watchedLogsProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(t(context).homeWatched,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: -0.2, color: w.ink)),
              ),
              Text(t(context).homeWatchedCount(items.length), style: TextStyle(color: w.muted, fontSize: 13)),
            ],
          ),
        ),
        for (final (i, l) in items.indexed)
          AppearIn(
            key: ValueKey(l.uuid),
            order: i,
            child: ListCard(
              onTap: () => context.push(l.route),
              edgeColor: l.entity == 'drill_log' ? w.warnFg : w.checkedFg,
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: l.entity == 'drill_log' ? w.warnBg : w.checkedBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      l.entity == 'drill_log' ? Icons.construction : Icons.foundation,
                      color: l.entity == 'drill_log' ? w.warnFg : w.checkedFg,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${l.entity == 'drill_log' ? t(context).labelDrill : t(context).labelCast} ${l.pointCode}',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: w.ink)),
                        Text(
                          [
                            if (l.projectCode != null) l.projectCode!,
                            l.entity == 'drill_log' ? t(context).homeDrillRunning : t(context).homeCastRunning,
                          ].join(' · '),
                          style: TextStyle(color: w.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: w.faint),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }
}

/// Greeting card at the top of Home: deep navy, with the rings of a pile
/// cross-section as a quiet motif, and how much is still waiting to be sent.
class _Hero extends ConsumerWidget {
  const _Hero({required this.name});

  final String name;

  static const _navy = Color(0xFF0B1F5C);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.colors;
    final pending = (ref.watch(pendingCountProvider).value ?? 0) + (ref.watch(pendingPhotoCountProvider).value ?? 0);
    final project = ref.watch(myProjectRecordProvider);
    Widget pill(IconData icon, String text, {VoidCallback? onTap}) => Material(
          color: Colors.white.withValues(alpha: 0.14),
          shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.18))),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(text,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy, Color.lerp(_navy, w.brand, 0.75)!],
        ),
        boxShadow: [
          BoxShadow(color: _navy.withValues(alpha: 0.28), offset: const Offset(0, 10), blurRadius: 24),
        ],
      ),
      child: Stack(
        children: [
          for (final (size, alpha) in const [(220.0, 0.06), (150.0, 0.08), (84.0, 0.10)])
            Positioned(
              right: -40 + (220 - size) / 2,
              top: -50 + (220 - size) / 2,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: alpha), width: 14),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(longDate(DateTime.now()).toUpperCase(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Colors.white.withValues(alpha: 0.72))),
                const SizedBox(height: 6),
                Text(t(context).homeGreeting(name),
                    style: const TextStyle(fontSize: 28, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: Colors.white)),
                const SizedBox(height: 4),
                Text(t(context).homeTagline,
                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.78))),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    pill(
                      Icons.location_city_outlined,
                      project == null ? t(context).homePickProject : '${project['code']} · ${project['name']}',
                      onTap: () => context.push('/settings'),
                    ),
                    pill(
                      pending == 0 ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
                      pending == 0 ? t(context).homeAllSent : t(context).homePending(pending),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.icon, required this.title, required this.body, required this.onTap});

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return ListCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [w.brand, w.brandStrong],
              ),
              boxShadow: [BoxShadow(color: w.brand.withValues(alpha: 0.25), offset: const Offset(0, 6), blurRadius: 12)],
            ),
            child: Icon(icon, color: w.onBrand, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: -0.2, color: w.ink)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(color: w.muted, fontSize: 13, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: w.surface2, shape: BoxShape.circle, border: Border.all(color: w.line)),
            child: Icon(Icons.arrow_forward_rounded, size: 18, color: w.ink),
          ),
        ],
      ),
    );
  }
}
