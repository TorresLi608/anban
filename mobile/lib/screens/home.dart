import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/planning.dart';
import '../data/store.dart';
import '../services/reminders.dart';
import '../ui.dart';
import 'care.dart';
import 'forms.dart';
import 'settings.dart';

class HomePage extends StatelessWidget {
  final CareStore store;
  final ReminderService reminders;
  final void Function(int) navigate;

  const HomePage({
    super.key,
    required this.store,
    required this.reminders,
    required this.navigate,
  });

  @override
  Widget build(BuildContext context) {
    final settings = store.data.settings;
    final now = DateTime.now();
    final planned = planReminders(store.data, now);
    final nextUpcoming = planned.isNotEmpty ? planned.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          'TODAY',
          '今日照护',
          '${dayKey(now)} · 把重要的安排与照护日常记在这里',
        ),

        // 1. 置顶模块：今日提醒看板（用户第一眼核心关注）
        Section(
          '今日提醒看板',
          trailing: TextButton.icon(
            onPressed: () => openSettings(context, store, reminders),
            icon: const Icon(Icons.tune_outlined, size: 18),
            label: const Text('提醒设置'),
          ),
          child: Column(
            children: [
              // 1.1 Hero 下次即将到来的提醒高亮卡片
              _HeroReminderCard(
                reminder: nextUpcoming,
                onTapSettings: () => openSettings(context, store, reminders),
              ),
              const SizedBox(height: 14),

              const SizedBox(height: 16),
            ],
          ),
        ),

        // 2. 快捷记录专区（黄金视线区，大触控热区）
        Section(
          '快速记录',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 540;
                  final count = isWide ? 4 : 2;
                  final itemWidth = (constraints.maxWidth - (count - 1) * 10) / count;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _QuickActionTile(
                        width: itemWidth,
                        icon: Icons.monitor_weight_outlined,
                        iconColor: const Color(0xFF2E7D32),
                        badgeBg: const Color(0xFFE8F5E9),
                        title: '记体重',
                        subtitle: '营养状态监测',
                        onTap: () => editRecord(context, store, 'weight'),
                      ),
                      _QuickActionTile(
                        width: itemWidth,
                        icon: Icons.device_thermostat_outlined,
                        iconColor: const Color(0xFFE65100),
                        badgeBg: const Color(0xFFFFF3E0),
                        title: '量体温',
                        subtitle: '发热感染监测',
                        onTap: () => editRecord(context, store, 'temperature'),
                      ),
                      _QuickActionTile(
                        width: itemWidth,
                        icon: Icons.favorite_outline,
                        iconColor: const Color(0xFFC2185B),
                        badgeBg: const Color(0xFFFCE4EC),
                        title: '测心率',
                        subtitle: '脉搏节律记录',
                        onTap: () => editRecord(context, store, 'heartRate'),
                      ),
                      _QuickActionTile(
                        width: itemWidth,
                        icon: Icons.water_drop_outlined,
                        iconColor: const Color(0xFF0288D1),
                        badgeBg: const Color(0xFFE1F5FE),
                        title: '记排泄',
                        subtitle: '尿液便况观察',
                        onTap: () => editRecord(context, store, 'urine'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 540;
                  final count = isWide ? 4 : 2;
                  final itemWidth = (constraints.maxWidth - (count - 1) * 10) / count;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _QuickActionTile(
                        width: itemWidth,
                        icon: Icons.bolt_outlined,
                        iconColor: const Color(0xFFD32F2F),
                        badgeBg: const Color(0xFFFFEBEE),
                        title: '记一次疼痛',
                        subtitle: '部位与程度评估',
                        urgentBorder: true,
                        onTap: () => editRecord(context, store, 'pain'),
                      ),
                      _QuickActionTile(
                        width: itemWidth,
                        icon: Icons.note_alt_outlined,
                        iconColor: pine,
                        badgeBg: const Color(0xFFE8F0E7),
                        title: '记医嘱',
                        subtitle: '医生叮嘱随手记',
                        onTap: () => editRecord(context, store, 'instruction'),
                      ),
                      _QuickActionTile(
                        width: itemWidth,
                        icon: Icons.folder_outlined,
                        iconColor: const Color(0xFF455A64),
                        badgeBg: const Color(0xFFECEFF1),
                        title: '医疗资料',
                        subtitle: '检查报告与病历',
                        onTap: () => navigate(3),
                      ),
                      _QuickActionTile(
                        width: itemWidth,
                        icon: Icons.edit_note,
                        iconColor: const Color(0xFF5D4037),
                        badgeBg: const Color(0xFFEFEBE9),
                        title: '随便记一笔',
                        subtitle: '随手记一笔状态',
                        onTap: () => editRecord(context, store, 'memory'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        // 3. 照护作息与排程节奏
        Section(
          '照护作息节奏',
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 540;
                  final halfWidth = isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: halfWidth,
                        child: _RhythmCard(
                          icon: Icons.restaurant_outlined,
                          title: '一日多餐进食',
                          subtitle:
                              '每天 ${settings['mealCount'] ?? '5'} 次 · 每次 ${settings['mealDuration'] ?? '30'} 分钟',
                          active: settings['notifyMeal'] == 'true',
                          onTap: () => openSettings(context, store, reminders),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final time in mealTimes(settings))
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F6F0),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFDDE8DC),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    '${minuteLabel(time)}–${minuteLabel(time + int.parse(settings['mealDuration'] ?? '30'))}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: ink,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: halfWidth,
                        child: _RhythmCard(
                          icon: Icons.water_drop_outlined,
                          title: '规律饮水补水',
                          subtitle: waterTimes(settings).isEmpty
                              ? '默认每30分钟提醒一次'
                              : '${settings['waterStart']}–${settings['waterEnd']} · 每${settings['waterInterval'] ?? '30'}分钟',
                          active: settings['notifyWater'] == 'true',
                          onTap: () => openSettings(context, store, reminders),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEBF5FE),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  size: 15,
                                  color: Color(0xFF1E88E5),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    settings['notifyWater'] == 'true'
                                        ? '按时补充水分，温水小口慢饮'
                                        : '提醒未开启，可在设置中启用通知',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF1565C0),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: reminders,
                builder: (_, _) => Surface(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.schedule, size: 16, color: pine),
                          const SizedBox(width: 6),
                          const Text(
                            '各项目下次预定时间',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ink,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '系统自动排程',
                            style: TextStyle(
                              fontSize: 11,
                              color: muted.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in reminderNames.entries)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: reminders.nextTimes[entry.key] != null
                                    ? const Color(0xFFF4F8F3)
                                    : const Color(0xFFF8F8F8),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: reminders.nextTimes[entry.key] != null
                                      ? const Color(0xFFD6E4D4)
                                      : const Color(0xFFE5E5E5),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    entry.value,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: reminders.nextTimes[entry.key] != null
                                          ? pine
                                          : muted,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    reminders.nextTimes[entry.key] == null
                                        ? '未安排'
                                        : '${dayKey(reminders.nextTimes[entry.key]!)} ${clockText(reminders.nextTimes[entry.key]!)}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: reminders.nextTimes[entry.key] != null
                                          ? ink
                                          : muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 3. 化疗及维护行程专区
        Section(
          '化疗及维护行程',
          trailing: TextButton.icon(
            onPressed: () => editRecord(context, store, 'journey'),
            icon: const Icon(Icons.add),
            label: const Text('创建行程'),
          ),
          child: JourneyList(store: store),
        ),
      ],
    );
  }
}

/// 置顶主卡片：展示下一次即将到来的提醒焦点
class _HeroReminderCard extends StatelessWidget {
  final PlannedReminder? reminder;
  final VoidCallback onTapSettings;

