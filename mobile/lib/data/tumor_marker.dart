import 'dart:convert';

/// 单项肿瘤标志物数据
class TumorMarkerItem {
  final String key;
  final String name;
  final String abbr;
  final String value;
  final String unit;
  final String ref;
  final String hint;
  final String status; // 'normal' | 'high' | 'low' | ''

  const TumorMarkerItem({
    required this.key,
    required this.name,
    required this.abbr,
    required this.value,
    required this.unit,
    required this.ref,
    required this.hint,
    this.status = '',
  });

  TumorMarkerItem copyWith({
    String? value,
    String? unit,
    String? ref,
    String? status,
  }) => TumorMarkerItem(
    key: key,
    name: name,
    abbr: abbr,
    value: value ?? this.value,
    unit: unit ?? this.unit,
    ref: ref ?? this.ref,
    hint: hint,
    status: status ?? this.status,
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'abbr': abbr,
    'value': value,
    'unit': unit,
    'ref': ref,
    'hint': hint,
    'status': status,
  };

  factory TumorMarkerItem.fromJson(Map<String, dynamic> json) => TumorMarkerItem(
    key: json['key'] as String? ?? '',
    name: json['name'] as String? ?? '',
    abbr: json['abbr'] as String? ?? '',
    value: json['value'] as String? ?? '',
    unit: json['unit'] as String? ?? '',
    ref: json['ref'] as String? ?? '',
    hint: json['hint'] as String? ?? '',
    status: json['status'] as String? ?? '',
  );

  /// 自动比对参考区间判断状态
  static String detectStatus(String valStr, String refStr) {
    valStr = valStr.trim();
    if (valStr.isEmpty) return '';
    final val = double.tryParse(valStr);
    if (val == null) return '';

    refStr = refStr.trim().replaceAll('，', ',').replaceAll('~', '–').replaceAll('-', '–');
    // 情况1：< X 或 <= X
    final lessMatch = RegExp(r'^(?:<|≤)\s*([0-9.]+)').firstMatch(refStr);
    if (lessMatch != null) {
      final max = double.tryParse(lessMatch.group(1)!);
      if (max != null) {
        return val > max ? 'high' : 'normal';
      }
    }

    // 情况2：0–X 或 A–B
    final rangeMatch = RegExp(r'^([0-9.]+)\s*[–—]\s*([0-9.]+)').firstMatch(refStr);
    if (rangeMatch != null) {
      final min = double.tryParse(rangeMatch.group(1)!);
      final max = double.tryParse(rangeMatch.group(2)!);
      if (min != null && max != null) {
        if (val > max) return 'high';
        if (val < min) return 'low';
        return 'normal';
      }
    }

    return 'normal';
  }
}

/// 临床常见的肿瘤标志物 12 项标准定义（C12 芯片 / 经典体检12项）
const defaultTumorMarkers12 = <TumorMarkerItem>[
  TumorMarkerItem(
    key: 'afp',
    name: '甲胎蛋白',
    abbr: 'AFP',
    value: '',
    unit: 'ng/ml',
    ref: '0–7',
    hint: '原发性肝癌、生殖系统肿瘤',
  ),
  TumorMarkerItem(
    key: 'cea',
    name: '癌胚抗原',
    abbr: 'CEA',
    value: '',
    unit: 'ng/mL',
    ref: '0–5',
    hint: '广谱消化道、肺癌、乳腺癌等',
  ),
  TumorMarkerItem(
    key: 'nse',
    name: '神经元特异烯醇化酶',
    abbr: 'NSE',
    value: '',
    unit: 'ng/mL',
    ref: '0–16.3',
    hint: '小细胞肺癌、神经内分泌肿瘤',
  ),
  TumorMarkerItem(
    key: 'ca50',
    name: '糖类抗原50',
    abbr: 'CA50',
    value: '',
    unit: 'U/mL',
    ref: '0–25',
    hint: '胰腺癌、结直肠癌、胃癌等',
  ),
  TumorMarkerItem(
    key: 'ferr',
    name: '铁蛋白',
    abbr: 'FERR',
    value: '',
    unit: 'ng/ml',
    ref: '13–150',
    hint: '原发性肝癌、血液系统肿瘤广谱辅助',
  ),
  TumorMarkerItem(
    key: 'scc',
    name: '鳞状上皮细胞癌抗原',
    abbr: 'SCC',
    value: '',
    unit: 'ng/ml',
    ref: '0–1.5',
    hint: '宫颈鳞癌、肺鳞癌、食管癌等',
  ),
  TumorMarkerItem(
    key: 'ca199',
    name: '糖类抗原19-9',
    abbr: 'CA19-9',
    value: '',
    unit: 'U/ml',
    ref: '0–26.1',
    hint: '胰腺癌、胆管癌、消化系统肿瘤',
  ),
  TumorMarkerItem(
    key: 'ca242',
    name: '糖类抗原242',
    abbr: 'CA242',
    value: '',
    unit: 'U/ml',
    ref: '0–10',
    hint: '胰腺癌、胃癌、结直肠癌',
  ),
  TumorMarkerItem(
    key: 'ca125',
    name: '糖类抗原125',
    abbr: 'CA125',
    value: '',
    unit: 'U/ml',
    ref: '0–31.3',
    hint: '卵巢癌、子宫内膜癌',
  ),
  TumorMarkerItem(
    key: 'ca153',
    name: '糖类抗原15-3',
    abbr: 'CA15-3',
    value: '',
    unit: 'U/ml',
    ref: '0–27.8',
    hint: '乳腺癌辅助监测',
  ),
  TumorMarkerItem(
    key: 'ca724',
    name: '糖类抗原72-4',
    abbr: 'CA72-4',
    value: '',
    unit: 'U/ml',
    ref: '0–8.79',
    hint: '胃癌及其他消化系统肿瘤',
  ),
  TumorMarkerItem(
    key: 'cyfra1',
    name: '细胞角蛋白19片段',
    abbr: 'CYFRA-1',
    value: '',
    unit: 'ng/mL',
    ref: '0–3.3',
    hint: '非小细胞肺癌（肺鳞癌）等',
  ),
];

