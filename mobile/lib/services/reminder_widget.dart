import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../data/models.dart';
import '../data/planning.dart';

const reminderWidgetProvider = 'ReminderWidgetProvider';

Future<void> updateReminderWidget(CareData data) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final now = DateTime.now();
    final reminders = planReminders(data, now);
    await HomeWidget.saveWidgetData<String>(
      'reminder_plan',
      jsonEncode([
        for (final reminder in reminders)
          {
            'label': reminderNames[reminder.channel],
            'channel': reminder.channel,
            'at': reminder.at.millisecondsSinceEpoch,
            if (reminder.dueAt != null)
              'due': reminder.dueAt!.millisecondsSinceEpoch,
          },
      ]),
    );
    await HomeWidget.saveWidgetData<String>(
      'reminder_synced',
      '${dayKey(now)} ${clockText(now)}',
    );
    await HomeWidget.updateWidget(androidName: reminderWidgetProvider);
    // Use the plugin's scheduler to advance the card without a running Flutter
    // process. The cached plan covers 14 days; opening Anban renews it.
    await HomeWidget.scheduleWidgetUpdates(
      reminders.map((r) => r.at).toSet().toList(),
      androidName: reminderWidgetProvider,
    );
  } on MissingPluginException {
    // Other platforms and older installations do not have the widget host.
  } on PlatformException catch (e) {
    debugPrint('桌面小组件更新失败：${e.code}');
  } on FormatException {
    // ReminderService reports invalid settings; the optional card must not
    // prevent application startup or notification scheduling.
    debugPrint('桌面小组件暂未更新：提醒设置格式无效');
  }
}
