import 'dart:math';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/planning.dart';
import '../data/store.dart';
import '../data/tumor_marker.dart';
import '../ui.dart';
import 'forms.dart';
import 'media.dart';
import 'tumor_marker_chart.dart';

class RecordsPage extends StatefulWidget {
  final CareStore store;
  const RecordsPage({super.key, required this.store});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  String kind = 'weight';
  int period = 7;
  final Set<String> _expandedTumorCards = {};

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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

        // 3.1 肿瘤标志物走势图
        if (kind == 'tumorMarker' && items.isNotEmpty) ...[
          Section(
            '指标走势分析',
            child: Surface(
              child: TumorMarkerChart(records: items),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 3.2 血氧饱和度走势图
        if (kind == 'bloodOxygen' && items.isNotEmpty) ...[
          Section(
            '血氧饱和度走势',
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
              child: BloodOxygenChart(records: items, days: period),
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
                                  Text(
                                    _formatMetricValue(r),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: ink,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.access_time_rounded,
                                        size: 12,
                                        color: muted,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${dayKey(r.at)} ${clockText(r.at)}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (r.kind == 'tumorMarker') ...[
                                    if (r.text('hospital').isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.local_hospital_outlined,
                                            size: 12,
                                            color: muted,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            r.text('hospital'),
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: muted,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    Builder(
                                      builder: (_) {
                                        final markers = parseTumorMarkers(
                                          r.text('markers'),
                                        );
                                        final highItems = markers
                                            .where((m) => m.status == 'high')
                                            .toList();
                                        final lowItems = markers
                                            .where((m) => m.status == 'low')
                                            .toList();
                                        final filledItems = markers
                                            .where((m) => m.value.isNotEmpty)
                                            .toList();
                                        final isExpanded = _expandedTumorCards
                                            .contains(r.id);

                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (highItems.isNotEmpty ||
                                                lowItems.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: [
                                                  for (final m in highItems)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 7,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xFFFFEBEE,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              5,
                                                            ),
                                                        border: Border.all(
                                                          color: const Color(
                                                            0xFFFFCDD2,
                                                          ),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        '${m.abbr} ${m.value} ${m.unit} ↑',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Color(
                                                            0xFFC62828,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  for (final m in lowItems)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 7,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xFFFFF3E0,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              5,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        '${m.abbr} ${m.value} ${m.unit} ↓',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Color(
                                                            0xFFEF6C00,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                            if (filledItems.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              InkWell(
                                                onTap: () => setState(() {
                                                  if (isExpanded) {
                                                    _expandedTumorCards.remove(
                                                      r.id,
                                                    );
                                                  } else {
                                                    _expandedTumorCards.add(
                                                      r.id,
                                                    );
                                                  }
                                                }),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 2,
                                                      ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        isExpanded
                                                            ? '收起12项明细'
                                                            : '查看12项检验单明细 (${filledItems.length}项已录入)',
                                                        style: const TextStyle(
                                                          fontSize: 11.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Color(
                                                            0xFF00796B,
                                                          ),
                                                        ),
                                                      ),
                                                      Icon(
                                                        isExpanded
                                                            ? Icons
                                                                .keyboard_arrow_up
                                                            : Icons
                                                                .keyboard_arrow_down,
                                                        size: 16,
                                                        color: const Color(
                                                          0xFF00796B,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              if (isExpanded) ...[
                                                const SizedBox(height: 8),
                                                _buildTumorDetailTable(markers),
                                              ],
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                  if (r.kind == 'bloodOxygen') ...[
                                    Builder(
                                      builder: (_) {
                                        final val =
                                            double.tryParse(r.text('bloodOxygen')) ??
                                            100;
                                        final (label, textColor, bg, border) =
                                            val <= 93
                                                ? (
                                                  '预警 ≤93%',
                                                  const Color(0xFFC62828),
                                                  const Color(0xFFFFEBEE),
                                                  const Color(0xFFFFCDD2),
                                                )
                                                : val < 95
                                                ? (
                                                  '偏低 <95%',
                                                  const Color(0xFFE65100),
                                                  const Color(0xFFFFF3E0),
                                                  const Color(0xFFFFE0B2),
                                                )
                                                : (
                                                  '正常',
                                                  const Color(0xFF2E7D32),
                                                  const Color(0xFFE8F5E9),
                                                  const Color(0xFFC8E6C9),
                                                );
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: bg,
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                  border: Border.all(
                                                    color: border,
                                                    width: 0.6,
                                                  ),
                                                ),
                                                child: Text(
                                                  label,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    color: textColor,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                val >= 95
                                                    ? '血氧充足'
                                                    : val <= 93
                                                    ? '建议尽快就诊或遵医嘱吸氧'
                                                    : '建议安静休息后复测',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color:
                                                      val < 95
                                                          ? textColor
                                                          : muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
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
                                                ConstrainedBox(
                                                  constraints: const BoxConstraints(maxWidth: 160),
                                                  child: Text(
                                                    r.text('filename', '1 个附件'),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Color(0xFF1565C0),
                                                      fontWeight: FontWeight.w600,
                                                    ),
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
    'bloodOxygen' => '${r.text('bloodOxygen')} %',
    'memory' => r.text('title', '随便记一笔'),
    'stool' || 'urine' => selectedValues(r.text('status')).isNotEmpty
        ? selectedValues(r.text('status')).join('、')
        : '正常',
    'pain' => '疼痛 ${r.text('score')} / 10 分',
    'tumorMarker' => r.text('summary').isNotEmpty
        ? r.text('summary')
        : '肿瘤标志物12项检测',
    _ => '${r.text('name')} · ${r.text('severity')}',
  };

  Widget _buildTumorDetailTable(List<TumorMarkerItem> markers) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2EBE2)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFFEEF5EE),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    '项目',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: ink,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    '测定值',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: ink,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    '参考区间',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: ink,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '状态',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < markers.length; i++) ...[
            Builder(
              builder: (_) {
                final m = markers[i];
                final isHigh = m.status == 'high';
                final isLow = m.status == 'low';
                final isNormal = m.status == 'normal';
                final isFilled = m.value.isNotEmpty;

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isHigh
                        ? const Color(0xFFFFF5F5)
                        : (i.isEven ? Colors.white : const Color(0xFFF9FBFA)),
                    border: const Border(
                      top: BorderSide(color: Color(0xFFEAEFEA), width: 0.8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              m.abbr,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: isHigh ? const Color(0xFFC62828) : ink,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                m.name,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: muted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          isFilled ? '${m.value} ${m.unit}' : '—',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isHigh
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isHigh
                                ? const Color(0xFFC62828)
                                : (isFilled ? ink : muted),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '${m.ref} ${m.unit}',
                          style: const TextStyle(fontSize: 10, color: muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Center(
                          child: isHigh
                              ? const Text(
                                  '偏高↑',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFC62828),
                                  ),
                                )
                              : isLow
                              ? const Text(
                                  '偏低↓',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFEF6C00),
                                  ),
                                )
                              : isNormal
                              ? const Text(
                                  '正常',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF2E7D32),
                                  ),
                                )
                              : const Text(
                                  '未测',
                                  style: TextStyle(fontSize: 10, color: muted),
                                ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
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
            Expanded(
              child: Text(
                days == 1 ? '今日每次疼痛评分' : '每日最高疼痛评分（缺测不连线）',
                style: const TextStyle(
                  color: ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
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

class BloodOxygenChart extends StatelessWidget {
  final List<CareRecord> records;
  final int days;
  const BloodOxygenChart({super.key, required this.records, required this.days});

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
        '暂无该时段血氧记录',
        '记录后的血氧饱和度数值将在这里连线展示，帮助评估呼吸供氧状况',
      );
    }

    final points = <Offset>[];
    final labels = <String>[];
    double sum = 0;
    int count = 0;

    if (days == 1) {
      for (final r in selected) {
        final val = double.tryParse(r.text('bloodOxygen'));
        if (val != null) {
          points.add(
            Offset(
              r.at.difference(start).inMinutes / (24 * 60),
              val,
            ),
          );
          sum += val;
          count++;
        }
      }
      labels.addAll(['00:00', '12:00', '24:00']);
    } else {
      for (var d = 0; d < days; d++) {
        final key = dayKey(DateTime(start.year, start.month, start.day + d));
        final values = selected
            .where((r) => dayKey(r.at) == key)
            .map((r) => double.tryParse(r.text('bloodOxygen')))
            .whereType<double>()
            .toList();
        if (values.isNotEmpty) {
          final avg = values.reduce((a, b) => a + b) / values.length;
          points.add(Offset(d / (days - 1), avg));
          sum += avg;
          count++;
        }
      }
      labels.addAll([
        '${start.month}/${start.day}',
        '日均值趋势',
        '${now.month}/${now.day}',
      ]);
    }

    final latestVal = double.tryParse(selected.last.text('bloodOxygen')) ?? 98;
    final avgVal = count > 0 ? (sum / count) : latestVal;
    double minY = 90;
    for (final p in points) {
      if (p.dy < minY) minY = max(50, p.dy - 2);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    days == 1 ? '今日每次测值' : '每日均值（缺测不连线）',
                    style: const TextStyle(
                      color: ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F7FA),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '最新 ${latestVal.toStringAsFixed(latestVal.truncateToDouble() == latestVal ? 0 : 1)}%',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF00838F),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '均值 ${avgVal.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 11.5, color: muted),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 180,
          width: double.infinity,
          child: CustomPaint(
            painter: _OxygenPainter(
              points: points,
              days: days,
              minY: minY,
              maxY: 100,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final l in labels)
              Text(l, style: const TextStyle(color: muted, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 12, color: muted),
            SizedBox(width: 4),
            Text(
              '正常参考范围：95%–100% · 低于 93% 建议警惕或就医',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
        ),
      ],
    );
  }
}

class _OxygenPainter extends CustomPainter {
  final List<Offset> points;
  final int days;
  final double minY;
  final double maxY;

  _OxygenPainter({
    required this.points,
    required this.days,
    required this.minY,
    required this.maxY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftMargin = 32.0;
    final plotWidth = size.width - leftMargin - 10;
    const topMargin = 12.0;
    final plotHeight = size.height - topMargin - 16;

    final gridLinePaint = Paint()
      ..color = const Color(0xFFE8ECE7)
      ..strokeWidth = 0.8;

    final baseline95Paint = Paint()
      ..color = const Color(0xFF81C784)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final baseline93Paint = Paint()
      ..color = const Color(0xFFE57373)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final yRange = maxY - minY;
    double yPos(double value) =>
        topMargin + plotHeight * (1 - (value - minY) / yRange);

    // 绘制横参考网格
    final gridValues = {100.0, 95.0, 93.0, minY}.toList()..sort();
    for (final v in gridValues) {
      final y = yPos(v);
      final is95 = (v - 95).abs() < 0.1;
      final is93 = (v - 93).abs() < 0.1;
      final paint = is93
          ? baseline93Paint
          : is95
          ? baseline95Paint
          : gridLinePaint;

      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(leftMargin + plotWidth, y),
        paint,
      );

      final label = TextPainter(
        text: TextSpan(
          text: '${v.toInt()}%',
          style: TextStyle(
            color: is93
                ? const Color(0xFFC62828)
                : is95
                ? const Color(0xFF2E7D32)
                : muted,
            fontSize: 9.5,
            fontWeight: is95 || is93 ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(2, y - 6));
    }

    Offset position(Offset p) => Offset(
      leftMargin + p.dx * plotWidth,
      yPos(p.dy.clamp(minY, maxY)),
    );

    final linePaint = Paint()
      ..color = const Color(0xFF00838F)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final dotBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var i = 0; i < points.length; i++) {
      if (i > 0 &&
          (days == 1 ||
              points[i].dx - points[i - 1].dx <= 1 / (days - 1) + .0001)) {
        canvas.drawLine(position(points[i - 1]), position(points[i]), linePaint);
      }
      final pos = position(points[i]);
      final val = points[i].dy;
      final dotColor = val <= 93
          ? const Color(0xFFD32F2F)
          : val < 95
          ? const Color(0xFFEF6C00)
          : const Color(0xFF00838F);

      final dotPaint = Paint()
        ..color = dotColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(pos, 5, dotPaint);
      canvas.drawCircle(pos, 5, dotBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OxygenPainter old) => true;
}