/// 解析记录中的 markers JSON
List<TumorMarkerItem> parseTumorMarkers(String jsonStr) {
  if (jsonStr.trim().isEmpty) {
    return defaultTumorMarkers12;
  }
  try {
    final list = jsonDecode(jsonStr) as List;
    final map = <String, TumorMarkerItem>{};
    for (final item in list) {
      if (item is Map) {
        final parsed = TumorMarkerItem.fromJson(Map<String, dynamic>.from(item));
        if (parsed.key.isNotEmpty) {
          map[parsed.key] = parsed;
        }
      }
    }
    // 合并默认12项，保证顺序且兼容新增指标
    return defaultTumorMarkers12.map((def) {
      if (map.containsKey(def.key)) {
        final existing = map[def.key]!;
        return def.copyWith(
          value: existing.value,
          unit: existing.unit.isNotEmpty ? existing.unit : def.unit,
          ref: existing.ref.isNotEmpty ? existing.ref : def.ref,
          status: existing.status,
        );
      }
      return def;
    }).toList();
  } catch (_) {
    return defaultTumorMarkers12;
  }
}

/// 序列化 markers 为 JSON
String encodeTumorMarkers(List<TumorMarkerItem> items) =>
    jsonEncode(items.map((e) => e.toJson()).toList());

/// 生成肿瘤标志物整体摘要
String summarizeTumorMarkers(List<TumorMarkerItem> items) {
  final filled = items.where((e) => e.value.trim().isNotEmpty || e.status.isNotEmpty).toList();
  if (filled.isEmpty) return '未录入指标';

  final highItems = filled.where((e) => e.status == 'high').toList();
  final lowItems = filled.where((e) => e.status == 'low').toList();

  if (highItems.isEmpty && lowItems.isEmpty) {
    return '已录入 ${filled.length} 项，全部正常';
  }

  final parts = <String>[];
  if (highItems.isNotEmpty) {
    final names = highItems.map((e) => e.abbr.isNotEmpty ? e.abbr : e.name).join('、');
    parts.add('${highItems.length} 项偏高 ($names)');
  }
  if (lowItems.isNotEmpty) {
    final names = lowItems.map((e) => e.abbr.isNotEmpty ? e.abbr : e.name).join('、');
    parts.add('${lowItems.length} 项偏低 ($names)');
  }
  return parts.join('，');
}

/// 单项标志物与前次对比差异
class TumorMarkerDiff {
  final TumorMarkerItem current;
  final TumorMarkerItem? previous;
  final double? prevVal;
  final double? currentVal;
  final double? diffValue;
  final double? diffPercent;
  final String trend; // 'up', 'down', 'flat', 'none'
  final bool isHigh;
  final bool isNewlyHigh;
  final bool isReturnedNormal;

  const TumorMarkerDiff({
    required this.current,
    this.previous,
    this.prevVal,
    this.currentVal,
    this.diffValue,
    this.diffPercent,
    required this.trend,
    required this.isHigh,
    required this.isNewlyHigh,
    required this.isReturnedNormal,
  });

  String get formattedDiff {
    if (prevVal == null || currentVal == null || diffValue == null) {
      return previous != null && previous!.value.isNotEmpty ? '本次未测' : '首笔基线';
    }
    if (trend == 'flat') return '持平';
    final sign = diffValue! > 0 ? '+' : '';
    final valStr = diffValue!.abs() >= 10
        ? diffValue!.toStringAsFixed(1)
        : diffValue!.toStringAsFixed(2);
    final arrow = trend == 'up' ? '↑' : '↓';
    if (diffPercent != null) {
      final pctSign = diffPercent! > 0 ? '+' : '';
      return '$sign$valStr ($pctSign${diffPercent!.toStringAsFixed(1)}%) $arrow';
    }
    return '$sign$valStr $arrow';
  }
}

