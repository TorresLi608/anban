import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/attachments.dart';
import '../data/medical.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/medical_export.dart';
import '../ui.dart';
import 'archive_picker.dart';
import 'forms.dart';
import 'media.dart';

String fileSizeText(CareRecord r) {
  final size = int.tryParse(r.text('size'));
  return size == null
      ? '原始文件'
      : size >= 1024 * 1024
      ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(size / 1024).toStringAsFixed(1)} KB';
}

Future<void> exportMedical(
  BuildContext context,
  CareStore store,
  List<CareRecord> records, {
  bool withFiles = false,
  Set<String>? archiveIds,
  String title = '医疗资料',
}) async {
  if (!await confirm(
    context,
    '导出未加密资料？',
    withFiles
        ? '将导出记录索引和原始文件，保留文件夹层级。资料较多时会分成多个独立 ZIP；请妥善保管导出的文件。'
        : '将导出可阅读的 PDF，请妥善保管。',
    action: '导出',
  )) {
    return;
  }
  final data = store.data, vault = store.vault;
  if (!withFiles) {
    final bytes = await medicalRecordsPdf(data, records, title: title);
    if (!context.mounted || !identical(vault, store.vault)) return;
    final saved = await FilePicker.saveFile(
      fileName: '${safeFileName(title)}.pdf',
      bytes: bytes,
      mimeType: 'application/pdf',
    );
    if (context.mounted) toast(context, saved == null ? '已关闭保存窗口' : 'PDF 已导出');
    return;
  }
  final ids =
      archiveIds ??
      {
        for (final r in records)
          if (['folder', 'document'].contains(r.kind))
            r.id
          else if (r.kind == 'visit')
            ...selectedValues(r.text('archiveIds')),
      };
  var count = 0;
  await for (final part in medicalArchiveExports(
    data,
    vault,
    selectedIds: ids,
    title: title,
    summary: records,
  )) {
    if (!context.mounted || !identical(vault, store.vault)) return;
    final saved = await FilePicker.saveFile(
      fileName: part.name,
      bytes: part.bytes,
      mimeType: 'application/zip',
    );
    if (saved == null) {
      if (context.mounted) toast(context, '导出已停止，已保存 $count 个压缩包');
      return;
    }
    count++;
  }
  if (context.mounted) toast(context, '已导出 $count 个独立压缩包');
}

class MedicalPage extends StatefulWidget {
  final CareStore store;
  const MedicalPage({super.key, required this.store});
  @override
  State<MedicalPage> createState() => _MedicalPageState();
}

