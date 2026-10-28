import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anban/data/models.dart';
import 'package:anban/data/planning.dart';
import 'package:anban/data/store.dart';
import 'package:anban/data/vault.dart';
import 'package:anban/screens/care.dart';
import 'package:anban/screens/forms.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('化疗周期与给药次数格式化工具测试', () {
    test('formatChemoCycle: 纯数字转为标准化周期文本，自定义文本原样保留，空值返回空串', () {
      expect(formatChemoCycle('1'), '第 1 周期');
      expect(formatChemoCycle('  2  '), '第 2 周期');
      expect(formatChemoCycle('第3周期'), '第3周期');
      expect(formatChemoCycle('维持治疗期'), '维持治疗期');
      expect(formatChemoCycle(''), '');
      expect(formatChemoCycle('   '), '');
    });

    test('formatChemoDose: 纯数字转为标准化给药次数，自定义文本原样保留，空值返回空串', () {
      expect(formatChemoDose('1'), '第 1 次给药');
      expect(formatChemoDose('  3  '), '第 3 次给药');
      expect(formatChemoDose('第2次'), '第2次');
      expect(formatChemoDose(''), '');
      expect(formatChemoDose('   '), '');
    });

    test('formatChemoStage: 灵活组合周期与给药次数', () {
      final both = CareRecord(
        kind: 'journey',
        fields: {
          'category': 'chemo',
          'last': '2026-10-01 09:00',
          'next': '2026-10-21 09:00',
          'cycle': '2',
          'doseNumber': '1',
        },
      );
      expect(formatChemoStage(both), '第 2 周期 · 第 1 次给药');

      final onlyCycle = CareRecord(
        kind: 'journey',
        fields: {
          'category': 'chemo',
          'last': '2026-10-01 09:00',
          'next': '2026-10-21 09:00',
          'cycle': '第3周期',
        },
      );
      expect(formatChemoStage(onlyCycle), '第3周期');

      final onlyDose = CareRecord(
        kind: 'journeyEntry',
        fields: {
          'journeyId': 'j1',
          'last': '2026-10-01 09:00',
          'next': '2026-10-21 09:00',
          'doseNumber': '2',
        },
      );
      expect(formatChemoStage(onlyDose), '第 2 次给药');

      final empty = CareRecord(
        kind: 'journey',
        fields: {
          'category': 'chemo',
          'last': '2026-10-01 09:00',
          'next': '2026-10-21 09:00',
        },
      );
      expect(formatChemoStage(empty), '');
    });
  });

  group('化疗数据模型校验测试', () {
    test('周期和给药次数非必填，填与不填均可正常通过 CareRecord 校验', () {
      // 包含周期和给药次数
      final withFields = CareRecord(
        kind: 'journey',
        fields: {
          'category': 'chemo',
          'last': '2026-10-01 09:00',
          'next': '2026-10-21 09:00',
          'cycle': '1',
          'doseNumber': '1',
        },
      );
      expect(() => withFields.validate(), returnsNormally);

      // 不包含周期和给药次数
      final withoutFields = CareRecord(
        kind: 'journey',
        fields: {
          'category': 'chemo',
          'last': '2026-10-01 09:00',
          'next': '2026-10-21 09:00',
        },
      );
      expect(() => withoutFields.validate(), returnsNormally);

      // journeyEntry 包含与不包含
      final entry = CareRecord(
        kind: 'journeyEntry',
        fields: {
          'journeyId': 'j1',
          'last': '2026-10-01 09:00',
          'next': '2026-10-21 09:00',
          'cycle': '2',
          'doseNumber': '2',
        },
      );
      expect(() => entry.validate(), returnsNormally);
    });
  });

  group('化疗界面展示与表单测试', () {
    testWidgets('JourneyList 与时间轴历史卡片中正确展示化疗周期与给药次数', (tester) async {
      final vault = (await tester.runAsync(LocalVault.memory))!;
      final chemoJourney = CareRecord(
        id: 'chemo-1',
        kind: 'journey',
        fields: {
          'category': 'chemo',
          'last': '2026-10-01 09:00',
          'next': '2026-10-21 09:00',
          'cycle': '1',
          'doseNumber': '1',
          'note': '首次化疗执行良好',
        },
      );
      final secondDose = CareRecord(
        id: 'entry-1',
        kind: 'journeyEntry',
        fields: {
          'journeyId': 'chemo-1',
          'last': '2026-10-15 09:00',
          'next': '2026-10-22 09:00',
          'cycle': '1',
          'doseNumber': '2',
          'note': '第1周期第2次给药顺利',
        },
      );
      final store = CareStore(
        vault,
        CareData(records: [chemoJourney, secondDose]),
      );

      // 渲染 CarePage
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CarePage(store: store),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 在列表中能够看到化疗及最新的阶段
      expect(find.text('化疗'), findsOneWidget);
      expect(find.text('第 1 周期 · 第 2 次给药'), findsOneWidget);

      // 点击进入行程详情
      await tester.tap(find.text('化疗'));
      await tester.pumpAndSettle();

      // 详情页顶部安排状态展示最新进度
      expect(find.text('当前安排状态'), findsOneWidget);
      expect(find.text('第 1 周期 · 第 2 次给药'), findsWidgets);

      // 历史时间轴中能找到各次的执行记录和对应阶段
      expect(find.text('执行历史时间轴 (2)'), findsOneWidget);
      expect(find.text('第 1 周期 · 第 1 次给药'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(vault.close);
      store.dispose();
    });

    testWidgets('化疗表单中支持展示并输入周期与给药次数', (tester) async {
      final vault = (await tester.runAsync(LocalVault.memory))!;
      final store = CareStore(vault, CareData());

      // 打开化疗行程表单（initial category 为 chemo）
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordForm(
                store: store,
                kind: 'journey',
                initial: const {
                  'category': 'chemo',
                  'last': '2026-10-01 09:00',
                  'next': '2026-10-21 09:00',
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 检查化疗周期与给药次数输入框存在
      expect(find.text('周期（选填）'), findsOneWidget);
      expect(find.text('给药次数（选填）'), findsOneWidget);

      // 输入周期与给药次数
      final cycleField = find.ancestor(
        of: find.text('周期（选填）'),
        matching: find.byType(TextFormField),
      );
      final doseField = find.ancestor(
        of: find.text('给药次数（选填）'),
        matching: find.byType(TextFormField),
      );

      await tester.enterText(cycleField, '2');
      await tester.enterText(doseField, '1');
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(vault.close);
      store.dispose();
    });
  });
}
