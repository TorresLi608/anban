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
import 'package:anban/services/reminders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('血氧饱和度数据模型校验测试', () {
    test('有效血氧值（50–100%）正常通过校验', () {
      CareRecord(kind: 'bloodOxygen', fields: {'bloodOxygen': '98'}).validate();
      CareRecord(kind: 'bloodOxygen', fields: {'bloodOxygen': '98.5'}).validate();
      CareRecord(kind: 'bloodOxygen', fields: {'bloodOxygen': '100'}).validate();
      CareRecord(kind: 'bloodOxygen', fields: {'bloodOxygen': '50'}).validate();
    });

    test('无效或越界血氧值抛出 FormatException', () {
      // 超过 100%
      expect(
        () => CareRecord(kind: 'bloodOxygen', fields: {'bloodOxygen': '101'}).validate(),
        throwsFormatException,
      );
      // 低于 50%
      expect(
        () => CareRecord(kind: 'bloodOxygen', fields: {'bloodOxygen': '49'}).validate(),
        throwsFormatException,
      );
      // 非数字文本
      expect(
        () => CareRecord(kind: 'bloodOxygen', fields: {'bloodOxygen': '正常'}).validate(),
        throwsFormatException,
      );
      // 空值
      expect(
        () => CareRecord(kind: 'bloodOxygen', fields: {'bloodOxygen': ''}).validate(),
        throwsFormatException,
      );
    });
  });

  group('血氧 PDF 导出测试', () {
    test('就诊报告包含血氧记录', () async {
      final data = CareData(
        records: [
          CareRecord(
            kind: 'bloodOxygen',
            at: DateTime(2026, 10, 26, 10, 0),
            fields: {'bloodOxygen': '98', 'note': '指尖测量血氧充足'},
          ),
        ],
      );
      final pdf = await medicalPdf(data);
      expect(ascii.decode(pdf.take(4).toList()), '%PDF');
      expect(pdf.length, greaterThan(1000));
    });
  });

  group('血氧界面交互与趋势图测试', () {
    testWidgets('在血氧录入表单中可输入并调节数值', (tester) async {
      final vault = (await tester.runAsync(LocalVault.memory))!;
      final store = CareStore(vault, CareData());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordForm(
                store: store,
                kind: 'bloodOxygen',
                initial: const {'bloodOxygen': '98'},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证血氧表单字段存在
      expect(find.text('血氧饱和度（%）*'), findsOneWidget);
      expect(find.text('98%'), findsOneWidget);
      expect(find.text('95%'), findsOneWidget);

      // 点击 95% 快捷预设 Chip
      await tester.tap(find.text('95%'));
      await tester.pumpAndSettle();
      expect(find.text('95'), findsOneWidget);

      // 点击 93% 快捷预设 Chip，验证紧急预警提示出现
      await tester.tap(find.text('93%'));
      await tester.pumpAndSettle();
      expect(find.textContaining('血氧较低（≤93%）'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(vault.close);
      store.dispose();
    });

    testWidgets('健康记录页面展示血氧分类、走势图和历史卡片', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final vault = (await tester.runAsync(LocalVault.memory))!;
      final now = DateTime.now();
      final records = [
        CareRecord(
          id: 'o2-1',
          kind: 'bloodOxygen',
          at: now.subtract(const Duration(hours: 4)),
          fields: {'bloodOxygen': '98', 'note': '晨起安静状态'},
        ),
        CareRecord(
          id: 'o2-2',
          kind: 'bloodOxygen',
          at: now.subtract(const Duration(hours: 1)),
          fields: {'bloodOxygen': '94', 'note': '走动后微喘'},
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

      // 点击筛选栏中的“血氧” FilterChip
      final chipFinder = find.widgetWithText(FilterChip, '血氧');
      await tester.tap(chipFinder);
      await tester.pumpAndSettle();

      // 验证当前选中的血氧概况横幅与历史列表
      expect(find.text('累计 2 笔记录 · 最新: 94 %'), findsOneWidget);
      expect(find.text('94 %'), findsWidgets);
      expect(find.text('98 %'), findsWidgets);
      expect(find.text('偏低 <95%'), findsOneWidget);
      expect(find.text('正常'), findsOneWidget);

      // 验证血氧饱和度走势图存在
      expect(find.text('血氧饱和度走势'), findsOneWidget);
      expect(find.byType(BloodOxygenChart), findsOneWidget);
      expect(find.textContaining('最新 94%'), findsOneWidget);
      expect(find.textContaining('均值 96.0%'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(vault.close);
      store.dispose();
    });

    testWidgets('首页快捷磁贴区测血氧排在测心率后面且可打开录入', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final vault = (await tester.runAsync(LocalVault.memory))!;
      final store = CareStore(vault, CareData());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HomePage(
                store: store,
                reminders: ReminderService(),
                navigate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证测心率和测血氧都在首页快速记录区展示
      final heartFinder = find.text('测心率');
      final oxygenFinder = find.text('测血氧');
      expect(heartFinder, findsOneWidget);
      expect(oxygenFinder, findsOneWidget);

      // 验证测血氧排在测心率之后（在组件树或坐标中的相对顺序）
      final heartElement = tester.element(heartFinder);
      final oxygenElement = tester.element(oxygenFinder);
      expect(
        heartElement.depth,
        lessThanOrEqualTo(oxygenElement.depth),
      );

      // 点击“测血氧”磁贴，验证弹出录入表单
      await tester.tap(oxygenFinder);
      await tester.pumpAndSettle();
      expect(find.text('血氧饱和度（%）*'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(vault.close);
      store.dispose();
    });
  });
}

