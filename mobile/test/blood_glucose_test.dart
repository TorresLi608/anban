import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anban/data/models.dart';
import 'package:anban/data/store.dart';
import 'package:anban/data/vault.dart';
import 'package:anban/screens/forms.dart';
import 'package:anban/screens/home.dart';
import 'package:anban/screens/records.dart';
import 'package:anban/services/export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('血糖与小便数据模型校验测试', () {
    test('有效血糖值（0.5–50 mmol/L）正常通过校验', () {
      CareRecord(kind: 'bloodGlucose', fields: {'bloodGlucose': '5.6'}).validate();
      CareRecord(kind: 'bloodGlucose', fields: {'bloodGlucose': '3.9'}).validate();
      CareRecord(kind: 'bloodGlucose', fields: {'bloodGlucose': '11.1'}).validate();
      CareRecord(kind: 'bloodGlucose', fields: {'bloodGlucose': '0.5'}).validate();
      CareRecord(kind: 'bloodGlucose', fields: {'bloodGlucose': '50'}).validate();
    });

    test('无效或越界血糖值抛出 FormatException', () {
      // 超过 50 mmol/L
      expect(
        () => CareRecord(kind: 'bloodGlucose', fields: {'bloodGlucose': '50.1'}).validate(),
        throwsFormatException,
      );
      // 低于 0.5 mmol/L
      expect(
        () => CareRecord(kind: 'bloodGlucose', fields: {'bloodGlucose': '0.4'}).validate(),
        throwsFormatException,
      );
      // 非数字文本
      expect(
        () => CareRecord(kind: 'bloodGlucose', fields: {'bloodGlucose': '正常'}).validate(),
        throwsFormatException,
      );
      // 空值
      expect(
        () => CareRecord(kind: 'bloodGlucose', fields: {'bloodGlucose': ''}).validate(),
        throwsFormatException,
      );
    });

    test('小便排尿量毫升校验', () {
      // 正常包含 volume
      CareRecord(kind: 'urine', fields: {'status': '["正常"]', 'volume': '200'}).validate();
      CareRecord(kind: 'urine', fields: {'status': '["正常"]', 'volume': '5000'}).validate();
      // volume 选填，留空亦可正常通过
      CareRecord(kind: 'urine', fields: {'status': '["正常"]', 'volume': ''}).validate();
      CareRecord(kind: 'urine', fields: {'status': '["正常"]'}).validate();

      // 无效 volume：0 或负数或超大值
      expect(
        () => CareRecord(kind: 'urine', fields: {'status': '["正常"]', 'volume': '0'}).validate(),
        throwsFormatException,
      );
      expect(
        () => CareRecord(kind: 'urine', fields: {'status': '["正常"]', 'volume': '-10'}).validate(),
        throwsFormatException,
      );
      expect(
        () => CareRecord(kind: 'urine', fields: {'status': '["正常"]', 'volume': '5001'}).validate(),
        throwsFormatException,
      );
      expect(
        () => CareRecord(kind: 'urine', fields: {'status': '["正常"]', 'volume': 'abc'}).validate(),
        throwsFormatException,
      );
    });
  });

  group('血糖与小便导出测试', () {
    test('就诊报告包含血糖与排尿量记录', () async {
      final data = CareData(
        records: [
          CareRecord(
            kind: 'bloodGlucose',
            at: DateTime(2026, 11, 25, 8, 30),
            fields: {'bloodGlucose': '5.6', 'note': '空腹测量'},
          ),
          CareRecord(
            kind: 'urine',
            at: DateTime(2026, 11, 25, 9, 0),
            fields: {'status': '["正常"]', 'volume': '250', 'note': '晨起第一泡'},
          ),
        ],
      );
      final pdf = await medicalPdf(data);
      expect(ascii.decode(pdf.take(4).toList()), '%PDF');
      expect(pdf.length, greaterThan(1000));
    });
  });

  group('血糖与小便界面表单测试', () {
    testWidgets('在血糖录入表单中可输入并调节数值', (tester) async {
      final vault = (await tester.runAsync(LocalVault.memory))!;
      final store = CareStore(vault, CareData());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordForm(
                store: store,
                kind: 'bloodGlucose',
                initial: const {'bloodGlucose': '5.6'},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证血糖表单字段与快捷芯片存在
      expect(find.text('血糖值（mmol/L）*'), findsOneWidget);
      expect(find.text('5.6'), findsWidgets);
      expect(find.text('7.8'), findsOneWidget);

      // 点击 7.8 快捷预设 Chip
      await tester.tap(find.text('7.8'));
      await tester.pumpAndSettle();
      expect(find.text('7.8'), findsWidgets);

      // 验证输入超低血糖时出现预警
      await tester.tap(find.text('4.5'));
      await tester.pumpAndSettle();
      // 连续减小触发低血糖提示
      for (var i = 0; i < 7; i++) {
        await tester.tap(find.widgetWithText(ActionChip, '0.1').first);
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('血糖偏低'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(vault.close);
      store.dispose();
    });

    testWidgets('小便录入表单包含毫升输入字段与快捷预设', (tester) async {
      final vault = (await tester.runAsync(LocalVault.memory))!;
      final store = CareStore(vault, CareData());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordForm(
                store: store,
                kind: 'urine',
                initial: const {'status': '["正常"]'},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证排尿量字段与快捷芯片存在
      expect(find.text('排尿量（ml）'), findsOneWidget);
      expect(find.text('200 ml'), findsOneWidget);

      // 点击 200 ml 预设
      await tester.tap(find.text('200 ml'));
      await tester.pumpAndSettle();
      expect(find.text('200'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(vault.close);
      store.dispose();
    });

    testWidgets('健康记录页面展示血糖分类、走势图和历史卡片', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final vault = (await tester.runAsync(LocalVault.memory))!;
      final now = DateTime.now();
      final records = [
        CareRecord(
          id: 'bg-1',
          kind: 'bloodGlucose',
          at: now.subtract(const Duration(hours: 4)),
          fields: {'bloodGlucose': '5.6', 'note': '晨起空腹'},
        ),
        CareRecord(
          id: 'bg-2',
          kind: 'bloodGlucose',
          at: now.subtract(const Duration(hours: 1)),
          fields: {'bloodGlucose': '8.2', 'note': '午餐后2小时'},
        ),
      ];
      final store = CareStore(vault, CareData(records: records));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordsPage(store: store),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击筛选栏中的“血糖” FilterChip
      final chipFinder = find.widgetWithText(FilterChip, '血糖');
      await tester.tap(chipFinder);
      await tester.pumpAndSettle();

      // 验证当前选中的血糖概况横幅与历史列表
      expect(find.text('累计 2 笔记录 · 最新: 8.2 mmol/L'), findsOneWidget);
      expect(find.text('8.2 mmol/L'), findsWidgets);
      expect(find.text('5.6 mmol/L'), findsWidgets);
      expect(find.text('正常'), findsWidgets);

      // 验证血糖水平走势图存在
      expect(find.text('血糖水平走势'), findsOneWidget);
      expect(find.byType(BloodGlucoseChart), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(vault.close);
      store.dispose();
    });
  });
}
