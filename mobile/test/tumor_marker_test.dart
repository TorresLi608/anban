import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anban/data/models.dart';
import 'package:anban/data/store.dart';
import 'package:anban/data/tumor_marker.dart';
import 'package:anban/data/vault.dart';
import 'package:anban/screens/records.dart';
import 'package:anban/screens/tumor_marker_chart.dart';
import 'package:anban/services/export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TumorMarker Data & Parsing', () {
    test('12 items default definitions are complete and correct', () {
      expect(defaultTumorMarkers12.length, 12);
      final keys = defaultTumorMarkers12.map((e) => e.key).toSet();
      expect(keys.length, 12);

      // 验证用户指定的12项核心标志物
      expect(keys, containsAll(['afp', 'cea', 'nse', 'ca50', 'ferr', 'scc', 'ca199', 'ca242', 'ca125', 'ca153', 'ca724', 'cyfra1']));
    });

    test('auto detect status against reference range', () {
      // 1. AFP: 0-7
      expect(TumorMarkerItem.detectStatus('5.2', '0–7'), 'normal');
      expect(TumorMarkerItem.detectStatus('8.1', '0–7'), 'high');

      // 2. CEA: 0-5
      expect(TumorMarkerItem.detectStatus('3.2', '0–5'), 'normal');
      expect(TumorMarkerItem.detectStatus('6.8', '0–5'), 'high');

      // 5. FERR: 13-150
      expect(TumorMarkerItem.detectStatus('100', '13–150'), 'normal');
      expect(TumorMarkerItem.detectStatus('10', '13–150'), 'low');
      expect(TumorMarkerItem.detectStatus('180', '13–150'), 'high');

      // 6. SCC: 0-1.5
      expect(TumorMarkerItem.detectStatus('1.2', '0–1.5'), 'normal');
      expect(TumorMarkerItem.detectStatus('2.0', '0–1.5'), 'high');

      // 7. CA19-9: 0-26.1
      expect(TumorMarkerItem.detectStatus('15.4', '0–26.1'), 'normal');
      expect(TumorMarkerItem.detectStatus('35.0', '0–26.1'), 'high');

      // 11. CA72-4: 0-8.79
      expect(TumorMarkerItem.detectStatus('5.0', '0–8.79'), 'normal');
      expect(TumorMarkerItem.detectStatus('12.5', '0–8.79'), 'high');

      // 12. CYFRA-1: 0-3.3
      expect(TumorMarkerItem.detectStatus('2.1', '0–3.3'), 'normal');
      expect(TumorMarkerItem.detectStatus('4.0', '0–3.3'), 'high');

      // 空白或非法数值
      expect(TumorMarkerItem.detectStatus('', '0–5'), '');
      expect(TumorMarkerItem.detectStatus('abc', '0–5'), '');
    });

    test('summarizeTumorMarkers generates human friendly Chinese summary', () {
      final items = parseTumorMarkers('');
      expect(summarizeTumorMarkers(items), '未录入指标');

      // 录入正常项
      final normalItems = items.map((e) {
        if (e.key == 'cea') return e.copyWith(value: '2.1', status: 'normal');
        if (e.key == 'afp') return e.copyWith(value: '3.0', status: 'normal');
        return e;
      }).toList();
      expect(summarizeTumorMarkers(normalItems), '已录入 2 项，全部正常');

      // 录入偏高项
      final highItems = normalItems.map((e) {
        if (e.key == 'cea') return e.copyWith(value: '7.8', status: 'high');
        return e;
      }).toList();
      expect(summarizeTumorMarkers(highItems), contains('1 项偏高 (CEA)'));
    });

    test('validation rules for tumorMarker CareRecord', () {
      // 空记录抛异常
      expect(
        () => CareRecord(kind: 'tumorMarker', fields: {}).validate(),
        throwsFormatException,
      );

      // 非法 JSON 抛异常
      expect(
        () => CareRecord(
          kind: 'tumorMarker',
          fields: {'markers': 'not-a-json'},
        ).validate(),
        throwsFormatException,
      );

      // 有效 markers
      final valid = CareRecord(
        kind: 'tumorMarker',
        fields: {
          'markers': jsonEncode([
            {'key': 'cea', 'name': '癌胚抗原', 'value': '3.2', 'status': 'normal'},
          ]),
          'summary': '已录入 1 项，全部正常',
        },
      );
      valid.validate(); // 不抛异常

      // 仅有照片亦有效
      final withPhoto = CareRecord(
        kind: 'tumorMarker',
        fields: {
          'photos': jsonEncode([
            {'id': 'att_123', 'name': '化验单.jpg'},
          ]),
        },
      );
      withPhoto.validate();
    });
  });

  group('TumorMarker UI and Form Interaction', () {
    testWidgets('TumorMarkerChart renders line chart and handles selection', (tester) async {
      final record1 = CareRecord(
        kind: 'tumorMarker',
        at: DateTime(2026, 9, 1),
        fields: {
          'markers': jsonEncode([
            {
              'key': 'cea',
              'name': '癌胚抗原',
              'abbr': 'CEA',
              'value': '8.5',
              'unit': 'ng/mL',
              'ref': '0–5',
              'status': 'high',
            },
          ]),
        },
      );
      final record2 = CareRecord(
        kind: 'tumorMarker',
        at: DateTime(2026, 10, 1),
        fields: {
          'markers': jsonEncode([
            {
              'key': 'cea',
              'name': '癌胚抗原',
              'abbr': 'CEA',
              'value': '4.2',
              'unit': 'ng/mL',
              'ref': '0–5',
              'status': 'normal',
            },
          ]),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TumorMarkerChart(records: [record1, record2]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('癌胚抗原 (CEA) 趋势'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.textContaining('最新记录: 4.2 ng/mL (正常)'), findsOneWidget);
    });

    testWidgets('RecordsPage shows tumor marker tab and card details', (tester) async {
      final vault = (await tester.runAsync(LocalVault.memory))!;
      final r = CareRecord(
        kind: 'tumorMarker',
        at: DateTime(2026, 10, 26, 10, 30),
        fields: {
          'hospital': '北京协和医院',
          'summary': '1 项偏高 (CEA)',
          'markers': jsonEncode([
            {
              'key': 'cea',
              'name': '癌胚抗原',
              'abbr': 'CEA',
              'value': '7.2',
              'unit': 'ng/mL',
              'ref': '0–5',
              'hint': '结直肠癌、胃癌',
              'status': 'high',
            },
            {
              'key': 'afp',
              'name': '甲胎蛋白',
              'abbr': 'AFP',
              'value': '3.1',
              'unit': 'ng/mL',
              'ref': '0–7',
              'hint': '原发性肝癌',
              'status': 'normal',
            },
          ]),
          'note': '化疗后第一次复查化验',
        },
      );
      final store = CareStore(vault, CareData(records: [r]));

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

      // 点击肿瘤标志物 FilterChip
      final chip = find.widgetWithText(FilterChip, '肿瘤标志物');
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      // 验证卡片展示
      expect(find.text('北京协和医院'), findsOneWidget);
      expect(find.textContaining('1 项偏高 (CEA)'), findsWidgets);
      expect(find.text('CEA 7.2 ng/mL ↑'), findsOneWidget);

      // 点击展开12项明细
      final expandBtn = find.textContaining('查看12项检验单明细');
      expect(expandBtn, findsOneWidget);
      await tester.ensureVisible(expandBtn);
      await tester.pumpAndSettle();
      await tester.tap(expandBtn);
      await tester.pumpAndSettle();

      expect(find.text('偏高↑'), findsOneWidget);
      expect(find.text('收起12项明细'), findsOneWidget);
    });

    test('medicalPdf export supports tumorMarker records', () async {
      final data = CareData(
        records: [
          CareRecord(
            kind: 'tumorMarker',
            at: DateTime.now(),
            fields: {
              'hospital': '肿瘤医院',
              'summary': '全部正常',
              'note': '术后随访',
            },
          ),
        ],
      );
      final pdfBytes = await medicalPdf(data, days: 7);
      expect(pdfBytes, isNotEmpty);
    });
  });
}
