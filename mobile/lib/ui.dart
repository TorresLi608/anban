import 'package:flutter/material.dart';

import 'data/models.dart';
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
  const Surface({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(24),
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
    ),
    child: child,
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
  'vital' =>
    '体温 ${r.text('temperature', '—')} ℃ · 体重 ${r.text('weight', '—')} kg',
  'medication' => r.text('name'),
  'dose' => '${r.text('name')} · ${r.text('dose')}',
  'handover' => '${r.text('caregiver')}的交接',
  'mood' => '${r.text('role')} · ${r.text('mood')}',
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
  'vital' =>
    '进食：${r.text('food', '未填')} · 睡眠 ${r.text('sleep', '—')} 小时 · 排便：${r.text('bowel', '未填')}',
  'medication' =>
    '${r.text('dose')} · ${r.text('type')} · ${r.text('times')}\n医嘱：${r.text('note', '未填写')}',
  'dose' => '实际 ${clockText(r.at)} · ${r.text('effect', '待观察')}',
  'handover' =>
    '${r.text('condition')}\n用药：${r.text('medication')}\n异常：${r.text('abnormal')}\n明日注意：${r.text('next')}',
  'mood' => r.text('note'),
  _ => r.text('note'),
};
