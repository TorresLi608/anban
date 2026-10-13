import 'package:anban/data/models.dart';
import 'package:anban/services/reminders.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezone = MethodChannel('flutter_timezone');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;
  late List<MethodCall> methodCalls;
  late Map<int, Map<String, Object?>> pending;
  late ReminderService reminders;
  var enabled = true;
  var exact = false;
  var initializationFails = false;
  var schedulingFails = false;
  var grantOnRequest = false;
  var channels = <Map<String, Object>>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    enabled = true;
    exact = false;
    initializationFails = false;
    schedulingFails = false;
    grantOnRequest = false;
    channels = [];
    calls = [];
    methodCalls = [];
    pending = {};
    reminders = ReminderService();
    messenger.setMockMethodCallHandler(timezone, (_) async => 'Asia/Shanghai');
    messenger.setMockMethodCallHandler(notifications, (call) async {
      calls.add(call.method);
      methodCalls.add(call);
      switch (call.method) {
        case 'initialize':
          if (initializationFails) {
            throw PlatformException(
              code: 'invalid_icon',
              message: 'missing ic_notification',
            );
          }
          return true;
        case 'areNotificationsEnabled':
          return enabled;
        case 'canScheduleExactNotifications':
          return exact;
        case 'requestNotificationsPermission':
          // Some devices return no result: query the actual system state again.
          if (grantOnRequest) enabled = true;
          return null;
        case 'getNotificationChannels':
          return channels;
        case 'pendingNotificationRequests':
          return pending.values.toList();
        case 'zonedSchedule':
          if (schedulingFails) {
            throw PlatformException(
              code: 'schedule_error',
              message: 'alarm denied',
            );
          }
          final args = Map<String, Object?>.from(call.arguments as Map);
          pending[args['id'] as int] = args;
          return null;
        case 'cancel':
          pending.remove((call.arguments as Map)['id']);
          return null;
        default:
          return null;
      }
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(notifications, null);
    messenger.setMockMethodCallHandler(timezone, null);
    reminders.dispose();
  });

  test('all categories and legacy modes share one Android channel', () {
    for (final category in ['meal', 'water', 'picc', 'port', 'chemo']) {
      for (final mode in [reminderModeNotification, reminderModeAlarm]) {
        final details = reminders.details(category, mode: mode).android!;
        expect(details.channelId, reminderChannelId);
        expect(details.playSound, isTrue);
        expect(details.enableVibration, isTrue);
        expect(details.audioAttributesUsage, AudioAttributesUsage.notification);
      }
    }
  });

  test('enabled Android notifications can be tested without requesting alarm access', () async {
    await reminders.initialize();
    await reminders.testNotification('meal');
    expect(calls, contains('show'));
    expect(calls, isNot(contains('requestNotificationsPermission')));
    expect(calls, isNot(contains('requestExactAlarmsPermission')));
    expect(await reminders.requestPermission(), isTrue);
    expect(calls, contains('requestExactAlarmsPermission'));
    await reminders.refresh(
      CareData(settings: {'notifyMeal': 'true'}),
      force: true,
    );
    expect(calls, contains('zonedSchedule'));
    expect(reminders.lastError, isNull);
    expect(reminders.warnings.single, contains('闹钟和提醒'));
    expect(reminders.pendingCount, greaterThan(0));
  });

  test(
    'restored settings request notifications once without requesting alarms',
    () async {
      enabled = false;
      grantOnRequest = true;
      exact = true;
      await reminders.initialize();
      final data = CareData(settings: {'notifyMeal': 'true'});
      await reminders.refresh(data);
      await reminders.refresh(data, force: true);
      expect(
        calls.where((c) => c == 'requestNotificationsPermission'),
        hasLength(1),
      );
      expect(calls, isNot(contains('requestExactAlarmsPermission')));
      expect(reminders.warnings, isEmpty);
    },
  );

  test(
    'delayed test uses a real alarm and survives refresh with reminders off',
    () async {
      exact = true;
      await reminders.initialize();
      final before = DateTime.now();
      final at = await reminders.testScheduledNotification();
      expect(at.difference(before).inSeconds, inInclusiveRange(60, 61));
      final args = pending[900100]!;
      final specifics = args['platformSpecifics'] as Map;
      expect(specifics['channelId'], reminderChannelId);
      expect(
        specifics['scheduleMode'],
        AndroidScheduleMode.exactAllowWhileIdle.name,
      );
      expect(args['matchDateTimeComponents'], isNull);
      expect(calls, isNot(contains('show')));
      await reminders.refresh(CareData(), force: true);
      expect(pending, contains(900100));
      await reminders.refresh(CareData(), clearTest: true);
      expect(pending, isEmpty);
    },
  );

  test('delayed test falls back when exact alarms are unavailable', () async {
    await reminders.initialize();
    await reminders.testScheduledNotification();
    final specifics = pending[900100]!['platformSpecifics'] as Map;
    expect(
      specifics['scheduleMode'],
      AndroidScheduleMode.inexactAllowWhileIdle.name,
    );
    expect(calls, contains('requestExactAlarmsPermission'));
  });

  test('migration only deletes known legacy channels', () async {
    channels = [
      for (final id in [
        'meal_alarm',
        'water_notificationSound',
        'other',
        reminderChannelId,
      ])
        {
          'id': id,
          'name': id,
          'importance': 4,
          'showBadge': true,
          'bypassDnd': false,
          'playSound': true,
          'enableLights': false,
          'enableVibration': true,
          'ledColor': 0,
          'audioAttributesUsage': 5,
        },
    ];
    await reminders.initialize();
    await reminders.refresh(CareData(settings: {'notifyMeal': 'true'}));
    final deleted = methodCalls
        .where((c) => c.method == 'deleteNotificationChannel')
        .map((c) => c.arguments);
    expect(reminders.lastError, isNull);
    expect(deleted, ['meal_alarm', 'water_notificationSound']);
    expect(
      methodCalls.indexWhere((c) => c.method == 'deleteNotificationChannel'),
      greaterThan(methodCalls.indexWhere((c) => c.method == 'zonedSchedule')),
    );
  });

  test(
    'cached refresh repairs a stale next time without rescheduling',
    () async {
      await reminders.initialize();
      final data = CareData(settings: {'notifyMeal': 'true'});
      await reminders.refresh(data);
      final scheduledCount = calls.where((c) => c == 'zonedSchedule').length;
      reminders.nextTimes['meal'] = DateTime.now().subtract(
        const Duration(minutes: 1),
      );
      await reminders.refresh(data);
      expect(reminders.nextTimes['meal']!.isAfter(DateTime.now()), isTrue);
      expect(
        calls.where((c) => c == 'zonedSchedule'),
        hasLength(scheduledCount),
      );
    },
  );

  test(
    'scheduling failure exposes the native cause and can be retried',
    () async {
      await reminders.initialize();
      final data = CareData(settings: {'notifyMeal': 'true'});
      schedulingFails = true;
      await reminders.refresh(data);
      expect(reminders.lastError, contains('alarm denied'));
      schedulingFails = false;
      await reminders.refresh(data);
      expect(reminders.lastError, isNull);
      expect(pending, isNotEmpty);
    },
  );

  test('disabled system notifications are still rejected', () async {
    enabled = false;
    await reminders.initialize();
    await expectLater(reminders.testNotification('meal'), throwsStateError);
    expect(calls, contains('requestNotificationsPermission'));
    expect(calls, isNot(contains('show')));
    expect(reminders.status, contains('通知权限未开启'));
  });

  test(
    'schedule failures preserve existing alarms until replacement succeeds',
    () async {
      await reminders.initialize();
      final data = CareData(settings: {'notifyMeal': 'true'});
      await reminders.refresh(data);
      final previous = Map<int, Map<String, Object?>>.from(pending);
      schedulingFails = true;
      await reminders.refresh(
        data.copy(settings: {'notifyMeal': 'true', 'mealCount': '3'}),
      );
      expect(pending, previous);
      schedulingFails = false;
      await reminders.refresh(
        data.copy(settings: {'notifyMeal': 'true', 'mealCount': '3'}),
      );
      expect(pending, hasLength(3));
    },
  );

  test(
    'remote reminders require login before canceling local schedules',
    () async {
      await reminders.initialize();
      await reminders.refresh(CareData(settings: {'notifyMeal': 'true'}));
      final previous = Map<int, Map<String, Object?>>.from(pending);
      await reminders.refresh(CareData(settings: {'notifyRemote': 'true'}));
      expect(reminders.lastError, contains('请先登录'));
      expect(pending, previous);
    },
  );

  test('system grant is recognized even when request returns null', () async {
    enabled = false;
    grantOnRequest = true;
    await reminders.initialize();
    await reminders.testNotification('meal');
    expect(calls, contains('requestNotificationsPermission'));
    expect(calls, contains('show'));
  });

  test(
    'initialization failure is reported accurately and can be retried',
    () async {
      initializationFails = true;
      await reminders.initialize();
      await expectLater(
        reminders.testNotification('meal'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('初始化失败'),
          ),
        ),
      );
      expect(reminders.initialized, isFalse);
      expect(calls, isNot(contains('requestNotificationsPermission')));
      initializationFails = false;
      await reminders.testNotification('meal');
      expect(reminders.initialized, isTrue);
      expect(calls, contains('show'));
    },
  );
}
