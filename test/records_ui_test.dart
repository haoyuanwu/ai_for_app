import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/ui/records_view.dart';

import 'records_test.dart' show FakeScheduler;

void main() {
  testWidgets(
    'records display categories, totals, draft reminders and readable responsive controls',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      late Directory directory;
      late LocalStore store;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('records_ui');
        store = await LocalStore.openAt(directory);
      });
      final repository = RecordRepository(store.database);
      final service = RecordService(
        repository,
        FakeScheduler(),
        (text, now) async => [],
      );
      await tester.runAsync(
        () => repository.insert('sample', [
          const ExtractedRecord(
            kind: RecordKind.reminder,
            title: '买药',
            quote: '明天提醒我买药',
          ),
          const ExtractedRecord(
            kind: RecordKind.expense,
            title: '午饭',
            quote: '午饭花了12.50元',
            amountMinor: 1250,
            currency: 'CNY',
            direction: 'expense',
          ),
          const ExtractedRecord(
            kind: RecordKind.phone,
            title: '张三',
            quote: '张三电话13800138000',
            phone: '13800138000',
          ),
        ]),
      );
      final boundaryKey = GlobalKey();
      Future<void> show(Size size, double scale) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              colorSchemeSeed: const Color(0xff2563eb),
            ),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: Scaffold(
                appBar: AppBar(title: const Text('本地随记')),
                body: RepaintBoundary(
                  key: boundaryKey,
                  child: RecordsView(store: store, service: service),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await show(const Size(375, 812), 1);
      expect(find.text('CNY 支出：12.50'), findsOneWidget);
      // A local, reviewable rendering artifact; not a golden baseline.
      await tester.runAsync(() async {
        final image =
            await (boundaryKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        await File('/tmp/local_ai_records.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.widgetWithText(ChoiceChip, '提醒'));
      await tester.pumpAndSettle();
      expect(find.text('待补充提醒时间'), findsOneWidget);
      expect(find.text('补充提醒时间'), findsOneWidget);
      await show(const Size(812, 375), 1.8);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await store.database.close();
        await directory.delete(recursive: true);
      });
    },
  );
}
