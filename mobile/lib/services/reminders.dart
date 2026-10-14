import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models.dart';
import '../data/planning.dart';
import 'account.dart';
import 'reminder_widget.dart';
import 'remote_reminders.dart';

const reminderModeNotification = 'notification';
const reminderModeAlarm = 'alarm';
const reminderChannelId = 'anban_reminders';
const _backgroundChannel = MethodChannel('app.anban.anban/reminders');

const _legacyReminderChannelIds = {
  'meal_alarm',
  'meal_notificationSound',
  'water_alarm',
  'water_notificationSound',
  'picc_alarm',
  'picc_notificationSound',
  'port_alarm',
  'port_notificationSound',
  'chemo_alarm',
  'chemo_notificationSound',
};

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
  int pendingCount = 0;
  String backgroundStatus = '';
  bool _remoteWasEnabled = false;
  bool _checkedRestoredPermission = false;
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

  Future<void> refresh(
    CareData data, {
    bool force = false,
    bool clearTest = false,
  }) {
    final result = _pending.then(
      (_) => _refresh(data, force: force || clearTest, clearTest: clearTest),
    );
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> _refresh(
    CareData data, {
    required bool force,
    required bool clearTest,
  }) async {
    await updateReminderWidget(data);
    if (!initialized) {
      return;
    }
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      final exact =
          android == null ||
          (await android.canScheduleExactNotifications() ?? false);
      final timezone = (await FlutterTimezone.getLocalTimezone()).identifier;
      if (android != null) await _readBackgroundStatus(exact);
      final fingerprint = jsonEncode([
        dayKey(DateTime.now()),
        Account.scope,
        exact,
        timezone,
        data.settings,
        data.records
            .where((r) => ['journey', 'journeyEntry'].contains(r.kind))
            .map((r) => r.toJson())
            .toList(),
      ]);
      if (!force &&
          fingerprint == _fingerprint &&
          (_refillAt == null || DateTime.now().isBefore(_refillAt!))) {
        nextTimes = {};
        for (final p in planReminders(data, DateTime.now())) {
          nextTimes.putIfAbsent(p.channel, () => p.at);
        }
        notifyListeners();
        return;
      }
      lastError = null;
      warnings.clear();
      tz.setLocalLocation(tz.getLocation(timezone));
      final hasEnabledReminder = data.settings.entries.any(
        (entry) => entry.key.startsWith('notify') && entry.value == 'true',
      );
      final remoteEnabled = data.settings['notifyRemote'] == 'true';
      if (!remoteEnabled && hasEnabledReminder && !_checkedRestoredPermission) {
        _checkedRestoredPermission = true;
        await requestPermission(exactAlarms: false);
      }
      final remoteNeedsSync =
          remoteEnabled ||
          _remoteWasEnabled ||
          data.settings.containsKey('notifyRemote');
      if (remoteEnabled && Account.current == null) {
        throw StateError('请先登录后再同步后端提醒');
      }
      if (Account.current != null && remoteNeedsSync) {
        await Account.reminderRequest(
          'PUT',
          body: remoteReminderPlan(data, DateTime.now(), timezone),
        );
      }
      _remoteWasEnabled = remoteEnabled;
      final scheduled = remoteEnabled
          ? <PlannedReminder>[]
          : scheduleReminders(data, DateTime.now(), android: android != null);
      final previous = await plugin.pendingNotificationRequests();
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
      // Updating the same ID replaces its alarm. Remove obsolete IDs only
      // after the new schedule succeeds so failures leave old alarms intact.
      for (final pending in previous) {
        if (!clearTest && pending.id == 900100) continue;
        if (pending.id >= 1 && pending.id <= scheduled.length) continue;
        await plugin.cancel(id: pending.id);
      }
      pendingCount = (await plugin.pendingNotificationRequests()).length;
      if (android != null) {
        if (!remoteEnabled && hasEnabledReminder && !exact) {
          warnings.add('未允许“闹钟和提醒”，定时通知可能延迟；即时测试不需要此权限');
        }
        if (!remoteEnabled &&
            await android.areNotificationsEnabled() == false) {
          warnings.add('系统通知权限已关闭');
        }
        for (final channel
            in await android.getNotificationChannels() ??
                <AndroidNotificationChannel>[]) {
          if (!remoteEnabled &&
              channel.id == reminderChannelId &&
              channel.importance == Importance.none) {
            warnings.add('安伴提醒通知渠道已关闭，请打开系统通知设置');
          }
          if (_legacyReminderChannelIds.contains(channel.id)) {
            await android.deleteNotificationChannel(channelId: channel.id);
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
      if (remoteEnabled) {
        nextTimes = {};
        for (final p in planReminders(data, DateTime.now())) {
          nextTimes.putIfAbsent(p.channel, () => p.at);
        }
      }
      status = remoteEnabled
          ? '后端 ntfy 排程已同步。请在 ntfy 客户端订阅账号主题。用餐/喝水每天循环；行程同步未来14天，需在覆盖期结束前打开安伴续排。'
          : scheduled.isEmpty
          ? '暂无待提醒事项，请检查各项通知开关与行程时间'
          : '${android != null ? '用餐与喝水按每天定时循环' : '已为各类提醒保留排程名额，打开应用自动续排'}${exact ? '' : ' · 未授权精确闹钟，可能延迟'}\n插件保存的待提醒：$pendingCount 条（不代表已送达）${warnings.isEmpty ? '' : '\n${warnings.join('\n')}'}';
    } catch (e) {
      _fingerprint = '';
      lastError = '提醒安排失败：$e';
      status = lastError!;
    }
    notifyListeners();
  }

  NotificationDetails details(
    String channel, {
    String mode = reminderModeAlarm,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        reminderChannelId,
        '安伴提醒',
        channelDescription: '安伴的用餐、喝水和行程提醒',
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.private,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );
  }

  Future<DateTime> testScheduledNotification({
    String mode = reminderModeAlarm,
  }) {
    final result = _pending.then((_) => _testScheduledNotification(mode: mode));
    _pending = result.then<void>((_) {}).catchError((Object _) {});
    return result;
  }

  Future<DateTime> _testScheduledNotification({required String mode}) async {
    if (!await requestPermission()) {
      throw StateError('请先允许系统通知权限');
    }
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final exact =
        android == null ||
        await android.canScheduleExactNotifications() == true;
    if (android != null) await _readBackgroundStatus(exact);
    final at = DateTime.now().add(const Duration(minutes: 1));
    await plugin.zonedSchedule(
      id: 900100,
      title: '安伴定时提醒测试',
      body: '收到此通知说明系统定时触发正常。',
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: details('meal', mode: mode),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'scheduled-test',
    );
    return at;
  }

  Future<void> _readBackgroundStatus(bool exact) async {
    final lines = ['精确闹钟：${exact ? '已允许' : '未允许，可能延迟'}'];
    try {
      final state = await _backgroundChannel.invokeMapMethod<String, dynamic>(
        'getBackgroundStatus',
      );
      if (state != null) {
        lines.add(
          '${state['manufacturer']} · Android ${state['androidVersion']}',
        );
        lines.add(
          '系统电池优化：${state['ignoringBatteryOptimizations'] == true ? '已豁免' : '未豁免'}',
        );
        lines.add('省电模式：${state['powerSaveMode'] == true ? '开启' : '关闭'}');
        lines.add(
          '系统后台限制：${state['backgroundRestricted'] == true ? '受限' : '未报告限制'}',
        );
        lines.add('厂商自启动/后台策略需在系统设置中另行检查。');
      }
    } on PlatformException {
      lines.add('无法读取系统后台状态');
    } on MissingPluginException {
      lines.add('当前安装包不支持读取系统后台状态');
    }
    backgroundStatus = lines.join('\n');
    notifyListeners();
  }

  Future<void> openBatterySettings() =>
      _backgroundChannel.invokeMethod<void>('openBatterySettings');

  Future<void> openAppSettings() =>
      _backgroundChannel.invokeMethod<void>('openAppSettings');

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
