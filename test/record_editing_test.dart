import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/record_editing.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/records/extracted_record.dart';

import 'records_test.dart' show FakeScheduler;

void main() {
  test('conversation edits require lookup, validate new value and update original only', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await Directory.systemTemp.createTemp('chat_edit');
    final store = await LocalStore.openAt(root);
    try {
      final repo = RecordRepository(store.database);
      final service = RecordService(repo, FakeScheduler(), (t, n) async => []);
      await repo.insert('original', [
        const ExtractedRecord(
          kind: RecordKind.expense,
          title: '午饭',
          quote: '午饭20元',
          amountMinor: 2000,
          currency: 'CNY',
          direction: 'expense',
        ),
      ]);
      final id = (await repo.all()).single['id'] as int;
      final receipts = <String>[];
      final edit = RecordEditing(
        store,
        '把午饭金额改成25元',
        service,
        onSaved: receipts.add,
      );
      expect(
        jsonDecode(await edit.edit(id, 'amount', '25'))['updated'],
        isFalse,
      );
      await edit.page('records', '午饭', 0);
      await expectLater(edit.edit(id, 'amount', '250'), throwsFormatException);
      expect(
        jsonDecode(await edit.edit(id, 'amount', '25'))['updated'],
        isTrue,
      );
      final row = await repo.get(id);
      expect(row['source_id'], 'original');
      expect(jsonDecode(row['payload'] as String)['amountMinor'], 2500);
      expect((await repo.all()).length, 1);
      expect(receipts.single, contains('25.00'));
      await expectLater(
        edit.edit(id, 'date', '2026-02-30'),
        throwsFormatException,
      );
    } finally {
      await store.database.close();
      await root.delete(recursive: true);
    }
  });
}
