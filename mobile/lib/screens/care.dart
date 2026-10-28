import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/planning.dart';
import '../data/store.dart';
import '../ui.dart';
import 'forms.dart';

class CarePage extends StatelessWidget {
  final CareStore store;
  const CarePage({super.key, required this.store});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PageHeading(
        'CARE JOURNEYS',
        '化疗及维护行程',
        'PICC/输液港维护周期与化疗疗程安排，提前提醒，按时执行。',
        action: FilledButton.icon(
          onPressed: () => editRecord(context, store, 'journey'),
          icon: const Icon(Icons.add),
          label: const Text('创建新行程'),
        ),
      ),

      // 医疗护理温馨提示
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F7F1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDCE8DC), width: 0.8),
        ),
        child: const Row(
          children: [
            Icon(Icons.health_and_safety_outlined, color: pine, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '提示：PICC 导管建议每 7 天维护一次；输液港治疗间歇期建议每 4 周冲管一次。',
                style: TextStyle(fontSize: 12, color: pine, height: 1.4),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),

      JourneyList(store: store),
    ],
  );
}

class JourneyList extends StatelessWidget {
  final CareStore store;
  const JourneyList({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final journeys = store.records('journey')
      ..sort(
        (a, b) =>
            DateTime.parse(
              latestJourney(store.data.records, a).text('next'),
            ).compareTo(
              DateTime.parse(latestJourney(store.data.records, b).text('next')),
            ),
      );

    if (journeys.isEmpty) {
      return EmptyState(
        Icons.event_note_outlined,
        '暂无化疗及维护行程',
        '点击下方按钮添加 PICC 护理、输液港维护或化疗周期安排',
        action: FilledButton.icon(
          onPressed: () => editRecord(context, store, 'journey'),
          icon: const Icon(Icons.add),
          label: const Text('创建第一个行程'),
        ),
      );
    }

    final now = DateTime.now();

    return Column(
      children: [
        for (final journey in journeys)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Builder(
              builder: (context) {
                final latest = latestJourney(store.data.records, journey);
                final category = journey.text('category');
                final categoryName =
                    journeyCategories[category] ?? '医疗行程';
                final chemoStage =
                    category == 'chemo' ? formatChemoStage(latest) : '';
                final nextDate = DateTime.tryParse(latest.text('next'));
                final daysLeft = nextDate
                    ?.difference(DateTime(now.year, now.month, now.day))
                    .inDays;

                // 倒计时状态标签
                Widget statusWidget;
                if (daysLeft == null) {
                  statusWidget = const SizedBox.shrink();
                } else if (daysLeft < 0) {
                  statusWidget = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '已逾期 ${-daysLeft} 天！',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFC62828),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                } else if (daysLeft == 0) {
                  statusWidget = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '今日执行',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                } else if (daysLeft == 1) {
                  statusWidget = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '明天执行',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFFE65100),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                } else {
                  statusWidget = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0E7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '还剩 $daysLeft 天',
                      style: const TextStyle(
                        fontSize: 11,
                        color: pine,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }

                return Surface(
                  padding: const EdgeInsets.all(18),
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            JourneyDetail(store: store, journeyId: journey.id),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 顶栏：分类名称与倒计时徽章
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE8F0E7),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.local_hospital_outlined,
                                color: pine,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    categoryName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: ink,
                                    ),
                                  ),
                                  if (chemoStage.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      chemoStage,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: pine,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            statusWidget,
                          ],
                        ),
                        const SizedBox(height: 14),

                        // 上次与下次执行对比卡片
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAF8),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFE8EDE7),
                              width: 0.8,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.history,
                                    size: 15,
                                    color: muted,
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    '上次执行：',
                                    style: TextStyle(fontSize: 12.5, color: muted),
                                  ),
                                  Text(
                                    displayDate(latest.text('last')),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: ink,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.event_available,
                                    size: 15,
                                    color: pine,
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    '下次执行：',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: pine,
                                    ),
                                  ),
                                  Text(
                                    displayDate(latest.text('next')),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: pine,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        if (latest.text('note').isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            latest.text('note'),
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: ink,
                              height: 1.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 12),

                        // 底栏引导
                        Row(
                          children: [
                            const Text(
                              '查看历史与新增维护记录',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: pine,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 12,
                              color: pine,
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: '快捷记一次',
                              icon: const Icon(
                                Icons.add_circle_outline,
                                color: pine,
                                size: 22,
                              ),
                              onPressed: () => editRecord(
                                context,
                                store,
                                'journeyEntry',
                                initial: {'journeyId': journey.id},
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class JourneyDetail extends StatelessWidget {
  final CareStore store;
  final String journeyId;
  const JourneyDetail({
    super.key,
    required this.store,
    required this.journeyId,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (_, _) {
      final journey = store.data.records
          .where((r) => r.id == journeyId)
          .firstOrNull;
      if (journey == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('行程')),
          body: const Center(child: Text('行程不存在，请返回刷新')),
        );
      }

      final category = journey.text('category');
      final categoryName = journeyCategories[category] ?? '行程详情';
      final entries = [
        journey,
        ...store
            .records('journeyEntry')
            .where((r) => r.text('journeyId') == journeyId),
      ]..sort(
          (a, b) => DateTime.parse(b.text('last'))
              .compareTo(DateTime.parse(a.text('last'))),
        );

      final latest = entries.first;
      final now = DateTime.now();
      final nextDate = DateTime.tryParse(latest.text('next'));
      final daysLeft = nextDate
          ?.difference(DateTime(now.year, now.month, now.day))
          .inDays;
      final chemoStage = category == 'chemo' ? formatChemoStage(latest) : '';

      return Scaffold(
        appBar: AppBar(
          title: Text(categoryName),
          actions: [
            IconButton(
              tooltip: '编辑行程基础信息',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => editRecord(
                context,
                store,
                journey.kind,
                record: journey,
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // 顶部当前状态高亮卡
            Surface(
              color: const Color(0xFFF7FAF6),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.alarm_on, color: pine, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        '当前安排状态',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: ink,
                        ),
                      ),
                      if (chemoStage.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F0E7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            chemoStage,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: pine,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (daysLeft != null)
                        StatusBadge(
                          label: daysLeft < 0
                              ? '已超期 ${-daysLeft} 天'
                              : daysLeft == 0
                              ? '今日执行'
                              : '还剩 $daysLeft 天',
                          textColor: daysLeft <= 1
                              ? const Color(0xFFC62828)
                              : pine,
                          backgroundColor: daysLeft <= 1
                              ? const Color(0xFFFFEBEE)
                              : const Color(0xFFE8F0E7),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '最近一次执行',
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              displayDate(latest.text('last')),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '下一次执行',
                              style: TextStyle(fontSize: 11, color: pine),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              displayDate(latest.text('next')),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: pine,
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
            const SizedBox(height: 18),

            FilledButton.icon(
              onPressed: () => editRecord(
                context,
                store,
                'journeyEntry',
                initial: {'journeyId': journeyId},
              ),
              icon: const Icon(Icons.add),
              label: const Text('新增本次执行记录'),
            ),
            const SizedBox(height: 22),

            Row(
              children: [
                const Icon(Icons.history_edu_outlined, size: 18, color: pine),
                const SizedBox(width: 6),
                Text(
                  '执行历史时间轴 (${entries.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 历史时间轴卡片
            for (var i = 0; i < entries.length; i++)
              _TimelineEntryCard(
                entry: entries[i],
                isLatest: i == 0,
                onTap: () => editRecord(
                  context,
                  store,
                  entries[i].kind,
                  record: entries[i],
                ),
                onDelete: entries[i].kind == 'journeyEntry'
                    ? () => attempt(
                          context,
                          () => deleteRecord(context, store, entries[i]),
                        )
                    : null,
              ),
          ],
        ),
      );
    },
  );
}

class _TimelineEntryCard extends StatelessWidget {
  final CareRecord entry;
  final bool isLatest;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _TimelineEntryCard({
    required this.entry,
    required this.isLatest,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final photos = photosOf(entry);
    final chemoStage = formatChemoStage(entry);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Surface(
        padding: const EdgeInsets.all(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isLatest ? pine : muted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '执行时间：${displayDate(entry.text('last'))}',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: isLatest ? FontWeight.bold : FontWeight.w600,
                        color: ink,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isLatest)
                    const StatusBadge(
                      label: '最新记录',
                      textColor: pine,
                      backgroundColor: Color(0xFFE8F0E7),
                    ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: muted),
                      onPressed: onDelete,
                      tooltip: '删除此记录',
                    ),
                ],
              ),
              if (chemoStage.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFC8E6C9), width: 0.6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.medication_outlined,
                        size: 13,
                        color: Color(0xFF2E7D32),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        chemoStage,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAF6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.update, size: 14, color: pine),
                    const SizedBox(width: 6),
                    Text(
                      '约定的下次执行：${displayDate(entry.text('next'))}',
                      style: const TextStyle(fontSize: 12, color: pine),
                    ),
                  ],
                ),
              ),
              if (entry.text('note').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  entry.text('note'),
                  style: const TextStyle(fontSize: 12.5, color: ink, height: 1.4),
                ),
              ],
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.photo_library_outlined, size: 14, color: muted),
                    const SizedBox(width: 4),
                    Text(
                      '${photos.length} 张维护留档照片',
                      style: const TextStyle(fontSize: 11.5, color: muted),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
