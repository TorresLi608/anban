import 'dart:convert';
import 'dart:math';

String newId() =>
    base64UrlEncode(List.generate(18, (_) => Random.secure().nextInt(256)));
String dayKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String clockText(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
const recordKinds = [
  'weight',
  'stool',
  'urine',
  'journey',
  'journeyEntry',
  'pain',
  'symptom',
  'vital',
  'medication',
  'dose',
  'task',
  'appointment',
  'handover',
  'mood',
  'memory',
  'document',
];
const symptomNames = [
  '黄疸',
  '腹胀',
  '恶心',
  '呕吐',
  '食欲差',
  '腹泻',
  '便秘',
  '低烧',
  '乏力',
  '睡眠差',
  '体重下降',
  '皮肤瘙痒',
];
const disclaimer =
    '本 APP 仅为居家陪护辅助工具，不具备医疗诊断功能，所有护理、用药、治疗决策请严格遵从主治医生医嘱。突发紧急情况请立即联系医院或就医。';

class CareRecord {
  final String id;
  final String kind;
  final DateTime at;
  final Map<String, String> fields;
  CareRecord({
    String? id,
    required this.kind,
    DateTime? at,
    required Map<String, String> fields,
  }) : id = id ?? newId(),
       at = at ?? DateTime.now(),
       fields = Map.unmodifiable(fields);
  String text(String key, [String fallback = '']) => fields[key] ?? fallback;
  double number(String key) => double.tryParse(text(key)) ?? 0;
  CareRecord copy({Map<String, String>? fields, DateTime? at}) => CareRecord(
    id: id,
    kind: kind,
    at: at ?? this.at,
    fields: fields ?? this.fields,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'at': at.toIso8601String(),
    'fields': fields,
  };
  factory CareRecord.fromJson(dynamic value) {
    final m = Map<String, dynamic>.from(value as Map);
    if (m['id'] is! String ||
        (m['id'] as String).length > 100 ||
        !recordKinds.contains(m['kind'])) {
      throw const FormatException('记录类型或标识无效');
    }
    final fields = Map<String, String>.from(m['fields'] as Map);
    if (fields.length > 30 ||
        fields.entries.any(
          (e) => e.key.length > 60 || e.value.length > 10000,
        )) {
      throw const FormatException('记录字段过长');
    }
    final r = CareRecord(
      id: m['id'],
      kind: m['kind'],
      at: DateTime.parse(m['at']).toLocal(),
      fields: fields,
    );
    r.validate();
    return r;
  }
  void validate() {
    if (id.isEmpty || !recordKinds.contains(kind)) {
      throw const FormatException('记录无效');
    }
    if (kind == 'pain' &&
        (int.tryParse(text('score')) == null ||
            number('score') < 0 ||
            number('score') > 10)) {
      throw const FormatException('疼痛分值应为 0–10 的整数');
    }
    if (photosOf(this).length > 9) {
      throw const FormatException('每条记录最多上传 9 张图片');
    }
    if (kind == 'weight') {
      final weight = double.tryParse(text('weight'));
      if (weight == null || !weight.isFinite || weight <= 0 || weight > 500) {
        throw const FormatException('请填写有效体重（kg）');
      }
      if (text('temperature').isNotEmpty) {
        final temperature = double.tryParse(text('temperature'));
        if (temperature == null ||
            !temperature.isFinite ||
            temperature < 30 ||
            temperature > 45) {
          throw const FormatException('请核对体温');
        }
      }
    }
    if (['stool', 'urine'].contains(kind) &&
        selectedValues(text('status')).isEmpty) {
      throw const FormatException('排便情况为必填项');
    }
    if (['journey', 'journeyEntry'].contains(kind)) {
      if (kind == 'journey' &&
          !['picc', 'port', 'chemo'].contains(text('category'))) {
        throw const FormatException('请选择行程分类');
      }
      if (kind == 'journeyEntry' && text('journeyId').isEmpty) {
        throw const FormatException('缺少所属行程');
      }
      final last = DateTime.tryParse(text('last'));
      final next = DateTime.tryParse(text('next'));
      if (last == null || next == null || !next.isAfter(last)) {
        throw const FormatException('请填写上次和下次执行时间，下次必须晚于上次');
      }
    }
    if (kind == 'medication') {
      if (text('name').trim().isEmpty || text('dose').trim().isEmpty) {
        throw const FormatException('请填写药物名称和医嘱剂量');
      }
      if (!['常规维持', '按需补救'].contains(text('type'))) {
        throw const FormatException('请选择用药类型');
      }
      if (text('type') == '常规维持' && parseTimes(text('times')).isEmpty) {
        throw const FormatException('请填写固定服药时间');
      }
      final start = DateTime.tryParse(text('start'));
      final end = text('end').isEmpty ? null : DateTime.tryParse(text('end'));
      if (start == null ||
          (text('end').isNotEmpty && end == null) ||
          (end != null && end.isBefore(start))) {
        throw const FormatException('请检查用药起止日期');
      }
    }
    if (kind == 'symptom' &&
        (!symptomNames.contains(text('name')) ||
            !['轻', '中', '重'].contains(text('severity')))) {
      throw const FormatException('症状或程度无效');
    }
    if (kind == 'vital') {
      for (final item in [
        ('temperature', 30.0, 45.0),
        ('weight', 10.0, 300.0),
        ('sleep', 0.0, 24.0),
      ]) {
        if (text(item.$1).isNotEmpty) {
          final n = double.tryParse(text(item.$1));
          if (n == null || !n.isFinite || n < item.$2 || n > item.$3) {
            throw const FormatException('体征数值超出有效范围，请核对');
          }
        }
      }
    }
    if (kind == 'dose' &&
        (text('medicationId').isEmpty ||
            text('doseKey').isEmpty ||
            text('name').isEmpty)) {
      throw const FormatException('服药记录缺少药物信息');
    }
  }
}

List<String> parseTimes(String value) {
  if (value.trim().isEmpty) {
    return [];
  }
  final times =
      value
          .replaceAll('，', ',')
          .split(',')
          .map((s) => s.trim())
          .toSet()
          .toList()
        ..sort();
  if (times.length > 8 ||
      times.any((s) => !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(s))) {
    throw const FormatException('时间格式为 08:00,20:00，每日最多 8 次');
  }
  return times;
}

class PlannedDose {
  final CareRecord medication;
  final DateTime scheduled;
  final CareRecord? taken;
  PlannedDose(this.medication, this.scheduled, this.taken);
  String get key =>
      '${medication.id}|${dayKey(scheduled)}|${clockText(scheduled)}';
  bool overdue(DateTime now) => taken == null && scheduled.isBefore(now);
}

List<PlannedDose> dosesForDay(List<CareRecord> records, DateTime date) {
  final result = <PlannedDose>[];
  final day = dayKey(date);
  final doses = {
    for (final r in records.where((r) => r.kind == 'dose'))
      r.text('doseKey'): r,
  };
  for (final med in records.where(
    (r) => r.kind == 'medication' && r.text('type') == '常规维持',
  )) {
    if (day.compareTo(med.text('start')) < 0 ||
        (med.text('end').isNotEmpty && day.compareTo(med.text('end')) > 0)) {
      continue;
    }
    for (final time in parseTimes(med.text('times'))) {
      final parts = time.split(':').map(int.parse).toList();
      final at = DateTime(date.year, date.month, date.day, parts[0], parts[1]);
      result.add(PlannedDose(med, at, doses['${med.id}|$day|$time']));
    }
  }
  return result..sort((a, b) => a.scheduled.compareTo(b.scheduled));
}

class CareData {
  final List<CareRecord> records;
  final Map<String, String> profile;
  final Map<String, String> settings;
  CareData({
    List<CareRecord> records = const [],
    Map<String, String> profile = const {},
    Map<String, String> settings = const {},
  }) : records = List.unmodifiable(records),
       profile = Map.unmodifiable(profile),
       settings = Map.unmodifiable(settings);
  CareData copy({
    List<CareRecord>? records,
    Map<String, String>? profile,
    Map<String, String>? settings,
  }) => CareData(
    records: records ?? this.records,
    profile: profile ?? this.profile,
    settings: settings ?? this.settings,
  );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'records': records.map((r) => r.toJson()).toList(),
    'profile': profile,
    'settings': settings,
  };
  factory CareData.fromJson(dynamic value) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['records'] is! List ||
        (value['records'] as List).length > 50000) {
      throw const FormatException('备份格式或版本不支持');
    }
    final records = (value['records'] as List)
        .map(CareRecord.fromJson)
        .toList();
    if (records.map((r) => r.id).toSet().length != records.length) {
      throw const FormatException('备份包含重复记录');
    }
    final doseKeys = records
        .where((r) => r.kind == 'dose')
        .map((r) => r.text('doseKey'))
        .toList();
    if (doseKeys.toSet().length != doseKeys.length) {
      throw const FormatException('备份包含重复服药打卡');
    }
    return CareData(
      records: records,
      profile: Map<String, String>.from(value['profile'] as Map),
      settings: Map<String, String>.from(value['settings'] as Map),
    );
  }
}

List<String> selectedValues(String value) =>
    value.isEmpty ? [] : List<String>.from(jsonDecode(value) as List);
List<Map<String, String>> photosOf(CareRecord record) {
  final value = record.text('photos');
  if (value.isEmpty) return [];
  final photos = (jsonDecode(value) as List)
      .map((v) => Map<String, String>.from(v as Map))
      .toList();
  if (photos.length > 9 ||
      photos.any((p) => (p['id'] ?? '').isEmpty || p['id']!.length > 100)) {
    throw const FormatException('图片数据无效');
  }
  return photos;
}

Iterable<String> attachmentIds(CareRecord record) => {
  if (record.text('attachment').isNotEmpty) record.text('attachment'),
  ...photosOf(record).map((p) => p['id']!),
};
