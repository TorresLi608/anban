import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../data/models.dart';
import '../data/planning.dart';
import '../data/store.dart';
import '../services/reminders.dart';
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
  late bool keepAlive;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final s = widget.store.data.settings;
    reminderMode = normalizedReminderMode(s['reminderMode']);
    keepAlive = s['keepAlive'] != 'false';
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
        'keepAlive': '$keepAlive',
      };
      values.remove('notifyRemote');
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
  Widget _buildOverviewHeader() {
    final activeCount = switches.values.where((v) => v).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [pine.withValues(alpha: 0.12), pine.withValues(alpha: 0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pine.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: pine.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications_active_rounded, color: pine, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '照护提醒中枢',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: pine,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '已启用 $activeCount 项照护提醒 · 本地闹钟强提醒就绪',
                  style: const TextStyle(fontSize: 12.5, color: muted),
                ),
              ],
            ),
          ),
          if (widget.reminders.supported)
            TextButton.icon(
              onPressed: () => attempt(context, widget.reminders.openSystemSettings),
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('系统设置', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCardHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: pine.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: pine, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: pine,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11.5, color: muted),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildTimeField(String name, String label, {IconData icon = Icons.access_time}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: saving
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
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 20, color: pine),
            suffixIcon: const Icon(Icons.arrow_drop_down, color: muted),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          child: Text(
            inputs[name]!.text.isEmpty ? '点击设置时间' : inputs[name]!.text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: inputs[name]!.text.isEmpty ? muted : pine,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('提醒设置'),
      actions: [
        if (saving)
          const Center(
            child: Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          TextButton(
            onPressed: save,
            child: const Text('保存', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
      ],
    ),
    body: Form(
      key: key,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          _buildOverviewHeader(),

          // 1. 日常饮食与饮水作息
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardHeader(
                  icon: Icons.restaurant_rounded,
                  title: '用餐作息提醒',
                  subtitle: '少食多餐均匀规划，提醒温和按时进食',
                  trailing: widget.reminders.supported ? testButton('meal') : null,
                ),
                toggle('notifyMeal', '开启用餐通知'),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(child: field('mealCount', '每日餐数 (1-12)')),
                    const SizedBox(width: 12),
                    Expanded(child: field('mealDuration', '每餐时长 (分钟)')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _buildTimeField('mealStart', '首餐开始时间')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTimeField('mealEnd', '末餐结束时间')),
                  ],
                ),
                const Note('各餐将在起止时段内均匀分布提醒，保障能量持续供给。'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. 补水饮水节奏
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardHeader(
                  icon: Icons.water_drop_rounded,
                  title: '规律饮水提醒',
                  subtitle: '少量多次补充水分，预防化疗副反应',
                  trailing: widget.reminders.supported ? testButton('water') : null,
                ),
                toggle('notifyWater', '开启喝水通知'),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(child: _buildTimeField('waterStart', '喝水开始时间', icon: Icons.wb_sunny_outlined)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTimeField('waterEnd', '喝水结束时间', icon: Icons.nightlight_outlined)),
                  ],
                ),
                field('waterInterval', '提醒间隔（分钟，默认 30）'),
                const Note('建议化疗期间保持足量饮水，促进代谢排泄。'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. 医疗行程提前提醒 (化疗/PICC/输液港)
          for (final category in journeyCategories.entries) ...[
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCardHeader(
                    icon: category.key == 'chemo'
                        ? Icons.medication_liquid_rounded
                        : Icons.healing_rounded,
                    title: '${category.value}提醒',
                    subtitle: '执行当天按时提醒，支持提前数日连续关怀',
                    trailing: widget.reminders.supported
                        ? testButton(category.key)
                        : null,
                  ),
                  toggle('notify_${category.key}', '开启${category.value}通知'),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(child: field('lead_${category.key}', '提前天数 (0-90)')),
                      const SizedBox(width: 12),
                      Expanded(child: field('count_${category.key}', '每天提醒频次 (1-8)')),
                    ],
                  ),
                  const Note(
                    '提前期间在 09:00–18:00 均匀提醒；执行当天按填写的确切执行时间准时提醒。',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // 4. 提醒方式与声音
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardHeader(
                  icon: Icons.volume_up_rounded,
                  title: '提醒方式与声音',
                  subtitle: '定制提醒铃声与振动强弱',
                ),
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                  const Note(
                    '所有提醒使用独立的“安伴提醒”高优先级通知渠道，声音与振动可直接在系统通知设置中调整。如需锁屏响铃，请授予“闹钟和提醒”权限。',
                  )
                else
                  RadioGroup<String>(
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
                          title: const Text('仅推送通知'),
                          subtitle: const Text('使用普通温和提示音，不占用系统闹钟通道'),
                          value: reminderModeNotification,
                          enabled: !saving,
                        ),
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('强提醒（推送 + 闹钟）'),
                          subtitle: const Text('显示通知，并以闹钟铃声和振动持续提醒'),
                          value: reminderModeAlarm,
                          enabled: !saving,
                        ),
                      ],
                    ),
                  ),
                if (widget.reminders.supported) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: saving
                              ? null
                              : () => attempt(context, () async {
                                  final at = await widget.reminders
                                      .testScheduledNotification(mode: reminderMode);
                                  if (context.mounted) {
                                    toast(
                                      context,
                                      '定时测试已安排在 ${clockText(at)}。请返回桌面或锁屏等待。',
                                    );
                                  }
                                }),
                          icon: const Icon(Icons.timer_outlined, size: 18),
                          label: const Text('1分钟后测试提醒'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 5. 桌面提醒小组件 (Android)
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCardHeader(
                    icon: Icons.widgets_rounded,
                    title: '桌面提醒卡片',
                    subtitle: '无需打开应用，在手机桌面随时看下一项提醒',
                  ),
                  const Note(
                    '显示当前账号用餐、喝水和行程的下一次提醒时间，沿用各项通知开关。保存设置或打开安伴后同步未来14天，时间到后自动换到下一项；系统省电策略可能延迟卡片刷新。',
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: saving
                          ? null
                          : () => attempt(context, () async {
                              await updateReminderWidget(widget.store.data);
                              if (await HomeWidget.isRequestPinWidgetSupported() ==
                                  true) {
                                await HomeWidget.requestPinWidget(
                                  androidName: reminderWidgetProvider,
                                );
                                if (context.mounted) {
                                  toast(context, '已请求桌面添加；若未弹出确认，请查看下方添加说明');
                                }
                              } else if (context.mounted) {
                                toast(context, '桌面不支持直接添加，请按下方说明手动添加');
                              }
                            }),
                      icon: const Icon(Icons.add_to_home_screen_rounded),
                      label: const Text('添加桌面提醒卡片'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Note(
                    '如果点击后没有弹窗：长按桌面空白处 → 添加小部件 → 全部应用／Android小组件／支持小部件的应用 → 安伴提醒。小米桌面可能将Android小组件放在列表底部；若直接添加被拦截，请到系统设置 → 应用设置 → 安伴 → 权限管理／其他权限，检查“桌面快捷方式”（若有）。更新安装后先打开安伴，再重新进入桌面小组件列表；仍未出现可重启手机刷新桌面列表。',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // 6. 各类下一次通知排程
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardHeader(
                  icon: Icons.event_available_rounded,
                  title: '各类下一次通知排程',
                  subtitle: '系统预计算出的各类别最近一次触发时刻',
                ),
                nextReminderTimes(),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 7. 系统状态与后台保活诊断
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardHeader(
                  icon: Icons.security_update_good_rounded,
                  title: '后台保活与系统诊断',
                  subtitle: '避免手机系统杀进程导致漏提醒',
                ),
                ListenableBuilder(
                  listenable: widget.reminders,
                  builder: (_, _) => Note(widget.reminders.status),
                ),
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('常驻后台守护（前台服务）'),
                    subtitle: const Text(
                      '在系统状态栏保持守护运行，提权免疫常规杀后台，保障长时间熄屏与极端省电模式下提醒准时触发。',
                    ),
                    value: keepAlive,
                    onChanged: saving
                        ? null
                        : (val) => setState(() => keepAlive = val),
                  ),
                  const SizedBox(height: 10),
                  ListenableBuilder(
                    listenable: widget.reminders,
                    builder: (_, _) => Note(widget.reminders.backgroundStatus),
                  ),
                  const SizedBox(height: 10),
                  const Note(
                    '小米、华为、OPPO等手机若回桌面/锁屏后漏提醒，请在系统设置中开启“自启动”，并将省电策略设为“无限制”。系统设置中的“强制停止”会清除 Android 闹钟。',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => attempt(context, widget.reminders.openAppSettings),
                          child: const Text('应用后台设置', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => attempt(context, widget.reminders.openBatterySettings),
                          child: const Text('电池优化设置', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          if (error != null) ...[
            const SizedBox(height: 16),
            Note(error!, urgent: true),
          ],
        ],
      ),
    ),
    bottomNavigationBar: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: FilledButton.icon(
          onPressed: saving ? null : save,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_circle_outline_rounded),
          label: Text(
            saving ? '正在保存设置…' : '保存全部提醒设置',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    ),
  );
}
