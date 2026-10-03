import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:anban/data/models.dart';
import 'package:anban/data/medical.dart';
import 'package:anban/data/store.dart';
import 'package:anban/data/vault.dart';
import 'package:anban/main.dart';
import 'package:anban/services/medical_export.dart';
import 'package:anban/services/reminders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<CareStore> medicalFixture() async {
  final vault = await LocalVault.memory();
  final root = CareRecord(
    id: 'root-folder',
    kind: 'folder',
    fields: {'title': '2026 年资料'},
  );
  final child = CareRecord(
    id: 'child-folder',
    kind: 'folder',
    fields: {'title': '影像检查', 'folderId': root.id},
  );
  final docs = <CareRecord>[];
  for (var i = 0; i < 12; i++) {
    final id = await vault.addAttachment(Uint8List.fromList([i, 2, 3]));
    docs.add(
      CareRecord(
        id: 'doc-$i',
        kind: 'document',
        fields: {
          'title': '报告 $i',
          'filename': '同名报告.txt',
          'extension': 'txt',
          'folderId': child.id,
          'attachment': id,
        },
      ),
    );
  }
  final visit = CareRecord(
    id: 'visit-one',
    kind: 'visit',
    at: DateTime(2026, 10, 1, 8),
    fields: {
      'title': '住院记录示例',
      'visitType': '住院',
      'hospital': '示例医院',
      'archiveIds': jsonEncode([root.id]),
      'findings': '检查结果按医生记录填写。',
      'dischargeAt': '2026-10-03T09:00:00',
    },
  );
  final instruction = CareRecord(
    id: 'instruction-one',
    kind: 'instruction',
    fields: {'title': '医嘱示例', 'content': '按医生提供的安排记录体温。', 'visitId': visit.id},
  );
  final data = CareData(
    records: [root, child, ...docs, visit, instruction],
    profile: {'name': '演示患者'},
  );
  await vault.save(data);
  return CareStore(vault, data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'nested folders, references and deletion preserve related records',
    () async {
      final store = await medicalFixture();
      final root = store
          .records('folder')
          .firstWhere((r) => r.id == 'root-folder');
      final child = store
          .records('folder')
          .firstWhere((r) => r.id == 'child-folder');
      expect(store.records('document'), hasLength(12));
      expect(archiveSelection(store.data.records, {root.id}), hasLength(14));
      await expectLater(
        store.put(root.copy(fields: {...root.fields, 'folderId': child.id})),
        throwsFormatException,
      );
      await expectLater(store.remove(root), throwsStateError);
      await store.put(child.copy(fields: {...child.fields, 'title': '重命名影像'}));
      expect(
        archiveLocation(store.data.records, store.records('document').first),
        contains('重命名影像'),
      );
      final visit = store.records('visit').single;
      await store.remove(visit);
      expect(store.records('instruction').single.text('visitId'), '');
      expect(store.records('document'), hasLength(12));
      final roundtrip = CareData.fromJson(store.data.toJson());
      expect(roundtrip.records.length, store.data.records.length);
      final v1 = {...store.data.toJson(), 'version': 1};
      expect(CareData.fromJson(v1).records.length, store.data.records.length);
      await store.vault.close();
      store.dispose();
    },
  );

  test(
    'PDF and ZIP include visits, nested originals and safe unique paths',
    () async {
      final store = await medicalFixture();
      final visit = store.records('visit').single;
      final longVisit = visit.copy(
        fields: {
          ...visit.fields,
          'note': List.filled(100, '这是用于分页验证的长段落。').join('\n'),
        },
      );
      final pdf = await medicalRecordsPdf(store.data, [
        longVisit,
      ], title: '看诊导出示例');
      expect(ascii.decode(pdf.take(4).toList()), '%PDF');
      final parts = await medicalArchiveExports(
        store.data,
        store.vault,
        selectedIds: {'root-folder'},
        summary: [visit],
        title: '住院资料',
      ).toList();
      expect(parts, hasLength(1));
      final zip = ZipDecoder().decodeBytes(parts.single.bytes);
      final originals = zip.files
          .where((f) => f.name.endsWith('.txt') && f.name != '说明.txt')
          .toList();
      expect(originals, hasLength(12));
      expect(originals.map((f) => f.name).toSet(), hasLength(12));
      expect(originals.every((f) => f.name.contains('影像检查')), isTrue);
      expect(
        originals.every(
          (f) => !f.name.startsWith('/') && !f.name.split('/').contains('..'),
        ),
        isTrue,
      );
      expect(originals.first.content, hasLength(3));
      expect(zip.findFile('资料索引.pdf'), isNotNull);
      const qa = String.fromEnvironment('ANBAN_EXPORT_QA_DIR');
      if (qa.isNotEmpty) {
        await Directory(qa).create(recursive: true);
        await File('$qa/medical-records.pdf').writeAsBytes(pdf);
        await File('$qa/medical-records.zip').writeAsBytes(parts.single.bytes);
      }
      await store.vault.close();
      store.dispose();
    },
  );

  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets('medical workspace and forms work at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = (await tester.runAsync(medicalFixture))!;
      await tester.pumpWidget(
        AnbanApp(
          store: store,
          reminders: ReminderService(),
          requireLogin: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('医疗资料').last);
      await tester.pumpAndSettle();
      expect(find.text('新建文件夹'), findsOneWidget);
      await tester.tap(find.text('新建文件夹'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '文件夹名称 *'),
        '新建文件夹测试',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('保存记录'));
        await store.exclusive(() async {});
      });
      await tester.pumpAndSettle();
      expect(
        store.records('folder').any((r) => r.text('title') == '新建文件夹测试'),
        isTrue,
      );
      await tester.tap(find.text('看诊'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('住院记录示例'));
      await tester.pumpAndSettle();
      expect(find.text('关联档案（12）'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('医嘱'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记医嘱'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '医嘱内容 *'),
        '本次临时记录',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('保存记录'));
        await store.exclusive(() async {});
      });
      await tester.pumpAndSettle();
      expect(store.records('instruction'), hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(store.vault.close);
      store.dispose();
    });
  }
}
