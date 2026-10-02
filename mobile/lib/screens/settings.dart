import 'package:flutter/material.dart';

import '../data/planning.dart';
import '../data/store.dart';
import '../services/reminders.dart';
import '../ui.dart';

Future<void> openSettings(
  BuildContext context,
  CareStore store,
  ReminderService reminders,
) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => SettingsPage(store: store, reminders: reminders),
  ),
);

class SettingsPage extends StatefulWidget {
  final CareStore store;
  final ReminderService reminders;
  const SettingsPage({super.key, required this.store, required this.reminders});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final key = GlobalKey<FormState>();
  late Map<String, TextEditingController> inputs;
  late Map<String, bool> switches;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final s = widget.store.data.settings;
    final defaults = {
      'mealStart': '07:30',
      'mealEnd': '18:30',
      'mealCount': '5',
      'mealDuration': '30',
      'waterStart': '',
      'waterEnd': '',
      'waterInterval': '30',
      for (final category in journeyCategories.keys) ...{
        'lead_$category': '3',
        'count_$category': '1',
      },
    };
    inputs = {
      for (final e in defaults.entries)
        e.key: TextEditingController(text: s[e.key] ?? e.value),
    };
    switches = {
      for (final k in [
        'notifyMeal',
        'notifyWater',
        ...journeyCategories.keys.map((k) => 'notify_$k'),
      ])
        k: s[k] == 'true',
    };
  }

  @override
  void dispose() {
    for (final c in inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!key.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final values = {
        for (final e in inputs.entries) e.key: e.value.text.trim(),
        for (final e in switches.entries) e.key: '${e.value}',
      };
      mealTimes(values);
      if (values['waterStart']!.isNotEmpty ||
          values['waterEnd']!.isNotEmpty ||
          switches['notifyWater']!) {
        if (values['waterStart']!.isEmpty || values['waterEnd']!.isEmpty) {
          throw const FormatException('请填写喝水开始和结束时间');
        }
        waterTimes(values);
      }
      for (final category in journeyCategories.keys) {
        settingInt(values, 'lead_$category', 3, 0, 90);
        settingInt(values, 'count_$category', 1, 1, 8);
      }
      if (switches.values.any((v) => v) &&
          widget.reminders.supported &&
          !await widget.reminders.requestPermission()) {
        throw StateError('请先允许系统通知权限');
      }
      await widget.store.settings(values);
      await widget.reminders.refresh(widget.store.data, force: true);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
    if (mounted) setState(() => saving = false);
  }

  Widget field(String name, String label, {bool time = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: inputs[name],
      enabled: !saving,
      readOnly: time,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      onTap: !time
          ? null
          : () async {
              final old = inputs[name]!.text;
              final minutes = old.isEmpty ? 8 * 60 : minuteOfDay(old);
              final value = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: minutes ~/ 60,
                  minute: minutes % 60,
                ),
              );
              if (value != null && mounted) {
                setState(
                  () => inputs[name]!.text = minuteLabel(
                    value.hour * 60 + value.minute,
                  ),
                );
              }
            },
      validator: (v) => !time && int.tryParse(v ?? '') == null ? '请输入整数' : null,
    ),
  );
  Widget toggle(String name, String label) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: switches[name]!,
    onChanged: saving ? null : (v) => setState(() => switches[name] = v),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('提醒设置')),
    body: Form(
      key: key,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Section(
            '用餐提醒',
            child: Column(
              children: [
                toggle('notifyMeal', '用餐通知'),
                field('mealCount', '每天用餐次数（1–12）'),
                field('mealDuration', '每次用餐时长（分钟，5–180）'),
                field('mealStart', '第一餐开始时间', time: true),
                field('mealEnd', '最后一餐结束时间', time: true),
                const Text('各餐均匀分布在时段内，最后一餐在结束时间前完成。'),
              ],
            ),
          ),
          Section(
            '喝水提醒',
            child: Column(
              children: [
                toggle('notifyWater', '喝水通知'),
                field('waterStart', '喝水开始时间', time: true),
                field('waterEnd', '喝水结束时间', time: true),
                field('waterInterval', '提醒间隔（分钟，5–720）'),
                const Text('开始和结束时间应在同一天；间隔默认30分钟。'),
              ],
            ),
          ),
          for (final category in journeyCategories.entries)
            Section(
              category.value,
              child: Column(
                children: [
                  toggle('notify_${category.key}', '${category.value}通知'),
                  field('lead_${category.key}', '提前几天（0–90）'),
                  field('count_${category.key}', '提前期间每天提醒次数（1–8）'),
                  const Text(
                    '提前期间在09:00–18:00均匀提醒；默认每天09:00一次。执行当天按填写的执行时间提醒。',
                  ),
                ],
              ),
            ),
          ListenableBuilder(
            listenable: widget.reminders,
            builder: (_, _) => Note(widget.reminders.status),
          ),
          const SizedBox(height: 16),
          const Note('手机通知受系统权限和省电设置影响；当前最多安排最近60条，打开应用会续排。浏览器不提供后台系统提醒。'),
          if (error != null) Note(error!, urgent: true),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? '正在保存…' : '保存设置'),
          ),
        ],
      ),
    ),
  );
}
