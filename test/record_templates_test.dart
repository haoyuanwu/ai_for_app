import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/records/record_templates.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/ui/record_data_view.dart';
import 'package:ai_for_app/ui/records_view.dart';
import 'package:ai_for_app/ui/edit_record_sheet.dart';

import 'records_test.dart' show FakeScheduler;

void main() {
  test('birthday templates normalize dates without inventing year or converting lunar dates', () {
    Map<String, dynamic> birthday(String quote) =>
        presentRecord({'kind': 'note', 'title': '生日', 'quote': quote});
    expect(birthday('我的生日1996年8月12日')['date'], '1996-08-12');
    expect(birthday('生日一九九六年八月十二日')['date'], '1996-08-12');
    expect(birthday('生日8月12日')['date'], isNull);
    expect(birthday('生日8月12日')['birthdayMonthDay'], '08月12日');
    expect(birthday('农历生日1996年8月12日')['date'], isNull);
    expect(birthday('农历生日1996年8月12日')['birthdayText'], contains('农历'));
    expect(birthday('生日1996年2月30日')['date'], isNull);
    expect(displayDate('1996-08-12'), '1996年08月12日');
  });
  test('model template is a whitelist, birthday year is checked against quoted facts', () {
    final records = ExtractedRecord.parse(
      jsonEncode({
        'records': [
          {
            'kind': 'note',
            'title': '生日',
            'quote': '我的生日8月12日',
            'date': '2026-08-12',
            'template': 'birthday',
            'fields': [],
          },
        ],
      }),
      '我的生日8月12日',
    );
    expect(records.single.toJson()['date'], isNull);
    expect(records.single.toJson()['birthdayMonthDay'], '08月12日');
    expect(templateFor({'kind': 'phone', 'template': '<script>'}), 'phone');
  });
  testWidgets(
    'birthday shows structured year month day rather than original speech',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordDataView(
              data: {
                'kind': 'note',
                'title': '我的生日',
                'quote': '记住我的生日1996年8月12日',
              },
            ),
          ),
        ),
      );
      expect(find.text('1996年08月12日'), findsOneWidget);
      expect(find.text('记住我的生日1996年8月12日'), findsNothing);
    },
  );
  test('editing updates existing payload without losing associations or source and refreshes reminder', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await Directory.systemTemp.createTemp('record_edit');
    final store = await LocalStore.openAt(root);
    try {
      final repo = RecordRepository(store.database);
      final scheduler = FakeScheduler();
      final service = RecordService(repo, scheduler, (t, n) async => []);
      await repo.insert('source', [
        ExtractedRecord(
          kind: RecordKind.reminder,
          title: '旧标题',
          quote: '提醒开会',
          at: DateTime.now().add(const Duration(days: 1)),
        ),
      ]);
      final id = (await repo.all()).single['id'] as int;
      await service.schedule(id);
      await service.edit(id, {
        'title': '新标题',
        'body': '补充说明',
        'template': 'reminder',
        'at': 'INVALID',
      });
      final row = await repo.get(id);
      final data = jsonDecode(row['payload'] as String);
      expect(data['title'], '新标题');
      expect(data['at'], isNot('INVALID'));
      expect(row['source_id'], 'source');
      expect((await repo.all()).length, 1);
      expect(scheduler.calls, 2);
    } finally {
      await store.database.close();
      await root.delete(recursive: true);
    }
  });
  testWidgets(
    'legacy birthdays render structured cards and editor selects a calendar date',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      late Directory root;
      late LocalStore store;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('legacy_birthday');
        store = await LocalStore.openAt(root);
      });
      try {
        store.notes.add({'text': '我的生日1996年8月12日', 'category': '事项'});
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RecordsView(
                store: store,
                service: RecordService(
                  RecordRepository(store.database),
                  FakeScheduler(),
                  (t, n) async => [],
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('1996年08月12日'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('1996年08月12日'), findsOneWidget);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EditRecordSheet(
                data: {
                  'kind': 'date',
                  'title': '生日',
                  'template': 'birthday',
                  'date': '1996-08-12',
                  'fields': [],
                },
              ),
            ),
          ),
        );
        final dateField = find.byKey(const ValueKey('record-date'));
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: dateField,
                  matching: find.byType(TextField),
                ),
              )
              .readOnly,
          true,
        );
        await tester.tap(dateField);
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        expect(
          tester
              .widget<DatePickerDialog>(find.byType(DatePickerDialog))
              .initialDate,
          DateTime(1996, 8, 12),
        );
        await tester.tap(find.text('15').last);
        await tester.tap(find.text('确定'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(dateField).controller!.text,
          '1996-08-15',
        );
        expect(tester.testTextInput.isVisible, false);
        await tester.tap(dateField);
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(dateField).controller!.text,
          '1996-08-15',
        );
        await tester.tap(find.byTooltip('清除日期'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(dateField).controller!.text,
          isEmpty,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        await tester.runAsync(() async {
          await store.database.close();
          await root.delete(recursive: true);
        });
      }
    },
  );
}