/// 肿瘤标志物整体对比结果
class TumorMarkersComparison {
  final bool hasPrevious;
  final DateTime? currentAt;
  final DateTime? previousAt;
  final List<TumorMarkerDiff> diffs;
  final List<TumorMarkerDiff> keyChanges;
  final int upCount;
  final int downCount;
  final int flatCount;
  final int newlyHighCount;
  final int returnedNormalCount;
  final String summary;

  const TumorMarkersComparison({
    required this.hasPrevious,
    this.currentAt,
    this.previousAt,
    required this.diffs,
    required this.keyChanges,
    required this.upCount,
    required this.downCount,
    required this.flatCount,
    required this.newlyHighCount,
    required this.returnedNormalCount,
    required this.summary,
  });
}

/// 对比当前标志物列表与前次标志物列表
TumorMarkersComparison compareTumorMarkers(
  List<TumorMarkerItem> current,
  List<TumorMarkerItem>? previous, {
  DateTime? currentAt,
  DateTime? previousAt,
}) {
  if (previous == null) {
    final diffs = current.map((c) {
      final curVal = double.tryParse(c.value.trim());
      return TumorMarkerDiff(
        current: c,
        previous: null,
        currentVal: curVal,
        trend: 'none',
        isHigh: c.status == 'high',
        isNewlyHigh: false,
        isReturnedNormal: false,
      );
    }).toList();

    return TumorMarkersComparison(
      hasPrevious: false,
      currentAt: currentAt,
      previousAt: null,
      diffs: diffs,
      keyChanges: const [],
      upCount: 0,
      downCount: 0,
      flatCount: 0,
      newlyHighCount: 0,
      returnedNormalCount: 0,
      summary: '基线记录',
    );
  }

  final prevMap = {for (final p in previous) p.key: p};
  final diffs = <TumorMarkerDiff>[];
  final keyChanges = <TumorMarkerDiff>[];

  int upCount = 0;
  int downCount = 0;
  int flatCount = 0;
  int newlyHighCount = 0;
  int returnedNormalCount = 0;

  for (final cur in current) {
    final prev = prevMap[cur.key];
    final curVal = double.tryParse(cur.value.trim());
    final prevVal = prev != null ? double.tryParse(prev.value.trim()) : null;

    double? diffVal;
    double? diffPct;
    String trend = 'none';

    if (curVal != null && prevVal != null) {
      diffVal = curVal - prevVal;
      if (prevVal > 0) {
        diffPct = (diffVal / prevVal) * 100;
      }
      if (diffVal > 0.0001) {
        trend = 'up';
        upCount++;
      } else if (diffVal < -0.0001) {
        trend = 'down';
        downCount++;
      } else {
        trend = 'flat';
        flatCount++;
      }
    }

    final isHigh = cur.status == 'high';
    final wasHigh = prev?.status == 'high';
    final isNewlyHigh = isHigh && !wasHigh && cur.value.isNotEmpty;
    final isReturnedNormal = wasHigh && cur.status == 'normal';

    if (isNewlyHigh) newlyHighCount++;
    if (isReturnedNormal) returnedNormalCount++;

    final diff = TumorMarkerDiff(
      current: cur,
      previous: prev,
      prevVal: prevVal,
      currentVal: curVal,
      diffValue: diffVal,
      diffPercent: diffPct,
      trend: trend,
      isHigh: isHigh,
      isNewlyHigh: isNewlyHigh,
      isReturnedNormal: isReturnedNormal,
    );

    diffs.add(diff);

    // 关键变动项目：新增偏高、恢复正常、偏高且继续上升
    if (isNewlyHigh || isReturnedNormal || (isHigh && trend == 'up')) {
      keyChanges.add(diff);
    }
  }

  String summary;
  if (newlyHighCount > 0) {
    summary = '⚠️ 新增偏高项，需关注';
  } else if (returnedNormalCount > 0 && upCount == 0) {
    summary = '🎉 指标好转改善';
  } else if (downCount > upCount) {
    summary = '整体向好回落';
  } else if (upCount > downCount) {
    summary = '部分指标有所上升';
  } else {
    summary = '指标整体相对平稳';
  }

  return TumorMarkersComparison(
    hasPrevious: true,
    currentAt: currentAt,
    previousAt: previousAt,
    diffs: diffs,
    keyChanges: keyChanges,
    upCount: upCount,
    downCount: downCount,
    flatCount: flatCount,
    newlyHighCount: newlyHighCount,
    returnedNormalCount: returnedNormalCount,
    summary: summary,
  );
}
