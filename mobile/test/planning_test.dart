import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anban/data/models.dart';
import 'package:anban/data/planning.dart';
import 'package:anban/data/store.dart';
import 'package:anban/data/vault.dart';

void main() {
  test('meal and water schedules respect count, duration and daily bounds', () {
    final meals = mealTimes({});
    expect(meals, hasLength(5));
    expect(meals.first, 7 * 60 + 30);
    expect(meals.last + 30, 18 * 60 + 30);
    for (var i = 1; i < meals.length; i++) {
      expect(meals[i] - meals[i - 1], greaterThanOrEqualTo(30));
    }
    expect(mealTimes({'mealCount': '1'}), [450]);
    expect(
      () => mealTimes({
        'mealCount': '12',
        'mealStart': '08:00',
        'mealEnd': '09:00',
      }),
      throwsFormatException,
    );
    expect(() => mealTimes({'mealStart': '25:00'}), throwsFormatException);
    expect(waterTimes({'waterStart': '08:00', 'waterEnd': '09:10'}), [
      480,
      510,
      540,
    ]);
    expect(
      () => waterTimes({'waterStart': '19:00', 'waterEnd': '08:00'}),
      throwsFormatException,
    );
    expect(
      () => waterTimes({
        'waterStart': '08:00',
        'waterEnd': '09:00',
        'waterInterval': '0',
      }),
      throwsFormatException,
    );
  });
  test('journey reminders use latest execution, update after edits, and respect switches', () async {
    final root = CareRecord(
      kind: 'journey',
      fields: {
        'category': 'picc',
        'last': '2026-10-01T10:00:00',
        'next': '2026-10-08T10:00:00',
      },
    );
    final entry = CareRecord(
      kind: 'journeyEntry',
      fields: {
        'journeyId': root.id,
        'last': '2026-10-08T10:00:00',
        'next': '2026-10-15T10:00:00',
      },
    );
    final older = CareRecord(
      kind: 'journeyEntry',
      fields: {
        'journeyId': root.id,
        'last': '2026-09-24T10:00:00',
        'next': '2026-10-01T10:00:00',
      },
    );
    expect(latestJourney([root, older], root).id, root.id);
    final data = CareData(
      records: [root, entry],
      settings: {'notify_picc': 'true', 'lead_picc': '2', 'count_picc': '2'},
    );
    final reminders = planReminders(data, DateTime(2026, 10, 12), days: 5);
    expect(reminders.map((r) => r.at), [
      DateTime(2026, 10, 13, 9),
      DateTime(2026, 10, 13, 18),
      DateTime(2026, 10, 14, 9),
      DateTime(2026, 10, 14, 18),
      DateTime(2026, 10, 15, 10),
    ]);
    expect(
      planReminders(data.copy(settings: {}), DateTime(2026, 10, 12)),
      isEmpty,
    );
    final changed = entry.copy(
      fields: {...entry.fields, 'next': '2026-10-16T11:30:00'},
    );
    expect(
      latestJourney([root, changed], root).text('next'),
      '2026-10-16T11:30:00',
    );
    final store = CareStore(await LocalVault.memory(), data);
    expect(() => store.remove(entry), throwsStateError);
    await expectLater(
      store.put(
        CareRecord(
          kind: 'journeyEntry',
          fields: {...entry.fields, 'journeyId': 'missing'},
        ),
      ),
      throwsStateError,
    );
    store.dispose();
    await store.vault.close();
  });
  test('health records validate required fields and nine images survive backup restore', () async {
    for (final record in [
      CareRecord(kind: 'weight', fields: {}),
      CareRecord(kind: 'weight', fields: {'weight': 'NaN'}),
      CareRecord(kind: 'stool', fields: {'status': '[]'}),
      CareRecord(kind: 'urine', fields: {'status': '[]'}),
      CareRecord(
        kind: 'journey',
        fields: {'category': 'picc', 'last': '2026-10-01T10:00:00'},
      ),
    ]) {
      expect(record.validate, throwsFormatException);
    }
    CareRecord(
      kind: 'stool',
      fields: {
        'status': jsonEncode(['便秘', '血便']),
      },
    ).validate();
    final source = await LocalVault.memory();
    final target = await LocalVault.memory();
    final photos = <Map<String, String>>[];
    for (var i = 0; i < 9; i++) {
      photos.add({
        'id': await source.addAttachment(Uint8List.fromList([i + 1])),
        'name': '$i.png',
      });
    }
    final record = CareRecord(
      kind: 'weight',
      at: DateTime(2026, 10, 2, 12, 34),
      fields: {'weight': '55.5', 'photos': jsonEncode(photos)},
    );
    record.validate();
    final backup = await source.backup(CareData(records: [record]));
    expect((backup['files'] as Map).length, 9);
    final restored = await target.restore(backup);
    expect(restored.records.single.at, DateTime(2026, 10, 2, 12, 34));
    for (var i = 0; i < 9; i++) {
      expect(await target.attachment(photos[i]['id']!), [i + 1]);
    }
    expect(
      () => record
          .copy(
            fields: {
              ...record.fields,
              'photos': jsonEncode([...photos, photos.first]),
            },
          )
          .validate(),
      throwsFormatException,
    );
    await source.close();
    await target.close();
  });
}
