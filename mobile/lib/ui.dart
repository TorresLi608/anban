import 'package:flutter/material.dart';

import 'data/models.dart';
import 'data/planning.dart';
import 'data/store.dart';

const pine = Color(0xFF245B4B);
const paper = Color(0xFFF6F5F0);
const ink = Color(0xFF25352F);
const muted = Color(0xFF64716B);
const danger = Color(0xFFA63F39);
const line = Color(0xFFDFE5DE);

void toast(BuildContext context, String text) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<void> attempt(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      toast(
        context,
        e.toString().replaceFirst(
          RegExp(r'^(Bad state: |FormatException: |Exception: )'),
          '',
        ),
      );
    }
  }
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  String action = '确认',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
Future<void> deleteRecord(
  BuildContext context,
  CareStore store,
  CareRecord record,
) async {
  if (!await confirm(
    context,
    '删除这条记录？',
    '删除后可通过底部提示撤回。用药计划删除后，已经服用的历史记录仍会保留。',
    action: '删除',
  )) {
    return;
  }
  await store.remove(record);
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('记录已删除'),
      action: SnackBarAction(
        label: '撤回',
        onPressed: () => attempt(context, () => store.put(record)),
      ),
    ),
  );
}

class PageHeading extends StatelessWidget {
  final String eyebrow, title, description;
  final Widget? action;
  const PageHeading(
    this.eyebrow,
    this.title,
    this.description, {
    super.key,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: muted,
            fontSize: 12,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 20,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineLarge),
            ?action,
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(description, style: const TextStyle(color: muted, height: 1.6)),
        ],
      ],
    ),
  );
}

class Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const Section(this.title, {super.key, required this.child, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            ?trailing,
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class Surface extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final BoxBorder? border;
  const Surface({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(20),
    this.border,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: border ?? Border.all(color: const Color(0xFFE5ECE3), width: 1),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A1C2E24),
          blurRadius: 12,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: child,
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, description;
  final Widget? action;
  const EmptyState(
    this.icon,
    this.title,
    this.description, {
    super.key,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 12),
    child: Center(
      child: Column(
        children: [
          Icon(icon, size: 32, color: muted),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 7),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 13, height: 1.6),
          ),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    ),
  );
}

class Note extends StatelessWidget {
  final String text;
  final bool urgent;
  const Note(this.text, {super.key, this.urgent = false});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: urgent ? const Color(0xFFF9EAE5) : const Color(0xFFEAF0E9),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          urgent ? Icons.error_outline_rounded : Icons.info_outline_rounded,
          size: 19,
          color: urgent ? danger : pine,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.65,
              color: urgent ? danger : pine,
            ),
          ),
        ),
      ],
    ),
  );
}

class ResponsiveColumns extends StatelessWidget {
  final Widget main, aside;
  const ResponsiveColumns({super.key, required this.main, required this.aside});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => c.maxWidth >= 790
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: main),
              const SizedBox(width: 30),
              Expanded(flex: 4, child: aside),
            ],
          )
        : Column(children: [main, const SizedBox(height: 6), aside]),
  );
}

class RecordActions extends StatelessWidget {
  final VoidCallback edit, delete;
  const RecordActions({super.key, required this.edit, required this.delete});
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: '编辑或删除',
    onSelected: (value) => value == 'edit' ? edit() : delete(),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'edit', child: Text('编辑记录')),
      PopupMenuItem(value: 'delete', child: Text('删除记录')),
    ],
  );
}

