import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models.dart';
import '../data/planning.dart';

class ReminderService extends ChangeNotifier {
  final plugin = FlutterLocalNotificationsPlugin();
  String status = '尚未启用提醒';
  String _fingerprint = '';
  Future<void> _pending = Future.value();
  bool initialized = false;
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
    } catch (_) {
      status = '提醒初始化失败，请检查设备设置';
    }
  }

  Future<bool> requestPermission() async {
    if (!supported || !initialized) {
      return false;
    }
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final allowed = await android.requestNotificationsPermission() ?? false;
      if (!allowed) {
        status = '通知权限未开启，请在系统设置中允许通知';
        notifyListeners();
        return false;
      }
      await android.requestExactAlarmsPermission();
      return true;
    }
    return await plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true, badge: false) ??
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
    if (!force && fingerprint == _fingerprint) {
      return;
    }
    try {
      await plugin.cancelAll();
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
      final pending = planReminders(data, DateTime.now());
      // ponytail: iOS permits 64 pending notifications; schedule earliest 60 and refill on resume.
      final scheduled = pending.take(60).toList();
      for (var i = 0; i < scheduled.length; i++) {
        final p = scheduled[i];
        await plugin.zonedSchedule(
          id: i + 1,
          title: p.title,
          body: p.body,
          scheduledDate: tz.TZDateTime.from(p.at, tz.local),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              p.channel,
              p.title,
              channelDescription: '用餐、喝水与化疗维护行程提醒',
              importance: Importance.high,
              priority: Priority.high,
              visibility: NotificationVisibility.private,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
            ),
          ),
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          payload: p.channel,
        );
      }
      _fingerprint = fingerprint;
      status = scheduled.isEmpty
          ? '暂无待提醒事项，请检查各项通知开关与行程时间'
          : '已排至 ${dayKey(scheduled.last.at)} ${clockText(scheduled.last.at)} · 每次打开自动续排${exact ? '' : ' · 未授权精确闹钟，可能延迟'}';
    } catch (_) {
      status = '提醒安排失败，请检查通知与闹钟权限后重试';
    }
    notifyListeners();
  }
}
