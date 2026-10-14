import 'dart:convert';

import 'package:anban/data/models.dart';
import 'package:anban/services/reminder_widget.dart';
import 'package:anban/services/reminders.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('home_widget');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, dynamic> saved;
  late List<MethodCall> calls;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    saved = {};
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final arguments = call.arguments as Map;
      if (call.method == 'saveWidgetData') {
        saved[arguments['id'] as String] = arguments['data'];
      }
      return true;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'card respects category switches and stores only future times and labels',
    () async {
      final before = DateTime.now().millisecondsSinceEpoch;
      await updateReminderWidget(
        CareData(
          settings: {'notifyMeal': 'true', 'notifyWater': 'false'},
          profile: {'name': 'private-patient-name'},
          records: [
            CareRecord(kind: 'memory', fields: {'title': 'private-content'}),
          ],
        ),
      );
      final rows = jsonDecode(saved['reminder_plan'] as String) as List;
      expect(rows, isNotEmpty);
      expect(rows.every((r) => r['label'] == '用餐' && r['at'] > before), isTrue);
      expect(saved['reminder_plan'], isNot(contains('private')));
      final schedule = calls.singleWhere(
        (c) => c.method == 'scheduleWidgetUpdates',
      );
      expect(
        (schedule.arguments as Map)['updateTimes'],
        rows.map((r) => r['at']).toSet().toList(),
      );
      expect((schedule.arguments as Map)['android'], reminderWidgetProvider);
    },
  );

  test('logout clears card data and timers even when notification initialization failed', () async {
    await updateReminderWidget(CareData(settings: {'notifyMeal': 'true'}));
    final reminders = ReminderService();
    await reminders.refresh(CareData(), clearTest: true);
    expect(jsonDecode(saved['reminder_plan'] as String), isEmpty);
    expect((calls.last.arguments as Map)['updateTimes'], isEmpty);
    reminders.dispose();
  });

  test(
    'widget uses the same reminder plan in local and remote modes',
    () async {
      await updateReminderWidget(CareData(settings: {'notifyMeal': 'true'}));
      final local = saved['reminder_plan'];
      await updateReminderWidget(
        CareData(settings: {'notifyMeal': 'true', 'notifyRemote': 'true'}),
      );
      expect(saved['reminder_plan'], local);
    },
  );

  test('widget errors do not disable the reminder service', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'widget_unavailable'),
    );
    final reminders = ReminderService();
    await reminders.refresh(CareData(), clearTest: true);
    expect(reminders.lastError, isNull);
    reminders.dispose();
  });

  test('invalid reminder data does not block application startup', () async {
    await updateReminderWidget(
      CareData(settings: {'notifyMeal': 'true', 'mealStart': 'invalid'}),
    );
    expect(calls, isEmpty);
  });
}
