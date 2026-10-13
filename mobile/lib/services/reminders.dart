import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models.dart';
import '../data/planning.dart';

const reminderModeNotification = 'notification';
const reminderModeAlarm = 'alarm';

String normalizedReminderMode(String? value) =>
    value == reminderModeNotification
    ? reminderModeNotification
    : reminderModeAlarm;

class ReminderService extends ChangeNotifier {
  final plugin = FlutterLocalNotificationsPlugin();
  String status = '尚未启用提醒';
  String _fingerprint = '';
  Future<void> _pending = Future.value();
  bool initialized = false;
  String? lastError;
  DateTime? _refillAt;
  Map<String, DateTime> nextTimes = {};
  final List<String> warnings = [];
  bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  Future<void> initialize() async {
    if (!supported) {
      status = '浏览器预览不提供后台提醒，请使用手机端';
      return;
    }
    try {
      lastError = null;
      tzdata.initializeTimeZones();
      tz.setLocalLocation(
        tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier),
      );
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      initialized = true;
      status = '提醒服务已就绪';
    } catch (e) {
      initialized = false;
      lastError = '提醒初始化失败：$e';
      status = lastError!;
    }
    notifyListeners();
  }

  Future<bool> requestPermission({bool exactAlarms = true}) async {
    if (!supported) throw StateError(status);
    if (!initialized) await initialize();
    if (!initialized) throw StateError(lastError ?? '提醒服务未初始化');
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      var allowed = await android.areNotificationsEnabled();
      if (allowed != true) {
        final requested = await android.requestNotificationsPermission();
        allowed = await android.areNotificationsEnabled() ?? requested;
      }
      if (allowed != true) {
        status = '通知权限未开启，请在系统设置中允许通知';
        notifyListeners();
        return false;
      }
      if (exactAlarms &&
          await android.canScheduleExactNotifications() != true) {
        await android.requestExactAlarmsPermission();
      }
      return true;
    }
    final ios = plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if ((await ios?.checkPermissions())?.isEnabled == true) return true;
    return await ios?.requestPermissions(
          alert: true,
          sound: true,
          badge: false,
        ) ??
        false;
  }

  Future<void> refresh(CareData data, {bool force = false}) {
    final result = _pending.then((_) => _refresh(data, force: force));
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> _refresh(CareData data, {required bool force}) async {
    if (!initialized) {
      return;
    }
    final fingerprint = jsonEncode([
      dayKey(DateTime.now()),
      data.settings,
      data.records
          .where((r) => ['journey', 'journeyEntry'].contains(r.kind))
          .map((r) => r.toJson())
          .toList(),
    ]);
    if (!force &&
        fingerprint == _fingerprint &&
        (_refillAt == null || DateTime.now().isBefore(_refillAt!))) {
      return;
    }
    try {
      lastError = null;
      warnings.clear();
      await plugin.cancelAllPendingNotifications();
      tz.setLocalLocation(
        tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier),
      );
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final exact =
          android == null ||
          (await android.canScheduleExactNotifications() ?? false);
      final scheduled = scheduleReminders(
        data,
        DateTime.now(),
        android: android != null,
      );
      final mode = normalizedReminderMode(data.settings['reminderMode']);
      nextTimes = {};
      final lastTimes = <String, DateTime>{};
      for (var i = 0; i < scheduled.length; i++) {
        final p = scheduled[i];
        await plugin.zonedSchedule(
          id: i + 1,
          title: p.title,
          body: p.body,
          scheduledDate: tz.TZDateTime.from(p.at, tz.local),
          notificationDetails: details(p.channel, mode: mode),
          matchDateTimeComponents: p.daily ? DateTimeComponents.time : null,
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          payload: p.channel,
        );
        for (final category in p.categories) {
          nextTimes.putIfAbsent(category, () => p.at);
          lastTimes[category] = p.at;
        }
      }
      if (android != null) {
        if (await android.areNotificationsEnabled() == false) {
          warnings.add('系统通知权限已关闭');
        }
        for (final channel
            in await android.getNotificationChannels() ??
                <AndroidNotificationChannel>[]) {
          final category = channel.id.replaceFirst(
            RegExp(r'_(notificationSound|alarm)$'),
            '',
          );
          if (nextTimes.containsKey(category) &&
              channel.importance == Importance.none) {
            warnings.add('${reminderNames[category]}通知渠道已关闭，请打开系统通知设置');
          }
        }
      }
      _refillAt = android == null && lastTimes.isNotEmpty
          ? (lastTimes.values.toList()..sort()).first.subtract(
              const Duration(minutes: 10),
            )
          : null;
      if (_refillAt != null &&
          _refillAt!.isBefore(DateTime.now().add(const Duration(minutes: 5)))) {
        _refillAt = DateTime.now().add(const Duration(minutes: 5));
      }
      _fingerprint = fingerprint;
      status = scheduled.isEmpty
          ? '暂无待提醒事项，请检查各项通知开关与行程时间'
          : '${android != null ? '用餐与喝水按每天定时循环' : '已为各类提醒保留排程名额，打开应用自动续排'}${exact ? '' : ' · 未授权精确闹钟，可能延迟'}\n${nextTimes.entries.map((e) => '${reminderNames[e.key]}下次：${dayKey(e.value)} ${clockText(e.value)}').join('\n')}${warnings.isEmpty ? '' : '\n${warnings.join('\n')}'}';
    } catch (_) {
      _fingerprint = '';
      lastError = '提醒安排失败，请检查通知与闹钟权限后重试';
      status = lastError!;
    }
    notifyListeners();
  }

  NotificationDetails details(
    String channel, {
    String mode = reminderModeAlarm,
  }) {
    final alarm = normalizedReminderMode(mode) == reminderModeAlarm;
    final channelId =
        '${channel}_${alarm ? reminderModeAlarm : 'notificationSound'}';
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        '${reminderNames[channel] ?? channel}${alarm ? '闹钟' : '通知'}',
        channelDescription: alarm ? '安伴照护闹钟提醒' : '安伴照护通知提醒',
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.private,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: alarm
            ? AudioAttributesUsage.alarm
            : AudioAttributesUsage.notification,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );
  }

  Future<void> testNotification(
    String channel, {
    String mode = reminderModeAlarm,
  }) async {
    if (!await requestPermission(exactAlarms: false)) {
      throw StateError('请先允许系统通知权限');
    }
    await plugin.show(
      id: 900001 + reminderNames.keys.toList().indexOf(channel),
      title: '${reminderNames[channel]}提醒测试',
      body: '这是一条测试通知，用于确认声音和提示是否正常。',
      notificationDetails: details(channel, mode: mode),
    );
  }

  Future<void> openSystemSettings() async {
    await plugin.openAppNotificationSettings();
  }
}
