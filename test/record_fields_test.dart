import 'dart:convert';
import 'dart:io';

import 'package:ai_for_app/records/record_fields.dart';
import 'package:ai_for_app/records/record_templates.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/ui/edit_record_sheet.dart';
import 'package:ai_for_app/ui/record_data_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'records_test.dart' show FakeScheduler;

void main() {
  test(
    'all templates declare required and optional fields with unique keys',
    () {
      for (final template in recordTemplates.keys) {
        final kind = ['birthday', 'date'].contains(template)
            ? 'date'
            : ['image', 'audio'].contains(template)
            ? 'note'
            : template;
        final fields = RecordFields.forRecord({
          'kind': kind,
          'template': template,
        });
        expect(fields.where((f) => f.required), isNotEmpty, reason: template);
        expect(fields.where((f) => !f.required), isNotEmpty, reason: template);
        expect(
          fields.map((f) => f.key).toSet().length,
          fields.length,
          reason: template,
        );
        expect(fields.any((f) => f.key == 'body' && !f.required), true);
        expect(fields.any((f) => f.key == 'category' && !f.required), true);
      }
    },
  );
  test(
    'required fields depend on record type and never include optional details',
    () {
      final complete = [
        {'kind': 'phone', 'title': '张三', 'phone': '13800138000'},
        {
          'kind': 'expense',
          'title': '午饭',
          'amountMinor': 2000,
          'currency': 'CNY',
          'direction': 'expense',
        },
        {'kind': 'date', 'title': '纪念日', 'date': '2026-11-05'},
        {'kind': 'reminder', 'title': '开会', 'at': '2026-11-06T09:00:00+08:00'},
        {'kind': 'task', 'title': '买牛奶'},
        {'kind': 'note', 'title': '随记'},
        {'kind': 'note', 'title': '照片', 'template': 'image'},
        {'kind': 'note', 'title': '录音', 'template': 'audio'},
      ];
      for (final data in complete) {
        expect(RecordFields.missing(data), isEmpty, reason: '$data');
      }
      expect(
        RecordFields.missing({'kind': 'phone', 'title': '电话'}),
        containsAll(['联系人的姓名', '电话号码']),
      );
      expect(
        RecordFields.missing({'kind': 'expense', 'title': '午饭'}).length,
        3,
      );
      expect(
        RecordFields.missing({'kind': 'reminder', 'title': '开会'}).single,
        contains('具体提醒日期和时刻'),
      );
      expect(
        RecordFields.missing({'kind': 'date', 'title': '纪念日'}).single,
        contains('日期'),
      );
      expect(
        RecordFields.missing({'kind': 'task', 'title': ''}).single,
        contains('事项内容'),
      );
    },
  );
  test(
    'birthday year stays optional when month/day or lunar date is supplied',
    () {
      for (final quote in ['我的生日是8月12日', '我的农历生日是五月初三']) {
        final data = {
          'kind': 'date',
          'template': 'birthday',
          'title': '我的生日',
          'quote': quote,
        };
        if (quote.contains('农历')) data['birthdayText'] = '农历五月初三';
        expect(RecordFields.missing(data), isEmpty);
      }
    },
  );
  test(
    'model extras work for all record kinds and still require literal evidence',
    () {
      final fields = [
        {'label': '商户', 'value': '便利店'},
        {'label': '支付方式', 'value': '微信'},
      ];
      const source = '午饭20元，在便利店用微信支付';
      final item = {
        'kind': 'expense',
        'title': '午饭',
        'quote': source,
        'amount': '20',
        'currency': 'CNY',
        'direction': 'expense',
        'category': '餐饮',
        'fields': fields,
      };
      final record = ExtractedRecord.parse(
        jsonEncode({
          'records': [item],
        }),
        source,
      ).single;
      expect(record.fields, fields);
      expect(record.category, '餐饮');
      expect(
        () => ExtractedRecord.parse(
          jsonEncode({
            'records': [
              {
                ...item,
                'fields': [
                  {'label': '商户', 'value': '猜测的店名'},
                ],
              },
            ],
          }),
          source,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'optional facts save and reload while edits cannot clear required fields',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final root = await Directory.systemTemp.createTemp('field_schema');
      final store = await LocalStore.openAt(root);
      try {
        final repo = RecordRepository(store.database);
        final service = RecordService(
          repo,
          FakeScheduler(),
          (text, now) async => [],
        );
        await repo.propose('task', [
          const ExtractedRecord(
            kind: RecordKind.task,
            title: '买牛奶',
            quote: '买牛奶',
          ),
        ], context: '帮我记录买牛奶');
        final id = (await service.saveExplicit('task')).single;
        await service.edit(id, {
          'category': '购物',
          'fields': [
            {'label': '地点', 'value': '超市'},
          ],
        });
        final saved = jsonDecode((await repo.get(id))['payload'] as String);
        expect(saved['fields'].single['value'], '超市');
        expect(saved['category'], '购物');
        await expectLater(service.edit(id, {'title': ''}), throwsStateError);
        expect(
          jsonDecode((await repo.get(id))['payload'] as String)['title'],
          '买牛奶',
        );
      } finally {
        await store.database.close();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'editor labels required fields and saves only populated optional values',
    (tester) async {
      Map<String, dynamic>? patch;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  patch = await showModalBottomSheet<Map<String, dynamic>>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const EditRecordSheet(
                      data: {'kind': 'task', 'title': '买牛奶', 'fields': []},
                    ),
                  );
                },
                child: const Text('编辑'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(find.text('事项内容（必填）'), findsOneWidget);
      expect(find.text('截止日期（选填）'), findsOneWidget);
      await tester.ensureVisible(find.text('更多选填信息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('更多选填信息'));
      await tester.pumpAndSettle();
      final location = find.byKey(const ValueKey('record-extra-地点'));
      await tester.ensureVisible(location);
      await tester.pumpAndSettle();
      await tester.enterText(location, '楼下超市');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存修改'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();
      expect(patch?['date'], isNull);
      expect(patch?['fields'], [
        {'label': '地点', 'value': '楼下超市'},
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordDataView(data: {'kind': 'task', ...patch!}),
          ),
        ),
      );
      expect(find.text('地点：楼下超市'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
