import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:anban/data/models.dart';
import 'package:anban/data/store.dart';
import 'package:anban/data/vault.dart';
import 'package:anban/main.dart';
import 'package:anban/services/reminders.dart';
import 'package:anban/services/export.dart';

CareRecord medication() => CareRecord(
  kind: 'medication',
  fields: {
    'name': '测试用药（非真实医嘱）',
    'dose': '按测试医嘱',
    'type': '常规维持',
    'times': '08:00,20:00',
    'start': '2026-10-01',
    'end': '2026-10-02',
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('schedules respect start, inclusive stop and invalid clock values', () {
    final med = medication();
    med.validate();
    expect(dosesForDay([med], DateTime(2026, 9, 30)), isEmpty);
    expect(dosesForDay([med], DateTime(2026, 10, 2)), hasLength(2));
    expect(dosesForDay([med], DateTime(2026, 10, 3)), isEmpty);
    expect(() => parseTimes('24:01'), throwsFormatException);
    expect(parseTimes('20:00,08:00,08:00'), ['08:00', '20:00']);
    expect(
      () => CareRecord(kind: 'pain', fields: {'score': '11'}).validate(),
      throwsFormatException,
    );
    expect(
      () =>
          CareRecord(kind: 'vital', fields: {'temperature': 'NaN'}).validate(),
      throwsFormatException,
    );
    CareRecord(kind: 'temperature', fields: {'temperature': '36.7'}).validate();
    CareRecord(kind: 'heartRate', fields: {'heartRate': '72'}).validate();
    expect(
      () => CareRecord(
        kind: 'temperature',
        fields: {'temperature': '46'},
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => CareRecord(
        kind: 'heartRate',
        fields: {'heartRate': '300'},
      ).validate(),
      throwsFormatException,
    );
  });
  test(
    'local persistence, concurrent duplicate prevention and atomic restore',
    () async {
      final db = await databaseFactoryMemory.openDatabase('test-vault');
      final vault = LocalVault(db);
      final store = CareStore(vault, CareData());
      final med = medication();
      await store.put(med);
      final dose = dosesForDay(store.data.records, DateTime(2026, 10, 1)).first;
      final first = store.take(dose, '待观察');
      final duplicate = store.take(dose, '待观察');
      await first;
      await expectLater(duplicate, throwsStateError);
      expect(store.records('dose'), hasLength(1));
      expect((await vault.load()).records, hasLength(2));
      final raw = await stringMapStoreFactory
          .store('vault')
          .record('state')
          .get(db);
      expect(jsonEncode(raw), contains(med.text('name')));
      final file = await vault.addAttachment(Uint8List.fromList([1, 2, 3, 4]));
      await store.put(
        CareRecord(
          kind: 'memory',
          fields: {'title': '私密回忆', 'attachment': file},
        ),
      );
      final snapshot = await vault.backup(store.data);
      final before = store.data.toJson();
      await expectLater(
        store.restore({'data': before, 'files': <String, String>{}}),
        throwsFormatException,
      );
      expect(store.data.toJson(), before);
      expect(store.data.toJson()['records'].toString(), contains('私密回忆'));
      await store.restore(snapshot);
      expect(await vault.attachment(file), [1, 2, 3, 4]);
      await store.clear();
      expect((await vault.load()).records, isEmpty);
      store.dispose();
      await db.close();
    },
  );
  test(
    'plain backup restores correctly and legacy encrypted backups remain supported',
    () async {
      // 1. 明文备份与还原
      final payload = {
        'data': CareData(profile: {'name': '测试用户'}).toJson(),
        'files': {'file1': base64Encode([1, 2, 3])},
      };
      final plain = await sealBackup(payload);
      expect(plain['version'], 2);
      expect(plain['algorithm'], 'PLAIN');
      final opened = await openBackup(plain);
      expect(opened['data']['profile']['name'], '测试用户');

      // 2. 兼容旧版 AES-256-GCM 加密备份
      const password = 'a-long-backup-password';
      final salt = randomBytes(16);
      final key = await passwordKey(password, salt);
      final encryptedBytes = await encryptBytes(
        utf8.encode(jsonEncode(payload)),
        key,
      );
      final legacy = {
        'version': 1,
        'algorithm': 'AES-256-GCM',
        'iterations': 210000,
        'salt': base64Encode(salt),
        ...encryptedBytes,
      };
      expect((await openBackup(legacy, password))['data']['profile']['name'], '测试用户');
      await expectLater(
        openBackup(legacy, 'a-wrong-long-password'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final changed = {
        ...legacy,
        'ciphertext': base64Encode([1, 2, 3]),
      };
      await expectLater(
        openBackup(changed, password),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    },
  );
  test(
    'switching accounts isolates records and encrypted attachments',
    () async {
      final firstDb = await databaseFactoryMemory.openDatabase('account-a');
      final first = LocalVault(firstDb);
      final store = CareStore(first, CareData());
      await store.put(medication());
      final attachment = await first.addAttachment(
        Uint8List.fromList([1, 2, 3]),
      );
      final secondDb = await databaseFactoryMemory.openDatabase('account-b');
      final second = LocalVault(secondDb);
      await store.switchVault(second, await second.load());
      expect(store.data.records, isEmpty);
      await expectLater(store.vault.attachment(attachment), throwsStateError);
      await store.profile({'name': '另一个用户'});
      expect((await second.load()).profile['name'], '另一个用户');
      await secondDb.close();
      final reopened = LocalVault(
        await databaseFactoryMemory.openDatabase('account-a'),
      );
      expect((await reopened.load()).records, hasLength(1));
      expect(await reopened.attachment(attachment), [1, 2, 3]);
      await reopened.db.close();
      store.dispose();
    },
  );
  test('Chinese PDF is generated locally', () async {
    final pdf = await medicalPdf(
      CareData(
        records: [
          CareRecord(kind: 'pain', fields: {'score': '3', 'location': '上腹'}),
        ],
      ),
    );
    expect(ascii.decode(pdf.take(4).toList()), '%PDF');
    expect(pdf.length, greaterThan(1000));
  });
  testWidgets('cloud app requires login and shows simplified login dialog', (
    tester,
  ) async {
    final vault = (await tester.runAsync(LocalVault.memory))!;
    final store = CareStore(vault, CareData());
    await tester.pumpWidget(
      AnbanApp(store: store, reminders: ReminderService()),
    );
    await tester.pumpAndSettle();
    expect(find.text('今日照护'), findsNothing);
    await tester.tap(find.text('登录 / 注册'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('登录密码（至少 6 个字符）'), findsOneWidget);
    expect(find.text('资料加密密码（至少 6 个字符）'), findsNothing);
    expect(find.text('后端服务地址'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(vault.close);
    store.dispose();
  });
  for (final width in [390.0, 1440.0, 320.0]) {
    testWidgets('five pages and pain form at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('widgets-$width'),
      ))!;
      final store = CareStore(
        LocalVault(db, SecretKey(List.filled(32, 1))),
        CareData(),
      );
      final reminders = ReminderService();
      await tester.pumpWidget(
        AnbanApp(store: store, reminders: reminders, requireLogin: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('今日照护'), findsOneWidget);
      await tester.tap(find.text('记一次疼痛'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存记录'));
      await tester.pumpAndSettle();
      expect(store.records('pain'), hasLength(1));
      await tester.tap(find.text('随便记一笔'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存记录'));
      await tester.pumpAndSettle();
      expect(store.records('memory'), hasLength(1));
      for (final name in ['健康记录', '行程', '医疗资料', '我的']) {
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$name at $width');
      }
      expect(find.text('导出加密备份'), findsOneWidget);
      expect(find.text('从加密备份恢复'), findsOneWidget);
      expect(find.text('退出登录'), findsOneWidget);
      expect(find.text('刷新云端资料'), findsNothing);
      expect(find.text('清空云端资料'), findsNothing);
      await tester.runAsync(
        () => store.settings({'largeText': 'true', 'dark': 'true'}),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      store.dispose();
      reminders.dispose();
      await tester.runAsync(() => db.close());
    });
  }
}
