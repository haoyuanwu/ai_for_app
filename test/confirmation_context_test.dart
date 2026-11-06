import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/core/local_context.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/records/record_confirmation.dart';

import 'records_test.dart' show FakeScheduler;

void main() {
  late Directory directory;
  late LocalStore store;
  late RecordRepository repo;
  late RecordService service;
  late FakeScheduler scheduler;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('confirmation');
    store = await LocalStore.openAt(directory);
    repo = RecordRepository(store.database);
    scheduler = FakeScheduler();
    service = RecordService(
      repo,
      scheduler,
      (text, now) async => [
        ExtractedRecord(
          kind: RecordKind.reminder,
          title: '开会',
          quote: text,
          at: now.add(const Duration(days: 1)),
        ),
      ],
    );
  });
  tearDown(() async {
    await store.database.close();
    await directory.delete(recursive: true);
  });
  test(
    'retrieval does not feed assistant thinking traces back into conversation',
    () async {
      store.messages.add({
        'role': 'assistant',
        'status': 'done',
        'text': '<think>秘密露营地点</think>建议带水。',
      });
      final result = jsonDecode(
        await LocalContext(store).seed('露营'),
      ) as Map<String, dynamic>;
      expect(result['relevant'], isEmpty);
      final answer = jsonDecode(
        await LocalContext(store).seed('带水'),
      ) as Map<String, dynamic>;
      expect((answer['relevant'] as List).single['preview'], contains('建议带水'));
      expect(
        (answer['relevant'] as List).single['preview'],
        isNot(contains('秘密露营')),
      );
      expect(store.messages.single['text'], contains('<think>'));
    },
  );
  test('extraction creates durable draft, no formal record or notification until explicit consent', () async {
    await service.extract('m1', '明天九点提醒我开会', DateTime.now());
    expect(await repo.all(), isEmpty);
    expect(scheduler.calls, 0);
    final draft = (await repo.proposals()).single;
    expect(draft.status, 'pending');
    expect(draft.question, contains('要帮你保存下来吗'));
    expect(draft.question, isNot(contains('批')));
    await store.database.close();
    store = await LocalStore.openAt(directory);
    repo = RecordRepository(store.database);
    service = RecordService(
      repo,
      scheduler,
      (text, now) async => throw StateError('must not infer during consent'),
    );
    expect((await repo.proposals()).single.id, draft.id);
    await Future.wait([
      service.decide(draft.id, accept: true),
      service.decide(draft.id, accept: true),
    ]);
    expect((await repo.all()).length, 1);
    expect(scheduler.calls, 1);
    expect((await repo.proposals()).single.status, 'accepted');
  });
  test('rejection never writes records and cannot be resurrected by repeated extraction or confirmation', () async {
    await service.extract('m1', '提醒我', DateTime.now());
    final draft = (await repo.proposals()).single;
    await service.decide(draft.id, accept: false);
    await service.decide(draft.id, accept: true);
    await service.extract('m1', '提醒我', DateTime.now());
    await service.recover();
    expect(await repo.all(), isEmpty);
    expect(scheduler.calls, 0);
    expect((await repo.proposals()).single.status, 'rejected');
  });
  test('consent parser rejects conditional, negated and mixed messages; multiple drafts need a target', () {
    expect(ConfirmationCommand.parse('同意记录！')?.accept, true);
    expect(ConfirmationCommand.parse('不要记录')?.accept, false);
    for (final text in ['如果我说同意记录', '可以，但金额改成20', '不要全部记录，先记录一个', '他说同意记录']) {
      expect(ConfirmationCommand.parse(text), isNull);
    }
    final drafts = [
      RecordProposal(1, 'a', 'pending', [], ''),
      RecordProposal(2, 'b', 'pending', [], ''),
    ];
    expect(ConfirmationCommand.parse('好的')!.resolve(drafts), isEmpty);
    expect(ConfirmationCommand.parse('确认第2批')!.resolve(drafts).single.id, 2);
    expect(ConfirmationCommand.parse('全部记录')!.resolve(drafts).length, 2);
  });
  test('missing fields are filled in conversation before confirmation and retries do not duplicate proposals', () async {
    final future = DateTime.now().add(const Duration(days: 1));
    service = RecordService(
      repo,
      scheduler,
      (text, now) async => [
        ExtractedRecord(kind: RecordKind.reminder, title: '买药', quote: text),
      ],
      refiner: (p, text, now) async => [
        ExtractedRecord(
          kind: RecordKind.reminder,
          title: '买药',
          quote: '${p.context}\n$text',
          at: future,
        ),
      ],
    );
    await service.extract('m1', '提醒我买药', DateTime.now());
    var draft = (await repo.proposals()).single;
    await expectLater(service.decide(draft.id, accept: true), throwsStateError);
    expect(await repo.all(), isEmpty);
    await service.refine(draft, 'm2', '明天上午九点', DateTime.now());
    await service.refine(draft, 'm2', '明天上午九点', DateTime.now());
    draft = (await repo.proposals()).single;
    expect(draft.missingFields, isEmpty);
    expect(draft.context, contains('明天上午九点'));
    await service.decide(draft.id, accept: true);
    expect((await repo.all()).length, 1);
    expect(scheduler.requests.values.single.isAtSameMomentAs(future), true);
  });
  test(
    'custom fields preserve distinct data structure with literal evidence',
    () {
      final parsed = ExtractedRecord.parse(
        jsonEncode({
          'records': [
            {
              'kind': 'note',
              'title': '体重',
              'quote': '今天体重65公斤',
              'category': '健康',
              'fields': [
                {'label': '体重', 'value': '65公斤'},
              ],
            },
          ],
        }),
        '今天体重65公斤',
      );
      expect(parsed.single.fields.single['value'], '65公斤');
      final phone = ExtractedRecord.parse(
        jsonEncode({
          'records': [
            {'kind': 'phone', 'title': '张三', 'quote': '张三电话', 'phone': null},
          ],
        }),
        '张三电话',
      ).single;
      expect(
        RecordProposal(1, 'phone', 'pending', [
          phone.toJson(),
        ], '张三电话').missingFields.single,
        contains('电话号码'),
      );
      expect(recordPreview(parsed.single.toJson()), contains('体重：65公斤'));
      expect(
        () => ExtractedRecord.parse(
          jsonEncode({
            'records': [
              {
                'kind': 'note',
                'title': '体重',
                'quote': '今天体重65公斤',
                'fields': [
                  {'label': '体重', 'value': '70公斤'},
                ],
              },
            ],
          }),
          '今天体重65公斤',
        ),
        throwsFormatException,
      );
    },
  );
  test('read tools expose all old conversations and every record with paging and complete detail, without writes', () async {
    for (var i = 0; i < 18; i++) {
      store.messages.add({
        'role': 'user',
        'text': i == 0 ? '张三电话13800138000' : '消息$i',
        'status': 'done',
      });
      await repo.insert('record$i', [
        ExtractedRecord(kind: RecordKind.task, title: '事项$i', quote: '事项$i'),
      ]);
    }
    store.notes.add({'text': '收藏原文'});
    final memory = LocalContext(store);
    final old = jsonDecode(await memory.page('history', '张三', 0));
    expect(old['total'], 1);
    expect(old['items'].single['preview'], contains('13800138000'));
    final first = jsonDecode(await memory.page('records', '', 0));
    expect(first['total'], 18);
    expect(first['nextOffset'], 5);
    final last = jsonDecode(await memory.page('records', '', 15));
    expect(last['items'].length, 3);
    expect(last['nextOffset'], isNull);
    final detail = jsonDecode(await memory.detail('history', 0, 0));
    expect(detail['content'], contains('张三'));
    final seed = jsonDecode(await memory.seed('张三电话'));
    expect(seed['counts']['records'], 18);
    expect(seed['relevant'].toString(), contains('13800138000'));
    await expectLater(
      memory.page('DROP TABLE records', '', 0),
      throwsArgumentError,
    );
    expect((await repo.all()).length, 18);
    final longText = '长内容' * 1200;
    store.messages.add({'role': 'user', 'text': longText, 'status': 'done'});
    var offset = 0;
    var rebuilt = '';
    while (true) {
      final chunk = jsonDecode(await memory.detail('history', 18, offset));
      rebuilt += chunk['content'] as String;
      if (chunk['nextOffset'] == null) break;
      offset = chunk['nextOffset'] as int;
    }
    expect(jsonDecode(rebuilt)['text'], longText);
  });
  test('v2 migration keeps existing records and introduces empty confirmation queue', () async {
    final oldDir = await Directory.systemTemp.createTemp('v2_migration');
    final old = await openDatabase(
      '${oldDir.path}/local_ai.db',
      version: 2,
      onCreate: (db, v) async {
        await db.execute(
          'CREATE TABLE app_state (id INTEGER PRIMARY KEY,payload TEXT NOT NULL)',
        );
        await RecordRepository.create(db);
      },
    );
    await RecordRepository(old).insert('old', [
      const ExtractedRecord(kind: RecordKind.task, title: '旧事项', quote: '旧事项'),
    ]);
    await old.close();
    final upgraded = await LocalStore.openAt(oldDir);
    expect((await RecordRepository(upgraded.database).all()).length, 1);
    expect(await RecordRepository(upgraded.database).proposals(), isEmpty);
    await upgraded.database.close();
    await oldDir.delete(recursive: true);
  });
}
