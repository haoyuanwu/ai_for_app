import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_confirmation.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';

import 'records_test.dart' show FakeScheduler;

void main() {
  test('phone requires both a supplied name and a valid number', () {
    for (final title in ['电话', '联系人', '姓名待补充', '13800138000', '', '朋友']) {
      final draft = RecordProposal(1, 'source', 'pending', [
        {'kind': 'phone', 'title': title, 'phone': '13800138000'},
      ], '帮我记录电话13800138000');
      expect(draft.missingFields, contains('联系人的姓名'));
      expect(draft.question, contains('这是谁的电话'));
    }
    final missing = RecordProposal(1, 'source', 'pending', [
      {'kind': 'phone', 'title': '张三', 'phone': ''},
    ], '记录张三电话');
    expect(missing.missingFields, contains('“张三”的电话号码'));
    expect(missing.question, contains('电话号码是多少'));
  });
  test('incomplete phone cannot be directly saved or confirmed, supplemented phone saves', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await Directory.systemTemp.createTemp('phone_required');
    final store = await LocalStore.openAt(root);
    final repo = RecordRepository(store.database);
    final service = RecordService(repo, FakeScheduler(), (t, n) async => []);
    try {
      await repo.propose('phone', [
        const ExtractedRecord(
          kind: RecordKind.phone,
          title: '姓名待补充',
          quote: '记录电话13800138000',
          phone: '13800138000',
        ),
      ], context: '记录电话13800138000');
      expect(await service.saveExplicit('phone'), isEmpty);
      final draft = (await repo.proposals()).single;
      await expectLater(
        service.decide(draft.id, accept: true),
        throwsStateError,
      );
      expect(await repo.all(), isEmpty);
      await repo.revise(draft.id, 'reply', '记录电话13800138000\n张三', [
        const ExtractedRecord(
          kind: RecordKind.phone,
          title: '张三',
          quote: '张三',
          phone: '13800138000',
        ),
      ]);
      expect(await service.saveExplicit('phone'), hasLength(1));
      final row = (await repo.all()).single;
      await expectLater(
        service.edit(row['id'] as int, {'title': '电话'}),
        throwsStateError,
      );
      await expectLater(
        service.edit(row['id'] as int, {'phone': ''}),
        throwsStateError,
      );
    } finally {
      await store.database.close();
      await root.delete(recursive: true);
    }
  });
}