class _MedicalPageState extends State<MedicalPage> {
  int tab = 0, visible = 40;
  String folderId = '', progress = '';
  final search = TextEditingController();
  bool busy = false, cancelUpload = false;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    await attempt(context, action);
    if (mounted) {
      setState(() {
        busy = false;
        progress = '';
      });
    }
  }

  void openFolder(String id) => setState(() {
    folderId = id;
    visible = 40;
    search.clear();
  });

  Future<void> upload() async {
    cancelUpload = false;
    final picked = await FilePicker.pickFiles(type: FileType.any);
    if (picked.isEmpty) return;
    final vault = widget.store.vault;
    var completed = 0;
    for (final file in picked) {
      if (cancelUpload || !mounted) break;
      String? attachment;
      try {
        setState(
          () =>
              progress = '正在保存 ${completed + 1}/${picked.length}：${file.name}',
        );
        final size = await file.length();
        if (size != null && size > maxAttachmentBytes) {
          throw const FormatException('单个文件最多 200 MB');
        }
        attachment = await vault.addAttachmentStream(file.readAsByteStream());
        if (!identical(vault, widget.store.vault)) {
          throw StateError('账号已切换，请重新上传');
        }
        await widget.store.put(
          CareRecord(
            kind: 'document',
            fields: {
              'title': file.name,
              'filename': file.name,
              'extension': file.extension?.toLowerCase() ?? '',
              'category': classify(file.name),
              'folderId': folderId,
              'attachment': attachment,
              'size': '${await vault.attachmentSize(attachment)}',
            },
          ),
        );
        completed++;
      } catch (error) {
        if (attachment != null) {
          try {
            await vault.releaseLocalAttachment(attachment);
          } catch (_) {
            /* Account may already be closed. */
          }
        }
        throw StateError(
          '已保存 $completed/${picked.length} 个文件；${file.name} 未保存：$error',
        );
      }
    }
    if (mounted) {
      toast(
        context,
        '已保存 $completed/${picked.length} 个文件${cancelUpload ? '，其余已取消' : ''}',
      );
    }
  }

  Future<void> action(CareRecord r, String value) async {
    if (value == 'edit') {
      await editRecord(context, widget.store, r.kind, record: r);
      return;
    }
    if (value == 'move') {
      final picked = await selectArchives(
        context,
        widget.store,
        foldersOnly: true,
        excluded: r.kind == 'folder'
            ? archiveSelection(widget.store.data.records, {r.id})
            : {},
      );
      if (picked != null) {
        await widget.store.put(
          r.copy(fields: {...r.fields, 'folderId': picked.single}),
        );
      }
      return;
    }
    if (value == 'delete') {
      if (!await confirm(
        context,
        '删除${r.kind == 'folder' ? '文件夹' : '这条记录'}？',
        '关联会一并解除，其他看诊和医嘱记录会保留。非空文件夹需先移出其中内容。',
        action: '删除',
      )) {
        return;
      }
      await widget.store.remove(r);
      return;
    }
    if (value == 'pin') {
      await widget.store.put(
        r.copy(
          fields: {...r.fields, 'pinned': '${r.text('pinned') != 'true'}'},
        ),
      );
      return;
    }
    if (value == 'export' && mounted) {
      if (r.kind == 'document' && r.text('attachment').isNotEmpty) {
        if (!await confirm(
          context,
          '导出原文件？',
          '导出的是未加密副本，请妥善保管。',
          action: '导出',
        )) {
          return;
        }
        await FilePicker.saveFile(
          fileName: safeFileName(r.text('filename', medicalTitle(r))),
          bytes: await widget.store.vault.attachment(r.text('attachment')),
        );
      } else {
        await exportMedical(
          context,
          widget.store,
          [r],
          withFiles: r.kind == 'folder',
          archiveIds: {r.id},
          title: medicalTitle(r),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final all = widget.store.data.records;
      final query = search.text.trim().toLowerCase();
      final scope = folderId.isEmpty ? null : archiveSelection(all, {folderId});
      final items =
          all.where((r) {
            if (tab == 0) {
              if (!['folder', 'document'].contains(r.kind)) return false;
              if (query.isEmpty && r.text('folderId') != folderId) return false;
              if (query.isNotEmpty && scope != null && !scope.contains(r.id)) {
                return false;
              }
            } else if (r.kind != (tab == 1 ? 'visit' : 'instruction')) {
              return false;
            }
            return query.isEmpty ||
                r.fields.values.any((v) => v.toLowerCase().contains(query));
          }).toList()..sort((a, b) {
            if (tab == 0 && a.kind != b.kind) {
              return a.kind == 'folder' ? -1 : 1;
            }
            if (tab == 2 && a.text('pinned') != b.text('pinned')) {
              return a.text('pinned') == 'true' ? -1 : 1;
            }
            return b.at.compareTo(a.at);
          });
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading('MEDICAL SPACE', '医疗资料', '档案、看诊和医嘱，保存在同一处。'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('档案')),
              ButtonSegment(value: 1, label: Text('看诊')),
              ButtonSegment(value: 2, label: Text('医嘱')),
            ],
            selected: {tab},
            onSelectionChanged: busy
                ? null
                : (s) => setState(() {
                    tab = s.first;
                    visible = 40;
                    search.clear();
                  }),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: search,
            decoration: InputDecoration(
              labelText: tab == 0 ? '搜索当前文件夹及子文件夹' : '搜索记录',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(search.clear),
                      icon: const Icon(Icons.clear),
                      tooltip: '清除搜索',
                    ),
            ),
            onChanged: (_) => setState(() => visible = 40),
          ),
          const SizedBox(height: 16),
          if (tab == 0)
            Wrap(
              children: [
                TextButton(
                  onPressed: busy ? null : () => openFolder(''),
                  child: const Text('全部档案'),
                ),
                for (final folder in folderTrail(all, folderId))
                  TextButton(
                    onPressed: busy ? null : () => openFolder(folder.id),
                    child: Text('› ${folder.text('title')}'),
                  ),
              ],
            ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => run(
                        tab == 0
                            ? upload
                            : () => editRecord(
                                context,
                                widget.store,
                                tab == 1 ? 'visit' : 'instruction',
                              ),
                      ),
                icon: Icon(tab == 0 ? Icons.upload_file : Icons.add),
                label: Text(
                  tab == 0
                      ? '上传文件'
                      : tab == 1
                      ? '新增看诊'
                      : '记医嘱',
                ),
              ),
              if (tab == 0)
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => run(
                          () => editRecord(
                            context,
                            widget.store,
                            'folder',
                            initial: {'folderId': folderId},
                          ),
                        ),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('新建文件夹'),
                ),
              OutlinedButton.icon(
                onPressed: busy || items.isEmpty
                    ? null
                    : () => run(
                        () => exportMedical(
                          context,
                          widget.store,
                          items,
                          withFiles: tab == 0,
                          archiveIds: tab == 0
                              ? items.map((r) => r.id).toSet()
                              : null,
                          title: tab == 0
                              ? '医疗档案'
                              : tab == 1
                              ? '看诊记录'
                              : '医嘱记录',
                        ),
                      ),
                icon: const Icon(Icons.ios_share),
                label: Text(tab == 0 ? '导出档案' : '导出 PDF'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            tab == 0
                ? '不限文件数量 · 单文件最多 200 MB · 支持图片、PDF、视频及其他文件'
                : '共 ${items.length} 条记录',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          if (busy && progress.isNotEmpty) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            if (progress.isNotEmpty) Text(progress),
            if (progress.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => cancelUpload = true),
                child: const Text('完成当前文件后停止'),
              ),
          ],
          const SizedBox(height: 14),
          if (items.isEmpty)
            EmptyState(
              tab == 0 ? Icons.folder_outlined : Icons.note_alt_outlined,
              query.isEmpty
                  ? '还没有${tab == 0
                        ? '档案'
                        : tab == 1
                        ? '看诊记录'
                        : '医嘱'}'
                  : '没有匹配的记录',
              tab == 0 ? '可先新建文件夹，再批量上传资料。' : '点上方按钮开始记录。',
            )
          else
            for (final r in items.take(visible))
              ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                leading: Icon(
                  r.kind == 'folder'
                      ? Icons.folder_outlined
                      : r.kind == 'visit'
                      ? Icons.local_hospital_outlined
                      : r.kind == 'instruction'
                      ? r.text('pinned') == 'true'
                            ? Icons.push_pin
                            : Icons.note_alt_outlined
                      : Icons.insert_drive_file_outlined,
                  color: pine,
                ),
                title: Text(
                  medicalTitle(r),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  r.kind == 'folder'
                      ? '${all.where((c) => c.text('folderId') == r.id).length} 项'
                      : r.kind == 'document'
                      ? '${r.text('category', '档案')} · ${fileSizeText(r)}\n${dayKey(r.at)}'
                      : r.kind == 'visit'
                      ? '${r.text('visitType')} · ${dayKey(r.at)}\n${r.text('hospital')} ${r.text('department')}'
                      : '${dayKey(r.at)} ${clockText(r.at)}\n${r.text('content')}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: busy
                    ? null
                    : () => r.kind == 'folder'
                          ? openFolder(r.id)
                          : r.kind == 'document'
                          ? run(() => previewMedia(context, widget.store, r))
                          : Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => MedicalDetailPage(
                                  store: widget.store,
                                  id: r.id,
                                ),
                              ),
                            ),
                trailing: PopupMenuButton<String>(
                  enabled: !busy,
                  tooltip: '记录操作',
                  onSelected: (value) => run(() => action(r, value)),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    if (['folder', 'document'].contains(r.kind))
                      const PopupMenuItem(value: 'move', child: Text('移动到文件夹')),
                    if (r.kind == 'instruction')
                      PopupMenuItem(
                        value: 'pin',
                        child: Text(r.text('pinned') == 'true' ? '取消置顶' : '置顶'),
                      ),
                    const PopupMenuItem(value: 'export', child: Text('导出')),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ),
          if (items.length > visible)
            TextButton(
              onPressed: () => setState(() => visible += 40),
              child: Text('加载更多（已显示 $visible/${items.length}）'),
            ),
        ],
      );
    },
  );
}

