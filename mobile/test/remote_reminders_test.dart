import 'dart:convert';

import 'package:anban/data/models.dart';
import 'package:anban/services/remote_reminders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 13, 6);
  test('remote mode is opt in and disabling produces an empty queue', () {
    expect(
      remoteReminderPlan(
        CareData(settings: {'notifyMeal': 'true'}),
        now,
        'Asia/Shanghai',
      )['jobs'],
      isEmpty,
    );
  });
  test('coincident events are merged without transmitting care content', () {
    final data = CareData(
      settings: {
        'notifyRemote': 'true',
        'notify_picc': 'true',
        'lead_picc': '0',
      },
      records: [
        for (var i = 0; i < 2; i++)
          CareRecord(
            kind: 'journey',
            fields: {
              'category': 'picc',
              'last': '2026-10-10',
              'next': '2026-10-13T09:00:00',
              'notes': 'private-care-notes',
            },
          ),
      ],
    );
    final plan = remoteReminderPlan(data, now, 'Asia/Shanghai');
    final jobs = plan['jobs'] as List;
    expect(jobs, hasLength(1));
    expect(jobs.single['key'], startsWith('event:'));
    expect(jobs.single['at'], endsWith('Z'));
    expect(jsonEncode(plan), isNot(contains('private-care-notes')));
    expect(jsonEncode(plan), isNot(contains('picc')));
  });
  test('individual category switches also apply to the backend plan', () {
    final plan = remoteReminderPlan(
      CareData(
        settings: {
          'notifyRemote': 'true',
          'notifyMeal': 'true',
          'notifyWater': 'false',
        },
      ),
      now,
      'Asia/Shanghai',
    );
    expect(plan['jobs'], hasLength(5));
    for (final job in plan['jobs'] as List) {
      expect(job['daily'], isNotEmpty);
    }
  });
}
