import 'dart:math';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/planning.dart';
import '../data/store.dart';
import '../ui.dart';
import 'forms.dart';

class RecordsPage extends StatefulWidget {
  final CareStore store;
  const RecordsPage({super.key, required this.store});
  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  String kind = 'weight';
  int period = 7;
  @override
  Widget build(BuildContext context) {
    final items = widget.store.records(kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading('HEALTH RECORDS', '健康记录', '每次变化，都带着准确的记录时间。'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in healthKinds)
              ChoiceChip(
                label: Text(kindNames[k]!),
                selected: kind == k,
                onSelected: (_) => setState(() => kind = k),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (kind == 'pain')
          Section(
            '疼痛趋势',
            trailing: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('今日')),
                ButtonSegment(value: 7, label: Text('7天')),
                ButtonSegment(value: 30, label: Text('30天')),
              ],
              selected: {period},
              onSelectionChanged: (s) => setState(() => period = s.first),
            ),
            child: Surface(
              child: PainChart(records: items, days: period),
            ),
          ),
        Section(
          '${kindNames[kind]}记录',
          trailing: FilledButton.icon(
            onPressed: () => editRecord(context, widget.store, kind),
            icon: const Icon(Icons.add),
            label: const Text('添加记录'),
          ),
          child: items.isEmpty
              ? const EmptyState(Icons.edit_note_outlined, '暂无记录', '保存后自动上传云端')
              : Column(
                  children: [
                    for (final r in items)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        title: Text(switch (r.kind) {
                          'weight' => '${r.text('weight')} kg',
                          'stool' ||
                          'urine' => selectedValues(r.text('status')).join('、'),
                          'pain' => '疼痛 ${r.text('score')} / 10',
                          _ => '${r.text('name')} · ${r.text('severity')}',
                        }),
                        subtitle: Text(
                          '${dayKey(r.at)} ${clockText(r.at)}\n${r.text('note')}${photosOf(r).isEmpty ? '' : '\n${photosOf(r).length} 张图片'}',
                        ),
                        onTap: () => editRecord(
                          context,
                          widget.store,
                          r.kind,
                          record: r,
                        ),
                        trailing: RecordActions(
                          edit: () => editRecord(
                            context,
                            widget.store,
                            r.kind,
                            record: r,
                          ),
                          delete: () => attempt(
                            context,
                            () => deleteRecord(context, widget.store, r),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class PainChart extends StatelessWidget {
  final List<CareRecord> records;
  final int days;
  const PainChart({super.key, required this.records, required this.days});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - (days - 1));
    final end = DateTime(now.year, now.month, now.day + 1);
    final selected =
        records
            .where((r) => !r.at.isBefore(start) && r.at.isBefore(end))
            .toList()
          ..sort((a, b) => a.at.compareTo(b.at));
    if (selected.isEmpty) {
      return const EmptyState(
        Icons.show_chart_rounded,
        '从第一笔记录开始',
        '有记录的日期才显示分值，不用 0 代替空缺',
      );
    }
    final points = <Offset>[];
    final labels = <String>[];
    if (days == 1) {
      for (final r in selected) {
        points.add(
          Offset(
            r.at.difference(start).inMinutes / (24 * 60),
            r.number('score'),
          ),
        );
      }
      labels.addAll(['00:00', '12:00', '24:00']);
    } else {
      for (var d = 0; d < days; d++) {
        final key = dayKey(DateTime(start.year, start.month, start.day + d));
        final values = selected
            .where((r) => dayKey(r.at) == key)
            .map((r) => r.number('score'))
            .toList();
        if (values.isNotEmpty) {
          points.add(Offset(d / (days - 1), values.reduce(max)));
        }
      }
      labels.addAll([
        '${start.month}/${start.day}',
        '每日最高分',
        '${now.month}/${now.day}',
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          days == 1 ? '今日每次疼痛评分' : '每日最高疼痛评分 · 缺测日期不连线',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 18),
        Semantics(
          label: selected
              .map(
                (r) =>
                    '${dayKey(r.at)} ${clockText(r.at)} 疼痛 ${r.text('score')} 分',
              )
              .join('；'),
          child: SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(painter: _PainPainter(points, days)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: labels
              .map(
                (s) =>
                    Text(s, style: const TextStyle(fontSize: 11, color: muted)),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _PainPainter extends CustomPainter {
  final List<Offset> points;
  final int days;
  _PainPainter(this.points, this.days);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (final n in [0, 5, 10]) {
      final y = 10 + (size.height - 20) * (1 - n / 10);
      canvas.drawLine(Offset(25, y), Offset(size.width, y), paint);
      final label = TextPainter(
        text: TextSpan(
          text: '$n',
          style: const TextStyle(color: muted, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(0, y - 6));
    }
    Offset position(Offset p) => Offset(
      30 + p.dx * (size.width - 40),
      10 + (size.height - 20) * (1 - p.dy / 10),
    );
    paint
      ..color = pine
      ..strokeWidth = 2.5;
    for (var i = 0; i < points.length; i++) {
      if (i > 0 &&
          (days == 1 ||
              points[i].dx - points[i - 1].dx <= 1 / (days - 1) + .0001)) {
        canvas.drawLine(position(points[i - 1]), position(points[i]), paint);
      }
      canvas.drawCircle(position(points[i]), 4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PainPainter old) => true;
}
