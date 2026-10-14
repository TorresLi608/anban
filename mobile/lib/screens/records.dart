import 'dart:math';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/planning.dart';
import '../data/store.dart';
import '../ui.dart';
import 'forms.dart';
import 'media.dart';

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
    final latest = items.isNotEmpty ? items.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          'HEALTH RECORDS',
          '健康记录',
          '每次变化都带着准确时间，为就诊复查提供真实参考。',
          action: FilledButton.icon(
            onPressed: () => editRecord(context, widget.store, kind),
            icon: const Icon(Icons.add),
            label: Text('记录${kindNames[kind]}'),
          ),
        ),

        // 1. 分类筛选胶囊栏（带图标和专属色彩指示）
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final k in healthKinds) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: Icon(
                      kindIcon(k),
                      size: 16,
                      color: kind == k ? Colors.white : kindColor(k),
                    ),
                    label: Text(kindNames[k]!),
                    selected: kind == k,
                    selectedColor: pine,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: kind == k ? Colors.white : ink,
                      fontWeight: kind == k ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: kind == k ? pine : const Color(0xFFDFE6DD),
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onSelected: (_) => setState(() => kind = k),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 2. 当前分类概况横幅
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          color: const Color(0xFFF7FAF6),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kindBadgeBg(kind),
                  shape: BoxShape.circle,
                ),
                child: Icon(kindIcon(kind), color: kindColor(kind), size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${kindNames[kind]}统计',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      latest == null
                          ? '暂无历史记录，点击右上角添加第一条'
                          : '累计 ${items.length} 笔记录 · 最新: ${_formatMetricValue(latest)}',
                      style: const TextStyle(fontSize: 11.5, color: muted),
                    ),
                  ],
                ),
              ),
              if (items.isNotEmpty)
                StatusBadge(
                  label: '${items.length} 条',
                  textColor: pine,
                  backgroundColor: const Color(0xFFE2EDE0),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 3. 疼痛趋势图（如果当前选中的是疼痛指标）
        if (kind == 'pain') ...[
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
          const SizedBox(height: 14),
        ],

        // 4. 记录历史列表（卡片化设计）
        Section(
          '历史记录流',
          child: items.isEmpty
              ? EmptyState(
                  kindIcon(kind),
                  '暂无${kindNames[kind]}记录',
                  '按时记录身体感受和指标变化，数据将安全加密保存。',
                  action: FilledButton.icon(
                    onPressed: () => editRecord(context, widget.store, kind),
                    icon: const Icon(Icons.add),
                    label: Text('立即记录${kindNames[kind]}'),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final r = items[index];
                    final photos = photosOf(r);
                    final hasAttachment = r.text('attachment').isNotEmpty;

                    return Surface(
                      padding: const EdgeInsets.all(16),
                      child: InkWell(
                        onTap: () => hasAttachment
                            ? previewMedia(context, widget.store, r)
                            : editRecord(
                                context,
                                widget.store,
                                r.kind,
                                record: r,
                              ),
                        borderRadius: BorderRadius.circular(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 类别徽章
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: kindBadgeBg(r.kind),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                kindIcon(r.kind),
                                color: kindColor(r.kind),
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 14),

                            // 主内容区
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        _formatMetricValue(r),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: ink,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${dayKey(r.at)} ${clockText(r.at)}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (r.text('note').isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAF7),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        r.text('note'),
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: ink,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (photos.isNotEmpty || hasAttachment) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        if (photos.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE8F0E7),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.image_outlined,
                                                  size: 13,
                                                  color: pine,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${photos.length} 张图片',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: pine,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (hasAttachment)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEBF3FB),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.attach_file,
                                                  size: 13,
                                                  color: Color(0xFF1E88E5),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  r.text('filename', '1 个附件'),
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF1565C0),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // 右侧快捷操作
                            RecordActions(
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
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatMetricValue(CareRecord r) => switch (r.kind) {
    'weight' => '${r.text('weight')} kg',
    'temperature' => '${r.text('temperature')} ℃',
    'heartRate' => '${r.text('heartRate')} 次/分',
    'memory' => r.text('title', '随便记一笔'),
    'stool' || 'urine' => selectedValues(r.text('status')).isNotEmpty
        ? selectedValues(r.text('status')).join('、')
        : '正常',
    'pain' => '疼痛 ${r.text('score')} / 10 分',
    _ => '${r.text('name')} · ${r.text('severity')}',
  };
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
    final selected = records
        .where((r) => !r.at.isBefore(start) && r.at.isBefore(end))
        .toList()
      ..sort((a, b) => a.at.compareTo(b.at));

    if (selected.isEmpty) {
      return const EmptyState(
        Icons.show_chart_rounded,
        '暂无该时段疼痛记录',
        '记录后的分值将在这里连线展示，帮助评估镇痛效果',
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
        '每日峰值',
        '${now.month}/${now.day}',
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              days == 1 ? '今日每次疼痛评分' : '每日最高疼痛评分（缺测不连线）',
              style: const TextStyle(
                color: ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'VAS 0~10分',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFFC62828),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
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
                (s) => Text(
                  s,
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
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
    final linePaint = Paint()
      ..color = const Color(0xFFE8ECE7)
      ..strokeWidth = 1;

    for (final n in [0, 5, 10]) {
      final y = 10 + (size.height - 20) * (1 - n / 10);
      canvas.drawLine(Offset(25, y), Offset(size.width, y), linePaint);
      final label = TextPainter(
        text: TextSpan(
          text: '$n',
          style: const TextStyle(color: muted, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(4, y - 6));
    }

    Offset position(Offset p) => Offset(
      30 + p.dx * (size.width - 40),
      10 + (size.height - 20) * (1 - p.dy / 10),
    );

    final curvePaint = Paint()
      ..color = const Color(0xFFD32F2F)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = const Color(0xFFD32F2F)
      ..style = PaintingStyle.fill;

    final dotBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var i = 0; i < points.length; i++) {
      if (i > 0 &&
          (days == 1 ||
              points[i].dx - points[i - 1].dx <= 1 / (days - 1) + .0001)) {
        canvas.drawLine(position(points[i - 1]), position(points[i]), curvePaint);
      }
      final pos = position(points[i]);
      canvas.drawCircle(pos, 5, dotPaint);
      canvas.drawCircle(pos, 5, dotBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PainPainter old) => true;
}
