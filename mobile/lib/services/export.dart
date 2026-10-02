import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/models.dart';

Future<Uint8List> medicalPdf(CareData data, {int days = 30}) async {
  final font = pw.Font.ttf(await rootBundle.load('assets/NotoSansSC.ttf'));
  final now = DateTime.now(),
      start = DateTime.now().subtract(Duration(days: days));
  final pdf = pw.Document();
  final rows =
      data.records
          .where(
            (r) =>
                ['pain', 'symptom', 'vital', 'dose'].contains(r.kind) &&
                !r.at.isBefore(start) &&
                !r.at.isAfter(now),
          )
          .toList()
        ..sort((a, b) => a.at.compareTo(b.at));
  const labels = {'pain': '疼痛', 'symptom': '症状', 'vital': '体征', 'dose': '服药'};
  String detail(CareRecord r) => switch (r.kind) {
    'pain' =>
      '${r.text('score')} 分；${r.text('location')}；${r.text('type')}；${r.text('trigger')}；${r.text('relief')}；${r.text('note')}',
    'symptom' =>
      '${r.text('name')}（${r.text('severity')}）；${r.text('duration')}；${r.text('impact')}；${r.text('note')}',
    'vital' =>
      '体温 ${r.text('temperature', '—')}℃；体重 ${r.text('weight', '—')}kg；进食 ${r.text('food')}；睡眠 ${r.text('sleep', '—')} 小时；排便 ${r.text('bowel')}；${r.text('note')}',
    _ =>
      '${r.text('name')}；${r.text('dose')}；计划 ${r.text('scheduled', '按需')}；效果 ${r.text('effect')}；${r.text('note')}',
  };
  pdf.addPage(
    pw.MultiPage(
      maxPages: 500,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: pw.ThemeData.withFont(base: font, bold: font),
      header: (_) => pw.Text(
        '安伴 · 居家照护记录',
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
      ),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${c.pageNumber} / ${c.pagesCount}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      build: (_) => [
        pw.SizedBox(height: 18),
        pw.Text('复诊参考记录', style: const pw.TextStyle(fontSize: 24)),
        pw.SizedBox(height: 12),
        pw.Text('患者：${data.profile['name'] ?? '未填写'}    导出日期：${dayKey(now)}'),
        pw.Text('范围：最近 $days 天 · 数据由患者或陪护者记录，未经医疗核验。'),
        pw.SizedBox(height: 16),
        pw.Text(disclaimer, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 18),
        if (rows.isEmpty)
          pw.Text('所选时间内暂无记录。')
        else
          pw.TableHelper.fromTextArray(
            headers: ['时间', '类型', '记录内容'],
            data: [
              for (final r in rows)
                [
                  '${dayKey(r.at)}\n${clockText(r.at)}',
                  labels[r.kind]!,
                  detail(r),
                ],
            ],
            columnWidths: {
              0: const pw.FixedColumnWidth(70),
              1: const pw.FixedColumnWidth(34),
            },
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellPadding: const pw.EdgeInsets.all(7),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
          ),
      ],
    ),
  );
  return pdf.save();
}
