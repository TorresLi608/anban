import 'package:flutter/material.dart';

import '../data/medical.dart';
import '../data/store.dart';

Future<Set<String>?> selectArchives(
  BuildContext context,
  CareStore store, {
  Set<String> selected = const {},
  bool foldersOnly = false,
  Set<String> excluded = const {},
}) => showDialog<Set<String>>(
  context: context,
  builder: (_) => _ArchivePicker(
    store: store,
    initial: selected,
    foldersOnly: foldersOnly,
    excluded: excluded,
  ),
);

class _ArchivePicker extends StatefulWidget {
  final CareStore store;
  final Set<String> initial, excluded;
  final bool foldersOnly;
  const _ArchivePicker({
    required this.store,
    required this.initial,
    required this.foldersOnly,
    required this.excluded,
  });
  @override
  State<_ArchivePicker> createState() => _ArchivePickerState();
}

class _ArchivePickerState extends State<_ArchivePicker> {
  late Set<String> selected = {...widget.initial};
  String folder = '', query = '';
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.store.data.records;
    final effective = archiveSelection(records, selected);
    final items =
        records
            .where(
              (r) =>
                  (r.kind == 'folder' ||
                      (!widget.foldersOnly && r.kind == 'document')) &&
                  !widget.excluded.contains(r.id) &&
                  (query.isEmpty
                      ? r.text('folderId') == folder
                      : medicalTitle(r)
                            .toLowerCase()
                            .contains(query.toLowerCase())),
            )
            .toList()
          ..sort(
            (a, b) => a.kind == b.kind
                ? medicalTitle(a).compareTo(medicalTitle(b))
                : a.kind == 'folder'
                ? -1
                : 1,
          );
    return Dialog(
      child: SizedBox(
        width: 620,
        height: MediaQuery.sizeOf(context).height * .78,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.foldersOnly ? '选择目标文件夹' : '关联档案',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: search,
                decoration: const InputDecoration(
                  labelText: '搜索名称',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => query = v.trim()),
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      folder = '';
                      query = '';
                      search.clear();
                    }),
                    child: const Text('全部档案'),
                  ),
                  for (final r in folderTrail(records, folder))
                    TextButton(
                      onPressed: () => setState(() {
                        folder = r.id;
                        query = '';
                        search.clear();
                      }),
                      child: Text(r.text('title')),
                    ),
                ],
              ),
              if (!widget.foldersOnly)
                const Text(
                  '勾选文件夹会关联其中全部档案及子文件夹。',
                  style: TextStyle(fontSize: 12),
                ),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('这里暂无档案'))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final r = items[index],
                              isFolder = items[index].kind == 'folder';
                          final inherited =
                              effective.contains(r.id) &&
                              !selected.contains(r.id);
                          return ListTile(
                            leading: widget.foldersOnly
                                ? const Icon(Icons.folder_outlined)
                                : Checkbox(
                                    value: effective.contains(r.id),
                                    onChanged: inherited
                                        ? null
                                        : (value) => setState(() {
                                            if (value == true) {
                                              selected.removeAll(
                                                archiveSelection(records, {
                                                  r.id,
                                                }),
                                              );
                                              selected.add(r.id);
                                            } else {
                                              selected.remove(r.id);
                                            }
                                          }),
                                  ),
                            title: Text(medicalTitle(r)),
                            subtitle: Text(
                              inherited
                                  ? '已随上级文件夹关联'
                                  : query.isEmpty
                                  ? isFolder
                                        ? '文件夹'
                                        : '文件'
                                  : archiveLocation(records, r),
                            ),
                            trailing: isFolder
                                ? const Icon(Icons.chevron_right)
                                : null,
                            onTap: () => setState(() {
                              if (isFolder) {
                                folder = r.id;
                                query = '';
                                search.clear();
                              } else if (!inherited) {
                                selected.contains(r.id)
                                    ? selected.remove(r.id)
                                    : selected.add(r.id);
                              }
                            }),
                          );
                        },
                      ),
              ),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      widget.foldersOnly ? {folder} : selected,
                    ),
                    child: Text(
                      widget.foldersOnly
                          ? '选择此文件夹'
                          : '确认关联（${selected.length}）',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
