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
      const PageHeading('CARE JOURNEYS', '化疗及维护行程', '记好每次执行时间，及时安排下一次。'),
      FilledButton.icon(
        onPressed: () => editRecord(context, store, 'journey'),
        icon: const Icon(Icons.add),
        label: const Text('创建行程'),
      ),
      const SizedBox(height: 24),
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
      return const EmptyState(
        Icons.event_note_outlined,
        '暂无化疗及维护行程',
        '添加PICC护理、输液港护理或化疗安排',
      );
    }
    return Column(
      children: [
        for (final journey in journeys)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Surface(
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        JourneyDetail(store: store, journeyId: journey.id),
                  ),
                ),
                child: Builder(
                  builder: (context) {
                    final latest = latestJourney(store.data.records, journey);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          journeyCategories[journey.text('category')]!,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Text('上次执行：${displayDate(latest.text('last'))}'),
                        const SizedBox(height: 6),
                        Text(
                          '下次执行：${displayDate(latest.text('next'))}',
                          style: const TextStyle(
                            color: pine,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (latest.text('note').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(latest.text('note')),
                          ),
                        const SizedBox(height: 10),
                        const Text(
                          '查看与新增行程记录 →',
                          style: TextStyle(color: pine),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String displayDate(String value) {
  final date = DateTime.parse(value);
  return '${dayKey(date)} ${clockText(date)}';
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
      final entries =
          [
            journey,
            ...store
                .records('journeyEntry')
                .where((r) => r.text('journeyId') == journeyId),
          ]..sort(
            (a, b) =>
                DateTime.parse(b.text('last'))
                    .compareTo(DateTime.parse(a.text('last'))),
          );
      return Scaffold(
        appBar: AppBar(
          title: Text(journeyCategories[journey.text('category')]!),
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            FilledButton.icon(
              onPressed: () => editRecord(
                context,
                store,
                'journeyEntry',
                initial: {'journeyId': journeyId},
              ),
              icon: const Icon(Icons.add),
              label: const Text('新增行程记录'),
            ),
            const SizedBox(height: 20),
            for (final entry in entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                title: Text('上次执行 ${displayDate(entry.text('last'))}'),
                subtitle: Text(
                  '下次执行 ${displayDate(entry.text('next'))}\n${entry.text('note')}\n${photosOf(entry).length} 张图片',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () =>
                    editRecord(context, store, entry.kind, record: entry),
              ),
          ],
        ),
      );
    },
  );
}
