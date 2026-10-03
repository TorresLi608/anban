import 'models.dart';

List<CareRecord> folderTrail(List<CareRecord> records, String folderId) {
  final folders = {
    for (final r in records.where((r) => r.kind == 'folder')) r.id: r,
  };
  final result = <CareRecord>[];
  final seen = <String>{};
  while (folderId.isNotEmpty && seen.add(folderId)) {
    final folder = folders[folderId];
    if (folder == null) break;
    result.insert(0, folder);
    folderId = folder.text('folderId');
  }
  return result;
}

Set<String> archiveSelection(List<CareRecord> records, Iterable<String> roots) {
  final selected = roots.toSet();
  var changed = true;
  while (changed) {
    changed = false;
    for (final r in records.where(
      (r) => ['document', 'folder'].contains(r.kind),
    )) {
      if (r.text('folderId').isNotEmpty &&
          selected.contains(r.text('folderId')) &&
          selected.add(r.id)) {
        changed = true;
      }
    }
  }
  return selected;
}

String medicalTitle(CareRecord record) => record.text('title').isNotEmpty
    ? record.text('title')
    : record.kind == 'instruction'
    ? record.text('content').split('\n').first
    : record.text('filename', '未命名档案');
String archiveLocation(List<CareRecord> records, CareRecord record) =>
    folderTrail(
      records,
      record.text('folderId'),
    ).map((r) => r.text('title')).join(' / ');
String safeFileName(String name) {
  final safe = name.replaceAll(RegExp(r'[/\\\x00-\x1f:*?"<>|]'), '_').trim();
  return safe.isEmpty || safe == '.' || safe == '..' ? '未命名' : safe;
}

String archiveExportPath(List<CareRecord> records, CareRecord record) {
  final folders = folderTrail(records, record.text('folderId'));
  return [
    ...folders.map(
      (r) =>
          '${safeFileName(r.text('title'))}_${safeFileName(r.id.substring(0, r.id.length.clamp(0, 6)))}',
    ),
    '${safeFileName(record.id)}_${safeFileName(record.text('filename', medicalTitle(record)))}',
  ].join('/');
}

String folderExportPath(
  List<CareRecord> records,
  String id,
) => folderTrail(records, id)
    .map(
      (r) =>
          '${safeFileName(r.text('title'))}_${safeFileName(r.id.substring(0, r.id.length.clamp(0, 6)))}',
    )
    .join('/');
