import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/reminder_time.dart';
import 'package:ai_for_app/records/reminder_notifications.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';

class FakeScheduler implements ReminderScheduler {
  final requests = <int, DateTime>{};
  bool denied = false, failCancel = false;
  int calls = 0;
  @override
  Future<String> schedule(
    int id,
    String title,
    DateTime at, {
    bool requestPermission = true,
  }) async {
    calls++;
    if (denied) throw StateError('permission denied');
    requests[id] = at;
    return 'scheduled_inexact';
  }

  @override
  Future<void> cancel(int id) async {
    if (failCancel) throw StateError('cancel failed');
    requests.remove(id);
  }
}

String response(List<Map<String, dynamic>> items) =>
    jsonEncode({'records': items});
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  final reference = DateTime(2026, 11, 4, 14);
  test(
    'one payment screenshot proposes multiple expenses and waits for consent',
    () async {
      final root = await Directory.systemTemp.createTemp('receipt_records');
      final store = await LocalStore.openAt(root);
      try {
        final repository = RecordRepository(store.database);
        const source =
            '图片识别结果：微信支付\n早餐店 -8.50元 支付成功\n书店 -20.00元 支付成功\n合计28.50元';
        final service = RecordService(repository, FakeScheduler(), (
          text,
          now,
        ) async {
          return ExtractedRecord.parse(
            response([
              {
                'kind': 'expense',
                'title': '早餐店',
                'quote': '早餐店 -8.50元 支付成功',
                'amount': '8.50',
                'currency': 'CNY',
                'direction': 'expense',
              },
              {
                'kind': 'expense',
                'title': '书店',
                'quote': '书店 -20.00元 支付成功',
                'amount': '20.00',
                'currency': 'CNY',
                'direction': 'expense',
              },
            ]),
            text,
            reference: now,
          );
        });
        await repository.propose('screenshot', [], context: source);
        await repository.retryEmptyExtraction('screenshot');
        expect(await service.extract('screenshot', source, reference), 2);
        final proposal = (await repository.proposals()).single;
        expect(proposal.status, 'pending');
        expect(proposal.items.map((item) => item['amountMinor']), [850, 2000]);
        expect(await service.saveExplicit('screenshot'), isEmpty);
        await service.extract('ocr-consent', '$source\n帮我记账', reference);
        expect(
          await service.saveExplicit('ocr-consent', intentText: ''),
          isEmpty,
        );

        expect(await store.database.query('records'), isEmpty);
        expect(await service.decide(proposal.id, accept: true), hasLength(2));
        await repository.retryEmptyExtraction('screenshot');
        expect(await service.extract('screenshot', source, reference), 0);
        expect(await store.database.query('records'), hasLength(2));
      } finally {
        await store.database.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'validates five types, original evidence, and exact decimal minor units',
    () {
      const source = '明天上午九点提醒我开会。张三电话13800138000。今天午饭花了12.50元。周五有会议。待办买牛奶。';
      final list = ExtractedRecord.parse(
        response([
          {
            'kind': 'reminder',
            'title': '开会',
            'quote': '明天上午九点提醒我开会',
            'datetime': '2026-11-05T09:00:00+08:00',
          },
          {
            'kind': 'phone',
            'title': '张三',
            'quote': '张三电话13800138000',
            'phone': '13800138000',
          },
          {
            'kind': 'expense',
            'title': '午饭',
            'quote': '今天午饭花了12.50元',
            'amount': '12.50',
            'currency': 'CNY',
            'direction': 'expense',
          },
          {
            'kind': 'date',
            'title': '会议',
            'quote': '周五有会议',
            'date': '2026-11-06',
            'datetime': null,
          },
          {'kind': 'task', 'title': '买牛奶', 'quote': '待办买牛奶'},
        ]),
        source,
        reference: reference,
      );
      expect(list.length, 5);
      expect(list[0].at, DateTime(2026, 11, 5, 9));
      expect(list[2].amountMinor, 1250);
      expect(list[3].date, '2026-11-06');
      expect(
        () => ExtractedRecord.parse(
          response([
            {'kind': 'task', 'title': '假的', 'quote': '用户没说过'},
          ]),
          source,
        ),
        throwsFormatException,
      );
      expect(
        () => ExtractedRecord.parse('not json', source),
        throwsFormatException,
      );
      expect(
        () => ExtractedRecord.parse(
          response([
            {
              'kind': 'phone',
              'title': '张三',
              'quote': '张三电话13800138000',
              'phone': '13900139000',
            },
          ]),
          source,
        ),
        throwsFormatException,
      );
    },
  );
  test('vague and recurring reminders cannot acquire an invented time', () {
    for (final quote in ['明天提醒我买药', '每天下午三点提醒我喝水', '明天三点左右提醒我开会']) {
      final r = ExtractedRecord.parse(
        response([
          {
            'kind': 'reminder',
            'title': '事项',
            'quote': quote,
            'datetime': '2026-11-05T09:00:00+08:00',
          },
        ]),
        quote,
        reference: reference,
      );
      expect(r.single.at, isNull);
    }
    expect(
      resolveReminderTime('三十分钟后提醒我', reference),
      reference.add(const Duration(minutes: 30)),
    );
    expect(
      resolveReminderTime('明天晚上八点半提醒我', reference),
      DateTime(2026, 11, 5, 20, 30),
    );
    expect(
      resolveReminderTime('11月5日14:30提醒我', reference),
      DateTime(2026, 11, 5, 14, 30),
    );
    expect(
      resolveReminderTime('下周一上午十点提醒我', reference),
      DateTime(2026, 11, 9, 10),
    );
    expect(resolveReminderTime('2月30日九点提醒我', reference), isNull);
  });
  test('rejects invalid dates and avoids negative intent, hypothetical money and invented amount', () {
    expect(
      () => ExtractedRecord.parse(
        response([
          {
            'kind': 'date',
            'title': '错误日期',
            'quote': '2月30日',
            'datetime': '2026-02-30T09:00:00+08:00',
          },
        ]),
        '2月30日',
      ),
      throwsFormatException,
    );
    expect(
      ExtractedRecord.parse(
        response([
          {'kind': 'reminder', 'title': '不要', 'quote': '不用提醒我买药'},
        ]),
        '不用提醒我买药',
      ),
      isEmpty,
    );
    expect(
      ExtractedRecord.parse(
        response([
          {
            'kind': 'expense',
            'title': '预算',
            'quote': '预算花200元',
            'amount': '200',
          },
        ]),
        '预算花200元',
      ),
      isEmpty,
    );
    final r = ExtractedRecord.parse(
      response([
        {
          'kind': 'expense',
          'title': '午饭',
          'quote': '午饭花了12元',
          'amount': '120',
          'currency': 'CNY',
          'direction': 'expense',
        },
      ]),
      '午饭花了12元',
    );
    expect(r.single.amountMinor, isNull);
  });
  group('SQLite record lifecycle', () {
    late Directory directory;
    late LocalStore store;
    late RecordRepository repo;
    late FakeScheduler scheduler;
    late RecordService service;
    late List<ExtractedRecord> proposals;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('records_test');
      store = await LocalStore.openAt(directory);
      repo = RecordRepository(store.database);
      scheduler = FakeScheduler();
      proposals = [
        ExtractedRecord(
          kind: RecordKind.reminder,
          title: '买药',
          quote: '明天提醒我买药',
          at: DateTime.now().add(const Duration(days: 1)),
        ),
      ];
      service = RecordService(repo, scheduler, (text, now) async => proposals);
    });
    Future<void> approvePending() async {
      for (final p in await repo.proposals()) {
        if (p.status == 'pending' && p.missingFields.isEmpty) {
          await service.decide(p.id, accept: true);
        }
      }
    }

    tearDown(() async {
      await store.database.close();
      await directory.delete(recursive: true);
    });
    test('repeated and concurrent extraction is idempotent, status survives reopening', () async {
      await Future.wait([
        service.extract('m1', '原文', DateTime.now()),
        service.extract('m1', '原文', DateTime.now()),
      ]);
      expect(await repo.all(), isEmpty);
      expect(scheduler.calls, 0);
      await approvePending();
      expect((await repo.all()).length, 1);
      expect(scheduler.requests.length, 1);
      final id = (await repo.all()).single['id'] as int;
      expect((await repo.get(id))['status'], 'scheduled_inexact');
      await store.database.close();
      store = await LocalStore.openAt(directory);
      expect(
        (await RecordRepository(store.database).all()).single['status'],
        'scheduled_inexact',
      );
    });
    test(
      'permission denial, retry, time editing, cancellation and deletion',
      () async {
        scheduler.denied = true;
        await service.extract('m1', '原文', DateTime.now());
        await approvePending();
        final id = (await repo.all()).single['id'] as int;
        expect((await repo.get(id))['status'], 'failed');
        expect(scheduler.requests, isEmpty);
        scheduler.denied = false;
        await service.schedule(id);
        final time = DateTime.now().add(const Duration(days: 2));
        await service.changeTime(id, time);
        expect(scheduler.requests[id]!.isAtSameMomentAs(time), isTrue);
        await service.cancel(id);
        await service.recover();
        expect(scheduler.requests, isEmpty);
        expect((await repo.get(id))['status'], 'cancelled');
        await service.delete(id);
        expect(await repo.all(), isEmpty);
        expect(
          await service.extract('m1', '原文', DateTime.now()),
          0,
        ); // deletion does not resurrect a source
      },
    );
    test(
      'vague and past reminders do not schedule; crashed pending work recovers',
      () async {
        proposals = [
          const ExtractedRecord(
            kind: RecordKind.reminder,
            title: '待定',
            quote: '明天提醒我',
          ),
          ExtractedRecord(
            kind: RecordKind.reminder,
            title: '已过',
            quote: '昨天',
            at: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ];
        await service.extract('m1', '原文', DateTime.now());
        await approvePending();
        expect(scheduler.calls, 0);
        expect(await repo.all(), isEmpty);
        final draft = (await repo.proposals()).single;
        expect(draft.missingFields, isNotEmpty);
        await expectLater(
          service.decide(draft.id, accept: true),
          throwsStateError,
        );
        await repo.insert('m2', [
          ExtractedRecord(
            kind: RecordKind.reminder,
            title: '恢复',
            quote: '明天九点',
            at: DateTime.now().add(const Duration(days: 1)),
          ),
        ]);
        await service.recover();
        expect(scheduler.requests.length, 1);
      },
    );
    test('failed extraction is retryable; failed cancellation cannot delete or reschedule', () async {
      var fail = true;
      service = RecordService(repo, scheduler, (text, now) async {
        if (fail) throw const FormatException('bad model output');
        return proposals;
      });
      await expectLater(
        service.extract('m1', '原文', DateTime.now()),
        throwsFormatException,
      );
      expect(await repo.hasExtracted('m1'), false);
      fail = false;
      await service.extract('m1', '原文', DateTime.now());
      await approvePending();
      final id = (await repo.all()).single['id'] as int;
      scheduler.failCancel = true;
      await expectLater(service.delete(id), throwsStateError);
      expect((await repo.get(id))['status'], 'cancel_failed');
      scheduler.failCancel = false;
      await service.recover();
      expect((await repo.get(id))['status'], 'cancelled');
      expect(scheduler.requests, isEmpty);
    });
  });
  test(
    'version 1 database upgrades without losing model or conversation data',
    () async {
      final dir = await Directory.systemTemp.createTemp('migration_test');
      final old = await openDatabase(
        '${dir.path}/local_ai.db',
        version: 1,
        onCreate: (db, v) async {
          await db.execute(
            'CREATE TABLE app_state (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)',
          );
          await db.insert('app_state', {
            'id': 1,
            'payload': jsonEncode({
              'models': {},
              'selected': {},
              'messages': [
                {'text': '旧消息'},
              ],
              'notes': [],
            }),
          });
        },
      );
      await old.close();
      final store = await LocalStore.openAt(dir);
      expect(store.messages.single['text'], '旧消息');
      expect(await RecordRepository(store.database).all(), isEmpty);
      await store.database.close();
      await dir.delete(recursive: true);
    },
  );
}
