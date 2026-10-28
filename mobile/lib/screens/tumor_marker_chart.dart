import 'dart:math';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/tumor_marker.dart';
import '../ui.dart';

class TumorMarkerChart extends StatefulWidget {
  final List<CareRecord> records;

  const TumorMarkerChart({super.key, required this.records});

  @override
  State<TumorMarkerChart> createState() => _TumorMarkerChartState();
}

class _TumorMarkerChartState extends State<TumorMarkerChart> {
  String selectedKey = 'cea';

  @override
  Widget build(BuildContext context) {
    // 找出有数据或默认的指标列表
    final allDefs = defaultTumorMarkers12;
    final selectedDef = allDefs.firstWhere(
      (e) => e.key == selectedKey,
      orElse: () => allDefs[1], // 默认 CEA
    );

    // 提取当前选中指标在历次记录中的数据点（按时间升序）
    final sortedRecords = widget.records.toList()
      ..sort((a, b) => a.at.compareTo(b.at));

    final points = <_MarkerDataPoint>[];
    for (final r in sortedRecords) {
      if (r.kind != 'tumorMarker') continue;
      final items = parseTumorMarkers(r.text('markers'));
      final found = items.where((e) => e.key == selectedKey).firstOrNull;
      if (found != null && found.value.isNotEmpty) {
        final val = double.tryParse(found.value);
        if (val != null) {
          points.add(_MarkerDataPoint(
            at: r.at,
            value: val,
            status: found.status,
            unit: found.unit,
            ref: found.ref,
          ));
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 指标选择栏
        Row(
          children: [
            Expanded(
              child: Text(
                '${selectedDef.name} (${selectedDef.abbr}) 趋势',
                style: const TextStyle(
                  color: ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedKey,
                  isDense: true,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF00796B),
                    fontWeight: FontWeight.w600,
                  ),
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: Color(0xFF00796B),
                  ),
                  items: allDefs.map((def) {
                    return DropdownMenuItem<String>(
                      value: def.key,
                      child: Text('${def.abbr} · ${def.name}'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => selectedKey = val);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '临床参考: ${selectedDef.hint} · 标准参考范围: ${selectedDef.ref} ${selectedDef.unit}',
          style: const TextStyle(fontSize: 11, color: muted),
        ),
        const SizedBox(height: 16),

        // 2. 折线图绘制区
        if (points.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: EmptyState(
                Icons.analytics_outlined,
                '暂无该指标测定数据',
                '在添加肿瘤标志物检测时填写该数值，即可生成随访趋势对比曲线',
              ),
            ),
          )
        else
          SizedBox(
            height: 190,
            width: double.infinity,
            child: CustomPaint(
              painter: _TumorMarkerPainter(points: points),
            ),
          ),

        if (points.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '最早记录: ${dayKey(points.first.at)}',
                style: const TextStyle(fontSize: 10.5, color: muted),
              ),
              Text(
                '最新记录: ${points.last.value} ${points.last.unit} (${points.last.status == 'high' ? '偏高' : '正常'})',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: points.last.status == 'high'
                      ? const Color(0xFFC62828)
                      : const Color(0xFF2E7D32),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MarkerDataPoint {
  final DateTime at;
  final double value;
  final String status;
  final String unit;
  final String ref;

  const _MarkerDataPoint({
    required this.at,
    required this.value,
    required this.status,
    required this.unit,
    required this.ref,
  });
}

class _TumorMarkerPainter extends CustomPainter {
  final List<_MarkerDataPoint> points;

  _TumorMarkerPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paddingLeft = 32.0;
    final paddingRight = 20.0;
    final paddingTop = 24.0;
    final paddingBottom = 26.0;

    final chartWidth = size.width - paddingLeft - paddingRight;
    final chartHeight = size.height - paddingTop - paddingBottom;

    // 计算 Y 轴最大值（取所有数据点最大值与参考上限的较大值）
    var maxVal = points.map((p) => p.value).reduce(max);
    // 尝试解析参考上限
    double? refMax;
    final refStr = points.first.ref;
    final rangeMatch = RegExp(r'(?:<|≤|–|—|-)\s*([0-9.]+)').firstMatch(refStr);
    if (rangeMatch != null) {
      refMax = double.tryParse(rangeMatch.group(1)!);
    }
    if (refMax != null && refMax > maxVal) {
      maxVal = refMax;
    }
    maxVal = maxVal == 0 ? 10 : maxVal * 1.25; // 顶部留白

    // 绘制水平网格与 Y 轴刻度
    final gridPaint = Paint()
      ..color = const Color(0xFFEDF2EC)
      ..strokeWidth = 1;

    for (var i = 0; i <= 3; i++) {
      final yRatio = i / 3;
      final y = paddingTop + chartHeight * (1 - yRatio);
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width - paddingRight, y), gridPaint);

      final valLabel = (maxVal * yRatio).toStringAsFixed(maxVal >= 10 ? 0 : 1);
      final tp = TextPainter(
        text: TextSpan(
          text: valLabel,
          style: const TextStyle(color: muted, fontSize: 9.5),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(paddingLeft - tp.width - 6, y - tp.height / 2));
    }

    // 如果有参考上限，画一条虚线红/橙提示参考线
    if (refMax != null && refMax <= maxVal) {
      final refY = paddingTop + chartHeight * (1 - (refMax / maxVal));
      final refLinePaint = Paint()
        ..color = const Color(0xFFEF9A9A)
        ..strokeWidth = 1.2;

      // 绘制虚线
      var startX = paddingLeft;
      while (startX < size.width - paddingRight) {
        canvas.drawLine(
          Offset(startX, refY),
          Offset(min(startX + 6, size.width - paddingRight), refY),
          refLinePaint,
        );
        startX += 10;
      }

      final refText = TextPainter(
        text: TextSpan(
          text: '参考上限 $refMax',
          style: const TextStyle(color: Color(0xFFE53935), fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      refText.paint(canvas, Offset(size.width - paddingRight - refText.width, refY - 12));
    }

    // 计算各个点的坐标
    Offset calcPos(int index) {
      final x = points.length == 1
          ? paddingLeft + chartWidth / 2
          : paddingLeft + (chartWidth * index / (points.length - 1));
      final y = paddingTop + chartHeight * (1 - (points[index].value / maxVal));
      return Offset(x, y);
    }

    // 绘制折线
    final linePaint = Paint()
      ..color = const Color(0xFF00796B)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < points.length - 1; i++) {
      canvas.drawLine(calcPos(i), calcPos(i + 1), linePaint);
    }

    // 绘制每个数据点与标签
    for (var i = 0; i < points.length; i++) {
      final pos = calcPos(i);
      final isHigh = points[i].status == 'high';
      final pointColor = isHigh ? const Color(0xFFD32F2F) : const Color(0xFF00796B);

      // 点的外圈与实心圆
      final dotPaint = Paint()..color = pointColor;
      final bgCirclePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = pointColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(pos, 5, bgCirclePaint);
      canvas.drawCircle(pos, 4, dotPaint);
      canvas.drawCircle(pos, 5, borderPaint);

      // 数值文本 (点上方)
      final valStr = points[i].value.toStringAsFixed(
        points[i].value.truncateToDouble() == points[i].value ? 0 : 1,
      );
      final valText = TextPainter(
        text: TextSpan(
          text: isHigh ? '$valStr↑' : valStr,
          style: TextStyle(
            color: pointColor,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      valText.paint(canvas, Offset(pos.dx - valText.width / 2, pos.dy - 16));

      // 日期文本 (点下方)
      final dateStr = '${points[i].at.month}/${points[i].at.day}';
      final dateText = TextPainter(
        text: TextSpan(
          text: dateStr,
          style: const TextStyle(color: muted, fontSize: 9.5),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      dateText.paint(
        canvas,
        Offset(pos.dx - dateText.width / 2, size.height - paddingBottom + 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TumorMarkerPainter old) => true;
}