class MedicalDetailPage extends StatefulWidget {
  final CareStore store;
  final String id;
  const MedicalDetailPage({super.key, required this.store, required this.id});
  @override
  State<MedicalDetailPage> createState() => _MedicalDetailPageState();
}

class _MedicalDetailPageState extends State<MedicalDetailPage> {
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    await attempt(context, action);
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final all = widget.store.data.records,
          matches = widget.store.data.records
              .where((r) => r.id == widget.id)
              .toList();
      if (matches.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: const Text('医疗记录')),
          body: const Center(child: Text('记录已删除')),
        );
      }
      final r = matches.first,
          linked = archiveSelection(all, selectedValues(r.text('archiveIds')));
      final docs = all
          .where((d) => d.kind == 'document' && linked.contains(d.id))
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: Text(medicalTitle(r)),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () => editRecord(context, widget.store, r.kind, record: r),
              child: const Text('编辑'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '${dayKey(r.at)} ${clockText(r.at)}',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 18),
            if (busy) const LinearProgressIndicator(),
            for (final field in medicalFields(r).entries)
              if (field.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        field.key,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      SelectableText(field.value),
                    ],
                  ),
                ),
            if (r.kind == 'instruction' && r.text('visitId').isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => MedicalDetailPage(
                      store: widget.store,
                      id: r.text('visitId'),
                    ),
                  ),
                ),
                icon: const Icon(Icons.link),
                label: const Text('查看关联看诊'),
              ),
            if (r.kind == 'visit') ...[
              Section(
                '关联档案（${docs.length}）',
                trailing: TextButton(
                  onPressed: () =>
                      editRecord(context, widget.store, 'visit', record: r),
                  child: const Text('管理关联'),
                ),
                child: Column(
                  children: [
                    for (final doc in docs.take(20))
                      ListTile(
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(medicalTitle(doc)),
                        subtitle: Text(archiveLocation(all, doc)),
                        onTap: busy
                            ? null
                            : () => run(
                                () => previewMedia(context, widget.store, doc),
                              ),
                      ),
                    if (docs.length > 20)
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('关联档案')),
                              body: ListView.builder(
                                itemCount: docs.length,
                                itemBuilder: (c, i) => ListTile(
                                  title: Text(medicalTitle(docs[i])),
                                  subtitle: Text(archiveLocation(all, docs[i])),
                                  onTap: () =>
                                      previewMedia(c, widget.store, docs[i]),
                                ),
                              ),
                            ),
                          ),
                        ),
                        child: const Text('查看全部关联档案'),
                      ),
                  ],
                ),
              ),
              Section(
                '本次看诊医嘱',
                trailing: TextButton(
                  onPressed: () => editRecord(
                    context,
                    widget.store,
                    'instruction',
                    initial: {'visitId': r.id},
                  ),
                  child: const Text('记医嘱'),
                ),
                child: Column(
                  children: [
                    for (final note in all.where(
                      (n) =>
                          n.kind == 'instruction' && n.text('visitId') == r.id,
                    ))
                      ListTile(
                        title: Text(medicalTitle(note)),
                        subtitle: Text(
                          note.text('content'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => MedicalDetailPage(
                              store: widget.store,
                              id: note.id,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => run(
                          () => exportMedical(context, widget.store, [
                            r,
                          ], title: medicalTitle(r)),
                        ),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('导出 PDF'),
                ),
                if (r.kind == 'visit')
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => run(
                            () => exportMedical(
                              context,
                              widget.store,
                              [r],
                              withFiles: true,
                              title: medicalTitle(r),
                            ),
                          ),
                    icon: const Icon(Icons.folder_zip_outlined),
                    label: const Text('导出记录和关联原件'),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
