import 'dart:convert';

import 'package:anban/data/models.dart';
import 'package:anban/data/store.dart';
import 'package:anban/data/vault.dart';
import 'package:anban/screens/settings.dart';
import 'package:anban/services/reminder_widget.dart';
import 'package:anban/services/reminders.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  test('widget persists reminder plan for enabled reminders', () async {
    await updateReminderWidget(CareData(settings: {'notifyMeal': 'true'}));
    expect(saved['reminder_plan'], isNotNull);
    expect(saved['reminder_synced'], isNotNull);
    final list = jsonDecode(saved['reminder_plan'] as String) as List;
    expect(list, isNotEmpty);
    expect(list.any((r) => r['label'] == '用餐'), isTrue);
  });

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

  test('ios updates widget and sets app group', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await updateReminderWidget(
      CareData(settings: {'notifyMeal': 'true'}),
    );
    expect(
      calls.any(
        (c) =>
            c.method == 'setAppGroupId' &&
            (c.arguments as Map)['groupId'] == 'group.app.anban.anban',
      ),
      isTrue,
    );
    expect(
      calls.any(
        (c) =>
            c.method == 'updateWidget' &&
            (c.arguments as Map)['ios'] == 'ReminderWidget',
      ),
      isTrue,
    );
  });

  for (final supported in [true, false]) {
    testWidgets('pin support $supported always gives adding instructions', (
      tester,
    ) async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'isRequestPinWidgetSupported') return supported;
        if (call.method == 'requestPinWidget') return null;
        return true;
      });
      final vault = await LocalVault.memory();
      final store = CareStore(vault, CareData());
      final reminders = ReminderService();
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsPage(store: store, reminders: reminders),
        ),
      );
      final button = find.text('添加桌面提醒卡片');
      await tester.scrollUntilVisible(
        button,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        calls.where((c) => c.method == 'requestPinWidget'),
        hasLength(supported ? 1 : 0),
      );
      expect(
        find.text(
          supported ? '已请求桌面添加；若未弹出确认，请查看下方添加说明' : '桌面不支持直接添加，请按下方说明手动添加',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('如果点击后没有弹窗'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      reminders.dispose();
      store.dispose();
      await vault.close();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
