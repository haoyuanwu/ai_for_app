import 'dart:convert';
import 'dart:io';

import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/ui/record_detail_page.dart';
import 'package:ai_for_app/ui/edit_record_sheet.dart';
import 'package:ai_for_app/ui/app_theme.dart';
import 'package:ai_for_app/ui/records_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'records_test.dart' show FakeScheduler;

void main() {
  testWidgets(
    'all detail designs adapt to small phones, landscape and large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final size in [const Size(375, 812), const Size(812, 375)]) {
        tester.view.physicalSize = size;
        for (final type in [
          'birthday',
          'date',
          'reminder',
          'expense',
          'phone',
          'task',
          'note',
          'image',
          'audio',
        ]) {
          final data = <String, dynamic>{
            'kind': ['birthday', 'date'].contains(type)
                ? 'date'
                : ['image', 'audio'].contains(type)
                ? 'note'
                : type,
            'template': type,
            'title': '旅行中值得记住的一件事',
            'date': '2026-11-06',
            'at': '2026-11-07T09:30:00+08:00',
            'amountMinor': 12345,
            'currency': 'CNY',
            'direction': 'expense',
            'phone': '13800138000',
            'body': '在这里保存清晰的事实与温暖的回忆。',
            'fields': [
              {'label': '地点', 'value': '杭州'},
              {'label': '人物', 'value': '朋友'},
            ],
          };
          await tester.pumpWidget(
            MaterialApp(
              theme: journalTheme(),
              home: MediaQuery(
                data: MediaQueryData(textScaler: const TextScaler.linear(1.8)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: RecordDetailContent(data: data),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$type $size');
          expect(find.byKey(ValueKey('detail-$type')), findsOneWidget);
          expect(find.byType(ListTile), findsNothing);
          expect(find.textContaining('展示模板'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );
  testWidgets('task completion persists and editor hides template selection', (
    tester,
  ) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('record_detail'),
    ))!;
    final store = (await tester.runAsync(() => LocalStore.openAt(root)))!;
    final repo = RecordRepository(store.database);
    final service = RecordService(repo, FakeScheduler(), (t, n) async => []);
    Future<void> flush() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
    }

    try {
      final ids = (await tester.runAsync(
        () => repo.insert('task', [
          const ExtractedRecord(
            kind: RecordKind.task,
            title: '买牛奶',
            quote: '买牛奶',
          ),
        ]),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          theme: journalTheme(),
          home: Scaffold(
            body: RecordsView(store: store, service: service),
          ),
        ),
      );
      await flush();
      await tester.tap(find.byTooltip('查看详情'));
      await flush();
      expect(find.byType(RecordDetailPage), findsOneWidget);
      await tester.ensureVisible(find.text('标记完成'));
      await tester.tap(find.text('标记完成'));
      await flush();
      final saved = jsonDecode(
        (await tester.runAsync(() => repo.get(ids.single)))!['payload']
            as String,
      );
      expect(saved['fields'], [
        {'label': '进度', 'value': '已完成'},
      ]);
      expect(find.text('恢复待办'), findsOneWidget);
      await tester.tap(find.byTooltip('编辑记录'));
      await tester.pumpAndSettle();
      expect(find.byType(EditRecordSheet), findsOneWidget);
      expect(find.textContaining('展示模板'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      Navigator.of(tester.element(find.byType(EditRecordSheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await flush();
      expect((await tester.runAsync(repo.all))!, isEmpty);
      expect(find.byType(RecordDetailPage), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await store.database.close();
        await root.delete(recursive: true);
      });
    }
  });
}
