import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/view_states.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/i18n.dart';

/// Every worker of the company, filterable by project.
///
/// A worker shows under a project when it is their main project or they were
/// absent there in the last [Worker.recentDays] days (see [Worker.belongsTo]),
/// so a crew borrowed by another site shows there without anyone editing it.
class WorkersPage extends ConsumerStatefulWidget {
  const WorkersPage({super.key});

  @override
  ConsumerState<WorkersPage> createState() => _WorkersPageState();
}

/// Filter value for workers with no current project.
const _noProject = 0;

class _WorkersPageState extends ConsumerState<WorkersPage> {
  /// null = all workers; [_noProject] = workers with no current project.
  int? _project;
  String _search = '';

  /// The user's own project becomes the first filter, once.
  bool _defaultApplied = false;

  static final _shortDate = DateFormat('d MMM', 'id');

  @override
  Widget build(BuildContext context) {
    final workers = ref.watch(workersProvider);
    final projects = ref.watch(projectsProvider).value ?? const <Map<String, Object?>>[];
    final canAdd = ref.watch(sessionProvider).value?.allows('field_worker', 'create') ?? false;
    final codes = {for (final p in projects) ?toIntOrNull(p['id']): '${p['code']}'};
    final mine = ref.watch(myProjectProvider);
    if (!_defaultApplied && mine.hasValue) {
      _defaultApplied = true;
      _project = mine.value;
    }
    return Scaffold(
      appBar: AppBar(title: Text(t(context).workersTitle)),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () {
                final project = _project == null || _project == _noProject ? '' : '?project=$_project';
                context.push('/workers/new$project');
              },
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(t(context).newWorker),
            )
          : null,
      body: workers.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(title: t(context).workersLoadError, message: '$e'),
        data: (all) => _list(all, codes),
      ),
    );
  }

  Widget _list(List<Worker> all, Map<int, String> codes) {
    final today = DateTime.now();
    // Chips only for projects that have someone on them, ordered by code.
    final counts = <int, int>{};
    var withoutProject = 0;
    for (final k in all) {
      final on = k.projectsOn(today);
      if (on.isEmpty) withoutProject++;
      for (final id in on) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    final chipIds = counts.keys.where(codes.containsKey).toList()..sort((a, b) => codes[a]!.compareTo(codes[b]!));
    // A filter whose project has emptied out falls back to all workers.
    final project = (_project == null || _project == _noProject || counts.containsKey(_project)) ? _project : null;

    final query = normalizeName(_search);
    final items = [
      for (final k in all)
        if ((project == null ||
                (project == _noProject ? k.projectsOn(today).isEmpty : k.belongsTo(project, today))) &&
            (query.isEmpty || normalizeName(k.name).contains(query) || (k.phone ?? '').contains(_search.trim())))
          k,
    ];

    final description = switch (project) {
      null => t(context).workersAllBody,
      _noProject => t(context).workersNoProjectBody('${Worker.recentDays}'),
      _ => t(context).workersProjectBody('${codes[project]}', '${Worker.recentDays}'),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, Dimens.pagePadding, Dimens.pagePadding, 96),
      children: [
        PageHeader(title: t(context).workersCount(items.length), description: description),
        if (all.isEmpty)
          EmptyState(message: t(context).noWorkersYet)
        else ...[
          TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t(context).searchNameOrPhone),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(t(context).allCount(all.length), project == null, () => setState(() => _project = null)),
                for (final id in chipIds)
                  _chip('${codes[id]} (${counts[id]})', project == id, () => setState(() => _project = id)),
                if (withoutProject > 0)
                  _chip(t(context).withoutProject(withoutProject), project == _noProject, () => setState(() => _project = _noProject)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty) EmptyState(message: t(context).noMatchingWorkers),
          for (final k in items) _card(k, codes),
        ],
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );

  Widget _card(Worker k, Map<int, String> codes) {
    final w = context.colors;
    final details = <String>[
      if (k.projectId != null && codes[k.projectId] != null) t(context).mainProjectIs('${codes[k.projectId]}'),
      if (k.lastProjectId != null && k.lastSeenDate != null)
        t(context).lastSeenAt(codes[k.lastProjectId] ?? t(context).otherProject, _shortDate.format(k.lastSeenDate!)),
      if (k.phone != null && k.phone!.isNotEmpty) k.phone!,
    ];
    return ListCard(
      onTap: () => context.push('/workers/${k.uuid}'),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: w.brandSoft, child: Icon(Icons.person, color: w.brandStrong)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k.name, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
                for (final d in details) Text(d, style: TextStyle(color: w.muted, fontSize: 13)),
              ],
            ),
          ),
          if (k.isLocal) StatusBadge.sendStatus(context, 'pending'),
        ],
      ),
    );
  }
}