String recordTitle(CareRecord r) => switch (r.kind) {
  'pain' => '疼痛 ${r.text('score')} 分 · ${r.text('location')}',
  'symptom' => '${r.text('name')} · ${r.text('severity')}度',
  'temperature' => '体温 ${r.text('temperature')} ℃',
  'heartRate' => '心率 ${r.text('heartRate')} 次/分',
  'bloodOxygen' => '血氧 ${r.text('bloodOxygen')} %',
  'memory' => r.text('title', '随便记一笔'),
  'vital' =>
    '体温 ${r.text('temperature', '—')} ℃ · 体重 ${r.text('weight', '—')} kg',
  'medication' => r.text('name'),
  'dose' => '${r.text('name')} · ${r.text('dose')}',
  'handover' => '${r.text('caregiver')}的交接',
  'mood' => '${r.text('role')} · ${r.text('mood')}',
  'tumorMarker' => r.text('summary').isNotEmpty
      ? '肿瘤标志物 · ${r.text('summary')}'
      : '肿瘤标志物12项检测',
  'journey' => r.text('category') == 'chemo' && formatChemoStage(r).isNotEmpty
      ? '化疗 · ${formatChemoStage(r)}'
      : (journeyCategories[r.text('category')] ?? r.text('title', '医疗行程')),
  'journeyEntry' => formatChemoStage(r).isNotEmpty
      ? '化疗记录 · ${formatChemoStage(r)}'
      : '行程记录',
  _ => r.text('title', '未命名'),
};
String recordSummary(CareRecord r) => switch (r.kind) {
  'pain' => [
    r.text('type'),
    r.text('trigger'),
    r.text('relief'),
    r.text('note'),
  ].where((s) => s.isNotEmpty).join(' · '),
  'symptom' => [
    r.text('duration'),
    r.text('impact'),
    r.text('note'),
  ].where((s) => s.isNotEmpty).join(' · '),
  'temperature' => r.text('note'),
  'heartRate' => r.text('note'),
  'bloodOxygen' => r.text('note'),
  'memory' => [
    r.text('note'),
    r.text('filename'),
  ].where((s) => s.isNotEmpty).join(' · '),
  'tumorMarker' => [
    r.text('hospital'),
    r.text('summary'),
    r.text('note'),
  ].where((s) => s.isNotEmpty).join(' · '),
  'vital' =>
    '进食：${r.text('food', '未填')} · 睡眠 ${r.text('sleep', '—')} 小时 · 排便：${r.text('bowel', '未填')}',
  'medication' =>
    '${r.text('dose')} · ${r.text('type')} · ${r.text('times')}\n医嘱：${r.text('note', '未填写')}',
  'dose' => '实际 ${clockText(r.at)} · ${r.text('effect', '待观察')}',
  'handover' =>
    '${r.text('condition')}\n用药：${r.text('medication')}\n异常：${r.text('abnormal')}\n明日注意：${r.text('next')}',
  'mood' => r.text('note'),
  'journey' || 'journeyEntry' => [
    if (formatChemoStage(r).isNotEmpty) formatChemoStage(r),
    if (r.text('last').isNotEmpty) '上次：${displayDate(r.text('last'))}',
    if (r.text('next').isNotEmpty) '下次：${displayDate(r.text('next'))}',
    r.text('note'),
  ].where((s) => s.isNotEmpty).join(' · '),
  _ => r.text('note'),
};

IconData kindIcon(String kind) => switch (kind) {
  'weight' => Icons.monitor_weight_outlined,
  'temperature' => Icons.device_thermostat_outlined,
  'heartRate' => Icons.favorite_outline,
  'bloodOxygen' => Icons.air,
  'stool' || 'urine' => Icons.water_drop_outlined,
  'pain' => Icons.bolt_outlined,
  'symptom' => Icons.healing_outlined,
  'instruction' => Icons.note_alt_outlined,
  'journey' || 'journeyEntry' => Icons.local_hospital_outlined,
  'tumorMarker' => Icons.biotech_outlined,
  _ => Icons.edit_note,
};

Color kindColor(String kind) => switch (kind) {
  'weight' => const Color(0xFF2E7D32),
  'temperature' => const Color(0xFFE65100),
  'heartRate' => const Color(0xFFC2185B),
  'bloodOxygen' => const Color(0xFF00838F),
  'stool' || 'urine' => const Color(0xFF0288D1),
  'pain' => const Color(0xFFD32F2F),
  'symptom' => const Color(0xFF7B1FA2),
  'instruction' => pine,
  'journey' || 'journeyEntry' => pine,
  'tumorMarker' => const Color(0xFF00796B),
  _ => const Color(0xFF5D4037),
};

Color kindBadgeBg(String kind) => switch (kind) {
  'weight' => const Color(0xFFE8F5E9),
  'temperature' => const Color(0xFFFFF3E0),
  'heartRate' => const Color(0xFFFCE4EC),
  'bloodOxygen' => const Color(0xFFE0F7FA),
  'stool' || 'urine' => const Color(0xFFE1F5FE),
  'pain' => const Color(0xFFFFEBEE),
  'symptom' => const Color(0xFFF3E5F5),
  'instruction' => const Color(0xFFE8F0E7),
  'journey' || 'journeyEntry' => const Color(0xFFE8F0E7),
  'tumorMarker' => const Color(0xFFE0F2F1),
  _ => const Color(0xFFEFEBE9),
};

class StatusBadge extends StatelessWidget {
  final String label;
  final Color textColor;
  final Color backgroundColor;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    this.textColor = pine,
    this.backgroundColor = const Color(0xFFE8F0E7),
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ],
    ),
  );
}
