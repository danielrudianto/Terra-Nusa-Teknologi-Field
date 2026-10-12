import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/i18n.dart';

/// Pick the rig operator of a drill log from the company's workers, or
/// register a new one on the spot. Returns the worker uuid.
///
/// Operators are ordinary workers (`field_workers`), so the weekly
/// "who drilled how many metres" recap counts one person once, however the
/// name gets typed later.
Future<String?> pickOperator(BuildContext context, {String? current}) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OperatorSheet(current: current),
    );

class _OperatorSheet extends ConsumerStatefulWidget {
  const _OperatorSheet({this.current});

  final String? current;

  @override
  ConsumerState<_OperatorSheet> createState() => _OperatorSheetState();
}

class _OperatorSheetState extends ConsumerState<_OperatorSheet> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _adding = false;
  String? _problem;

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _addNew(List<Worker> all) async {
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.length < 2) {
      setState(() => _problem = t(context).operatorNameRequired);
      return;
    }
    final phone = _phone.text.trim();
    final uuid = newUuid();
    // A worker with the same name or phone is most likely the same person.
    final same = possibleDuplicates(all, uuid: uuid, name: name, phone: phone.isEmpty ? null : phone);
    if (same.isNotEmpty && _problem == null) {
      setState(() => _problem = t(context).operatorExists(same.first.name));
      return;
    }
    final p = ref.read(userProvider);
    if (p == null) return;
    await ref.read(dbProvider).saveDocument(
      uuid: uuid,
      entity: 'worker',
      userId: p.id,
      body: {
        'name': name,
        'projectID': ref.read(myProjectProvider).value,
        'phone': phone.isEmpty ? null : phone,
        'facePhotoUuid': null,
        'note': 'Operator bor',
        'isActive': true,
      },
    );
    ref.read(syncProvider.notifier).afterSave();
    if (mounted) Navigator.pop(context, uuid);
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final all = ref.watch(workersProvider).value ?? const <Worker>[];
    final q = normalizeName(_search.text);
    final shown = [
      for (final k in all)
        if (k.active && (q.isEmpty || normalizeName(k.name).contains(q))) k,
    ]..sort((a, b) => a.name.compareTo(b.name));

    return Padding(
      padding: sheetPadding(context),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_adding ? t(context).newOperator : t(context).drillOperator, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: w.ink)),
            const SizedBox(height: 10),
            if (_adding) ...[
              if (_problem != null) TerraBanner(kind: BannerKind.warning, title: t(context).checkFirst, body: _problem),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: t(context).operatorName),
                onChanged: (_) => setState(() => _problem = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t(context).phoneOptional),
              ),
              const Spacer(),
              SizedBox(height: Dimens.minTouch + 4, child: FilledButton(onPressed: () => _addNew(all), child: Text(t(context).save))),
              TextButton(onPressed: () => setState(() => _adding = false), child: Text(t(context).backToList)),
            ] else ...[
              TextField(
                controller: _search,
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t(context).searchName),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: shown.isEmpty
                    ? Center(child: Text(t(context).noMatchAddNew, style: TextStyle(color: w.muted)))
                    : ListView(
                        children: [
                          for (final k in shown)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(backgroundColor: w.brandSoft, child: Icon(Icons.engineering, color: w.brandStrong)),
                              title: Text(k.name, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
                              subtitle: k.phone == null || k.phone!.isEmpty ? null : Text(k.phone!),
                              trailing: k.uuid == widget.current ? Icon(Icons.check_circle, color: w.brand) : null,
                              onTap: () => Navigator.pop(context, k.uuid),
                            ),
                        ],
                      ),
              ),
              SizedBox(
                height: Dimens.minTouch,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _adding = true;
                    _name.text = _search.text;
                  }),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Operator baru'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