  const _HeroReminderCard({
    required this.reminder,
    required this.onTapSettings,
  });

  @override
  Widget build(BuildContext context) {
    if (reminder == null) {
      return Surface(
        color: const Color(0xFFF7FAF6),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFE6F4EA),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF2E7D32),
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '今日提醒已全部完成',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: ink,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '当前无待提醒事项 · 好好休息，按时休养',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final item = reminder!;
    final isJourney = !['meal', 'water'].contains(item.channel);
    final hasDue = item.dueAt != null && item.dueAt != item.at;

    IconData heroIcon;
    Color iconColor;
    Color badgeColor;

    if (item.channel == 'meal') {
      heroIcon = Icons.restaurant_outlined;
      iconColor = const Color(0xFFE65100);
      badgeColor = const Color(0xFFFFF0E5);
    } else if (item.channel == 'water') {
      heroIcon = Icons.water_drop_outlined;
      iconColor = const Color(0xFF0288D1);
      badgeColor = const Color(0xFFE1F3FE);
    } else {
      heroIcon = Icons.local_hospital_outlined;
      iconColor = const Color(0xFF2E7D32);
      badgeColor = const Color(0xFFE6F5EB);
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF275F4F), Color(0xFF1E4C3F)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F245B4B),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTapSettings,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部标签与倒计时
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            size: 13,
                            color: Colors.white,
                          ),
                          SizedBox(width: 4),
                          Text(
                            '下一次待办',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      '点击管理设置 ›',
                      style: TextStyle(
                        color: Color(0xFFD6EADB),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 主信息行：图标 + 时间大字 + 名称
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: badgeColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(heroIcon, color: iconColor, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${dayKey(item.at)} ${clockText(item.at)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isJourney ? '响铃提醒' : '建议时间',
                                style: const TextStyle(
                                  color: Color(0xFFBCE0C5),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.title,
                            style: const TextStyle(
                              color: Color(0xFFF1F7F2),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // 如果是化疗/PICC等行程，且有实际执行时间，特别醒目高亮展示！
                if (hasDue) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.event_available,
                          color: Color(0xFF7DE1A2),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                              children: [
                                const TextSpan(
                                  text: '实际执行安排：',
                                  style: TextStyle(
                                    color: Color(0xFFC7EBD0),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      '${dayKey(item.dueAt!)} ${clockText(item.dueAt!)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (item.dueAt!.isAfter(DateTime.now()))
                                  TextSpan(
                                    text:
                                        '（还剩 ${item.dueAt!.difference(DateTime.now()).inDays} 天）',
                                    style: const TextStyle(
                                      color: Color(0xFF86EBB0),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 照护节律卡片（用餐/喝水）
class _RhythmCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool active;
  final Widget child;
  final VoidCallback onTap;

  const _RhythmCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Surface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: pine),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  active ? '已开启' : '未开启',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: active ? const Color(0xFF2E7D32) : muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11.5, color: muted),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// 快速记录操作磁贴
class _QuickActionTile extends StatelessWidget {
  final double width;
  final IconData icon;
  final Color iconColor, badgeBg;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool urgentBorder;

  const _QuickActionTile({
    required this.width,
    required this.icon,
    required this.iconColor,
    required this.badgeBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.urgentBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: urgentBorder
                    ? const Color(0xFFF3C2B8)
                    : const Color(0xFFE5ECE3),
                width: urgentBorder ? 1.4 : 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x061C2E24),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: urgentBorder ? const Color(0xFFB71C1C) : ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
