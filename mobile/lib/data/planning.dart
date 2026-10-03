import 'models.dart';

const healthKinds = ['weight', 'stool', 'urine', 'pain', 'symptom'];
const journeyCategories = {'picc': 'PICC护理', 'port': '输液港护理', 'chemo': '化疗'};
const defaultHealthOptions = <String, List<String>>{
  'stoolStatus': ['正常', '未排便', '黑便', '血便', '便秘', '腹泻'],
  'urineStatus': ['正常', '尿痛', '血尿'],
  'urineColor': ['浅黄', '淡黄色，类似淡啤酒色'],
  'urineAppearance': ['清澈', '泡沫很少，静置一会泡沫消失', '泡沫很多'],
};

int minuteOfDay(String value) {
  if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
    throw const FormatException('时间格式应为 HH:mm');
  }
  final p = value.split(':').map(int.parse).toList();
  return p[0] * 60 + p[1];
}

String minuteLabel(int value) =>
    '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
int settingInt(
  Map<String, String> s,
  String key,
  int fallback,
  int min,
  int max,
) {
  final value = int.tryParse(s[key] ?? '$fallback');
  if (value == null || value < min || value > max) {
    throw FormatException('$key 应为 $min–$max 的整数');
  }
  return value;
}

List<int> mealTimes(Map<String, String> s) {
  final start = minuteOfDay(s['mealStart'] ?? '07:30');
  final end = minuteOfDay(s['mealEnd'] ?? '18:30');
  final count = settingInt(s, 'mealCount', 5, 1, 12);
  final duration = settingInt(s, 'mealDuration', 30, 5, 180);
  if (end <= start || count * duration > end - start) {
    throw const FormatException('用餐时段不足，请减少次数或时长');
  }
  return List.generate(
    count,
    (i) => count == 1
        ? start
        : start + ((end - start - duration) * i / (count - 1)).round(),
  );
}

List<int> waterTimes(Map<String, String> s) {
  if ((s['waterStart'] ?? '').isEmpty || (s['waterEnd'] ?? '').isEmpty) {
    return [];
  }
  final start = minuteOfDay(s['waterStart']!);
  final end = minuteOfDay(s['waterEnd']!);
  final interval = settingInt(s, 'waterInterval', 30, 5, 720);
  if (end <= start) throw const FormatException('喝水结束时间必须晚于开始时间');
  return [for (var t = start; t <= end; t += interval) t];
}

CareRecord latestJourney(List<CareRecord> records, CareRecord journey) {
  final entries =
      [
        journey,
        ...records.where(
          (r) => r.kind == 'journeyEntry' && r.text('journeyId') == journey.id,
        ),
      ]..sort((a, b) {
        final result = DateTime.parse(b.text('last'))
            .compareTo(DateTime.parse(a.text('last')));
        return result != 0 ? result : b.at.compareTo(a.at);
      });
  return entries.first;
}

class PlannedReminder {
  final DateTime at;
  final String channel, title, body;
  final bool daily;
  final List<String> categories;
  PlannedReminder(
    this.at,
    this.channel,
    this.title,
    this.body, {
    this.daily = false,
    List<String>? categories,
  }) : categories = categories ?? [channel];
}

const reminderNames = {'meal': '用餐', 'water': '喝水', ...journeyCategories};

/// Daily Android alarms do not consume one slot per day. Keep capacity for each
/// category on iOS so frequent water reminders cannot crowd out meals.
List<PlannedReminder> scheduleReminders(
  CareData data,
  DateTime now, {
  required bool android,
}) {
  final raw = planReminders(data, now);
  final daily = <String, PlannedReminder>{};
  final events = <PlannedReminder>[];
  for (final item in raw) {
    if (!['meal', 'water'].contains(item.channel)) {
      events.add(item);
      continue;
    }
    final key = android ? clockText(item.at) : item.at.toIso8601String();
    final previous = daily[key];
    if (previous == null) {
      daily[key] = PlannedReminder(
        item.at,
        item.channel,
        item.title,
        item.body,
        daily: android,
      );
    } else if (!previous.categories.contains(item.channel) &&
        previous.at == item.at) {
      // One alert contains both reminders instead of competing heads-up banners.
      daily[key] = PlannedReminder(
        item.at,
        'meal',
        '用餐与喝水提醒',
        '${previous.body}\n${item.body}',
        daily: android,
        categories: ['meal', 'water'],
      );
    }
  }
  final all = [...daily.values, ...events]
    ..sort((a, b) => a.at.compareTo(b.at));
  if (android) {
    final repeating = all.where((r) => r.daily).toList();
    return [...repeating, ...events.take(450 - repeating.length)]
      ..sort((a, b) => a.at.compareTo(b.at));
  }
  final groups = {
    for (final category in reminderNames.keys)
      category: all.where((r) => r.categories.contains(category)).iterator,
  };
  final selected = <PlannedReminder>{};
  var progressed = true;
  while (selected.length < 60 && progressed) {
    progressed = false;
    for (final group in groups.values) {
      if (group.moveNext()) {
        progressed = true;
        selected.add(group.current);
      }
      if (selected.length == 60) break;
    }
  }
  return selected.toList()..sort((a, b) => a.at.compareTo(b.at));
}

List<PlannedReminder> planReminders(
  CareData data,
  DateTime now, {
  int days = 14,
}) {
  final s = data.settings;
  final result = <PlannedReminder>[];
  void add(DateTime at, String channel, String title, String body) {
    if (at.isAfter(now)) result.add(PlannedReminder(at, channel, title, body));
  }

  for (var i = 0; i < days; i++) {
    final day = DateTime(now.year, now.month, now.day + i);
    DateTime at(int minutes) =>
        DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
    if (s['notifyMeal'] == 'true') {
      for (final t in mealTimes(s)) {
        add(at(t), 'meal', '用餐提醒', '到了安排的用餐时间，请按个人情况进食。');
      }
    }
    if (s['notifyWater'] == 'true') {
      for (final t in waterTimes(s)) {
        add(at(t), 'water', '喝水提醒', '请按医嘱和个人情况补水。');
      }
    }
    for (final journey in data.records.where((r) => r.kind == 'journey')) {
      final category = journey.text('category');
      if (s['notify_$category'] != 'true') continue;
      final entry = latestJourney(data.records, journey);
      final due = DateTime.parse(entry.text('next'));
      final dueDay = DateTime(due.year, due.month, due.day);
      final lead = settingInt(s, 'lead_$category', 3, 0, 90);
      final count = settingInt(s, 'count_$category', 1, 1, 8);
      final first = DateTime(due.year, due.month, due.day - lead);
      if (day.isBefore(first) || day.isAfter(dueDay)) continue;
      if (day == dueDay) {
        add(
          due,
          category,
          '${journeyCategories[category]}行程提醒',
          '今天有已安排的行程，请打开安伴核对。',
        );
      } else {
        for (var j = 0; j < count; j++) {
          final time =
              9 * 60 + (count == 1 ? 0 : (9 * 60 * j / (count - 1)).round());
          add(
            at(time),
            category,
            '${journeyCategories[category]}即将到期',
            '请打开安伴核对下次执行时间。',
          );
        }
      }
    }
  }
  return result..sort((a, b) => a.at.compareTo(b.at));
}
