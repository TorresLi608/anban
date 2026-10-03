import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/planning.dart';
import '../data/store.dart';
import '../services/reminders.dart';
import '../ui.dart';
import 'care.dart';
import 'forms.dart';
import 'settings.dart';

class HomePage extends StatelessWidget {
  final CareStore store;
  final ReminderService reminders;
  final void Function(int) navigate;
  const HomePage({
    super.key,
    required this.store,
    required this.reminders,
    required this.navigate,
  });
  @override
  Widget build(BuildContext context) {
    final settings = store.data.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading('TODAY', '今日照护', '${dayKey(DateTime.now())} · 把重要的安排记在这里'),
        Section(
          '化疗及维护行程',
          trailing: TextButton.icon(
            onPressed: () => editRecord(context, store, 'journey'),
            icon: const Icon(Icons.add),
            label: const Text('创建'),
          ),
          child: JourneyList(store: store),
        ),
        Section(
          '快速记录',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final kind in healthKinds)
                OutlinedButton.icon(
                  onPressed: () => editRecord(context, store, kind),
                  icon: Icon(switch (kind) {
                    'weight' => Icons.monitor_weight_outlined,
                    'stool' || 'urine' => Icons.water_drop_outlined,
                    'pain' => Icons.monitor_heart_outlined,
                    _ => Icons.edit_note,
                  }),
                  label: Text(
                    kind == 'pain' ? '记一次疼痛' : '${kindNames[kind]}记录',
                  ),
                ),
            ],
          ),
        ),
        Section(
          '用餐提醒',
          trailing: TextButton(
            onPressed: () => openSettings(context, store, reminders),
            child: const Text('设置'),
          ),
          child: Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '每天 ${settings['mealCount'] ?? '5'} 次 · 每次 ${settings['mealDuration'] ?? '30'} 分钟 · ${settings['notifyMeal'] == 'true' ? '通知已开启' : '通知未开启'}',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    for (final time in mealTimes(settings))
                      Chip(
                        label: Text(
                          '${minuteLabel(time)}–${minuteLabel(time + int.parse(settings['mealDuration'] ?? '30'))}',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Section(
          '喝水提醒',
          trailing: TextButton(
            onPressed: () => openSettings(context, store, reminders),
            child: const Text('设置'),
          ),
          child: Surface(
            child: Text(
              waterTimes(settings).isEmpty
                  ? '设置开始、结束时间，默认每30分钟提醒一次'
                  : '${settings['waterStart']}–${settings['waterEnd']} · 每${settings['waterInterval'] ?? '30'}分钟\n${settings['notifyWater'] == 'true' ? '通知已开启' : '通知未开启'}',
            ),
          ),
        ),
      ],
    );
  }
}
