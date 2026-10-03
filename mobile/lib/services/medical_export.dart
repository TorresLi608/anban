import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/models.dart';
import '../data/medical.dart';
import '../data/vault.dart';

String medicalDate(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  return date == null ? value : '${dayKey(date)} ${clockText(date)}';
}

Map<String, String> medicalFields(CareRecord r) => switch (r.kind) {
  'visit' => {
    '类型': r.text('visitType'),
    '医院': r.text('hospital'),
    '科室': r.text('department'),
    '医生': r.text('doctor'),
    '就诊/入院原因': r.text('reason'),
    '诊疗结果/住院经过': r.text('findings'),
    '后续安排': r.text('plan'),
    '出院时间': medicalDate(r.text('dischargeAt')),
    '备注': r.text('note'),
  },
  'instruction' => {'医嘱内容': r.text('content'), '医生/来源': r.text('doctor')},
  _ => {
    '文件名': r.text('filename'),
    '分类': r.text('category'),
    '备注': r.text('note'),
  },
};

Future<Uint8List> medicalRecordsPdf(
  CareData data,
  Iterable<CareRecord> records, {
  String title = '医疗资料',
}) async {
  final font = pw.Font.ttf(await rootBundle.load('assets/NotoSansSC.ttf'));
  final selected = records.toList()..sort((a, b) => b.at.compareTo(a.at));
  final content = <pw.Widget>[
    pw.Text(
      title,
      style: pw.TextStyle(fontSize: 23, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 12),
    pw.Text(
      '患者：${data.profile['name'] ?? '未填写'}    导出日期：${dayKey(DateTime.now())}',
    ),
    pw.Text(
      '内容由用户记录；关联资料原件可另行导出为压缩包。',
      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
    ),
  ];
  void text(String value) {
    content.add(
      pw.Text(
        value,
        overflow: pw.TextOverflow.span,
        style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
      ),
    );
    content.add(pw.SizedBox(height: 6));
  }

  for (final r in selected) {
    content.add(pw.SizedBox(height: 18));
    text(
      '${r.kind == 'visit'
          ? '看诊'
          : r.kind == 'instruction'
          ? '医嘱'
          : r.kind == 'folder'
          ? '文件夹'
          : '档案'}：${medicalTitle(r)}',
    );
    text('记录时间：${dayKey(r.at)} ${clockText(r.at)}');
    if (['document', 'folder'].contains(r.kind)) {
      text(
        '位置：${archiveLocation(data.records, r).isEmpty ? '全部档案' : archiveLocation(data.records, r)}',
      );
    }
    for (final entry in medicalFields(r).entries) {
      if (entry.value.isNotEmpty) text('${entry.key}：${entry.value}');
    }
    if (r.kind == 'visit') {
      final ids = archiveSelection(
        data.records,
        selectedValues(r.text('archiveIds')),
      );
      final docs = data.records.where(
        (d) => d.kind == 'document' && ids.contains(d.id),
      );
      for (final doc in docs) {
        text('关联档案：${archiveExportPath(data.records, doc)}');
      }
      for (final note in data.records.where(
        (d) => d.kind == 'instruction' && d.text('visitId') == r.id,
      )) {
        text('关联医嘱（${dayKey(note.at)}）：${note.text('content')}');
      }
    }
  }
  if (selected.isEmpty) text('暂无记录。');
  final pdf = pw.Document();
  pdf.addPage(
    pw.MultiPage(
      maxPages: 10000,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: pw.ThemeData.withFont(base: font, bold: font),
      header: (_) => pw.Text(
        '安伴 · 医疗资料',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${c.pageNumber} / ${c.pagesCount}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      build: (_) => content,
    ),
  );
  return pdf.save();
}

/// Independent ZIP volumes keep total file count unbounded without loading the
/// entire archive into memory. A file over 64 MB receives a volume of its own.
Stream<({String name, Uint8List bytes})> medicalArchiveExports(
  CareData data,
  LocalVault vault, {
  required Set<String> selectedIds,
  String title = '医疗档案',
  List<CareRecord>? summary,
}) async* {
  final ids = archiveSelection(data.records, selectedIds);
  final selected = data.records.where((r) => ids.contains(r.id)).toList();
  final pdf = await medicalRecordsPdf(data, summary ?? selected, title: title);
  Archive create() => Archive()
    ..addFile(ArchiveFile.bytes('资料索引.pdf', pdf))
    ..addFile(
      ArchiveFile.string(
        '档案目录.json',
        jsonEncode({'records': selected.map((r) => r.toJson()).toList()}),
      ),
    )
    ..addFile(
      ArchiveFile.string(
        '说明.txt',
        '本压缩包为未加密导出，请妥善保管。多个分卷各自独立，可分别解压到同一目录。文件名前的标识用于避免同名文件互相覆盖。',
      ),
    );
  var archive = create(), total = 0, count = 0, part = 1;
  for (final r in selected.where((r) => r.kind == 'folder')) {
    archive.addFile(
      ArchiveFile.directory('${folderExportPath(data.records, r.id)}/'),
    );
  }
  for (final r in selected.where(
    (r) => r.kind == 'document' && r.text('attachment').isNotEmpty,
  )) {
    final size = await vault.attachmentSize(r.text('attachment'));
    if (count > 0 && total + size > 64 * 1024 * 1024) {
      yield (
        name: '${safeFileName(title)}-${part++}.zip',
        bytes: ZipEncoder().encodeBytes(archive),
      );
      archive = create();
      total = 0;
      count = 0;
    }
    final bytes = await vault.attachment(r.text('attachment'));
    archive.addFile(
      ArchiveFile.noCompress(
        archiveExportPath(data.records, r),
        bytes.length,
        bytes,
      ),
    );
    total += bytes.length;
    count++;
  }
  yield (
    name: '${safeFileName(title)}-$part.zip',
    bytes: ZipEncoder().encodeBytes(archive),
  );
}
