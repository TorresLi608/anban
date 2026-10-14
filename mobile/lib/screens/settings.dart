import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../data/models.dart';
import '../data/planning.dart';
import '../data/store.dart';
import '../services/reminders.dart';
import '../services/account.dart';
import '../services/reminder_widget.dart';
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
  late String reminderMode;
  bool remoteEnabled = false;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final s = widget.store.data.settings;
    reminderMode = normalizedReminderMode(s['reminderMode']);
    remoteEnabled = s['notifyRemote'] == 'true';
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
        'reminderMode': reminderMode,
        'notifyRemote': '$remoteEnabled',
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
          !remoteEnabled &&
          widget.reminders.supported &&
          !await widget.reminders.requestPermission()) {
        throw StateError('请先允许系统通知权限');
      }
      await widget.store.settings(values);
      await widget.reminders.refresh(widget.store.data, force: true);
      if (widget.reminders.lastError != null) {
        throw StateError('配置已保存，但${widget.reminders.lastError}');
      }
      if (widget.reminders.warnings.isNotEmpty) {
        throw StateError('配置已保存；${widget.reminders.warnings.join('；')}');
      }
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

  Widget testButton(String channel) => TextButton(
    onPressed: saving
        ? null
        : () => attempt(
            context,
            () =>
                widget.reminders.testNotification(channel, mode: reminderMode),
          ),
    child: const Text('测试通知'),
  );

  Widget nextReminderTimes() => ListenableBuilder(
    listenable: widget.reminders,
    builder: (_, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in reminderNames.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Builder(
              builder: (_) {
                final time = widget.reminders.nextTimes[entry.key];
                return Text(
                  time == null
                      ? '${entry.value}：暂无排程（请开启通知并填写有效时间）'
                      : '${entry.value}：${dayKey(time)} ${clockText(time)}',
                );
              },
            ),
          ),
      ],
    ),
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
            '后端推送（ntfy）',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('使用 ntfy 后端提醒'),
                  subtitle: const Text(
                    '开启后发送提醒时间和时区到后端，由 ntfy 客户端显示通知；本地日常提醒关闭以免重复。照护内容不发送给 ntfy。',
                  ),
                  value: remoteEnabled,
                  onChanged: saving
                      ? null
                      : (value) => setState(() => remoteEnabled = value),
                ),
                const Note(
                  '需另行安装 ntfy 客户端，添加自建服务器和只读账号，再订阅本账号主题。ntfy 客户端需允许后台运行。设置保存后生效。',
                ),
                TextButton(
                  onPressed: () => attempt(context, () async {
                    final info = await Account.reminderRequest('GET');
                    if (!context.mounted) return;
                    await showDialog<void>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('ntfy 订阅信息'),
                        content: SingleChildScrollView(
                          child: SelectableText(
                            '服务器：${info['server']}\n主题：${info['topic']}\n后端待提醒：${info['pending']}\n最近提交 ntfy：${info['lastSuccess'] ?? '暂无'}\n发送错误：${info['lastError'] == '' ? '暂无' : info['lastError']}\n\n提交成功不代表手机收到。请使用部署时分配的只读账号订阅。',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    );
                  }),
                  child: const Text('查看订阅信息与后端状态'),
                ),
                OutlinedButton(
                  onPressed: () => attempt(context, () async {
                    final info = await Account.reminderRequest(
                      'POST',
                      test: true,
                    );
                    if (context.mounted) {
                      final at = DateTime.parse(info['at'] as String).toLocal();
                      toast(
                        context,
                        '后端测试已安排：${dayKey(at)} ${clockText(at)}。请返回桌面/锁屏，等待 ntfy 通知。',
                      );
                    }
                  }),
                  child: const Text('1 分钟后发送后端测试通知'),
                ),
              ],
            ),
          ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            const Section(
              '提醒方式',
              child: Note(
                '所有提醒使用同一个“安伴提醒”通知渠道，声音和震动统一在系统通知设置中调整。准时提醒另外需要系统的“闹钟和提醒”权限。',
              ),
            )
          else
            Section(
              '提醒方式',
              child: RadioGroup<String>(
                groupValue: reminderMode,
                onChanged: saving
                    ? (_) {}
                    : (value) {
                        if (value != null) setState(() => reminderMode = value);
                      },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('仅推送'),
                      subtitle: const Text('使用普通通知声音和震动，不占用闹钟音频'),
                      value: reminderModeNotification,
                      enabled: !saving,
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('推送 + 闹钟'),
                      subtitle: const Text('显示通知，并使用闹钟声音和震动提醒'),
                      value: reminderModeAlarm,
                      enabled: !saving,
                    ),
                  ],
                ),
              ),
            ),
          const Note(
            'Android 只需允许一次“安伴”通知权限。下面的开关分别控制用餐、喝水和各项护理提醒；关闭某项不会影响其他提醒。',
          ),
          Section(
            '用餐提醒',
            trailing: widget.reminders.supported ? testButton('meal') : null,
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
            trailing: widget.reminders.supported ? testButton('water') : null,
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
              trailing: widget.reminders.supported
                  ? testButton(category.key)
                  : null,
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
          Section('各类下一次通知', child: nextReminderTimes()),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            Section(
              '桌面提醒卡片',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Note(
                    '显示当前账号用餐、喝水和行程的下一次提醒时间，沿用各项通知开关。保存设置或打开安伴后同步未来14天，时间到后自动换到下一项；系统省电策略可能延迟卡片刷新。',
                  ),
                  OutlinedButton.icon(
                    onPressed: saving
                        ? null
                        : () => attempt(context, () async {
                            await updateReminderWidget(widget.store.data);
                            if (await HomeWidget.isRequestPinWidgetSupported() ==
                                true) {
                              await HomeWidget.requestPinWidget(
                                androidName: reminderWidgetProvider,
                              );
                            } else if (context.mounted) {
                              toast(context, '请长按桌面 → 小组件 → 安伴提醒，添加到桌面');
                            }
                          }),
                    icon: const Icon(Icons.widgets_outlined),
                    label: const Text('添加桌面提醒卡片'),
                  ),
                ],
              ),
            ),
          ListenableBuilder(
            listenable: widget.reminders,
            builder: (_, _) => Note(widget.reminders.status),
          ),
          const SizedBox(height: 16),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
            ListenableBuilder(
              listenable: widget.reminders,
              builder: (_, _) => Note(widget.reminders.backgroundStatus),
            ),
            const Note(
              '小米手机若回桌面/锁屏后漏提醒，请在安伴的系统应用设置中开启后台自启动，并将省电策略设为“无限制”。通知权限与这些后台设置相互独立；系统状态未报告限制也不代表厂商没有限制。',
            ),
            TextButton(
              onPressed: () =>
                  attempt(context, widget.reminders.openAppSettings),
              child: const Text('打开应用后台设置'),
            ),
            TextButton(
              onPressed: () =>
                  attempt(context, widget.reminders.openBatterySettings),
              child: const Text('打开电池优化设置'),
            ),
          ],
          const Note(
            '安卓用餐和喝水提醒每天循环；同一时刻会合并成一条提示。iOS 保留最多60条待提醒，按类型分配并在打开应用时续排。通知仍受系统权限、省电设置和厂商后台限制影响；系统设置中的“强制停止”会清除 Android 闹钟，无法由应用恢复。',
          ),
          if (widget.reminders.supported)
            OutlinedButton.icon(
              onPressed: saving
                  ? null
                  : () => attempt(context, () async {
                      final at = await widget.reminders
                          .testScheduledNotification(mode: reminderMode);
                      if (context.mounted) {
                        toast(
                          context,
                          '定时测试已安排在 ${clockText(at)}。请返回桌面或锁屏等待；未允许精确闹钟时可能延迟。',
                        );
                      }
                    }),
              icon: const Icon(Icons.timer_outlined),
              label: const Text('1 分钟后测试提醒'),
            ),
          if (widget.reminders.supported)
            TextButton(
              onPressed: () =>
                  attempt(context, widget.reminders.openSystemSettings),
              child: const Text('打开系统通知设置'),
            ),
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
