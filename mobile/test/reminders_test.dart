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
  late ReminderService reminders;
  var enabled = true;
  var initializationFails = false;
  var grantOnRequest = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    enabled = true;
    initializationFails = false;
    grantOnRequest = false;
    calls = [];
    reminders = ReminderService();
    messenger.setMockMethodCallHandler(timezone, (_) async => 'Asia/Shanghai');
    messenger.setMockMethodCallHandler(notifications, (call) async {
      calls.add(call.method);
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
          return false;
        case 'requestNotificationsPermission':
          // Some devices return no result: query the actual system state again.
          if (grantOnRequest) enabled = true;
          return null;
        case 'getNotificationChannels':
          return <Map<String, Object>>[];
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

  test('reminder modes use separate notification channel behavior', () {
    final push = reminders.details(
      'meal',
      mode: reminderModeNotification,
    ).android!;
    final alarm = reminders.details('meal', mode: reminderModeAlarm).android!;
    expect(push.channelId, 'meal_notificationSound');
    expect(push.playSound, isTrue);
    expect(push.enableVibration, isTrue);
    expect(push.audioAttributesUsage, AudioAttributesUsage.notification);
    expect(alarm.channelId, 'meal_alarm');
    expect(alarm.playSound, isTrue);
    expect(alarm.enableVibration, isTrue);
    expect(alarm.audioAttributesUsage, AudioAttributesUsage.alarm);
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
    expect(reminders.warnings, isEmpty);
  });

  test('disabled system notifications are still rejected', () async {
    enabled = false;
    await reminders.initialize();
    await expectLater(reminders.testNotification('meal'), throwsStateError);
    expect(calls, contains('requestNotificationsPermission'));
    expect(calls, isNot(contains('show')));
    expect(reminders.status, contains('通知权限未开启'));
  });

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
