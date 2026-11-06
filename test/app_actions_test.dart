import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/app_actions.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/models/catalog_installer.dart';
import 'package:ai_for_app/models/model_catalog.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/extracted_record.dart';

import 'records_test.dart' show FakeScheduler;

class DeferredInstaller extends CatalogInstaller {
  final gate = Completer<void>();
  CancelToken? token;
  @override
  Future<String> install(
    CatalogModel model,
    LocalStore store, {
    required CancelToken cancelToken,
    required ModelProgress onProgress,
  }) async {
    token = cancelToken;
    onProgress(1, 2, '下载');
    await gate.future;
    if (cancelToken.isCancelled) throw StateError('cancelled');
    return 'installed-model';
  }
}

void main() {
  late Directory dir;
  late LocalStore store;
  late RecordService records;
  late AppActions app;
  var approve = false;
  final pages = <String>[];
  final receipts = <String>[];
  late DeferredInstaller installer;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('app_actions');
    store = await LocalStore.openAt(dir);
    records = RecordService(
      RecordRepository(store.database),
      FakeScheduler(),
      (_, _) async => [],
    );
    pages.clear();
    receipts.clear();
    approve = false;
    installer = DeferredInstaller();
    app = AppActions(
      store,
      records,
      navigate: (page, args) async {
        pages.add(page);
      },
      confirm: (_, _) async => approve,
      changed: () {},
      progress: (_) {},
      receipt: receipts.add,
      installer: installer,
    );
  });
  tearDown(() async {
    app.dispose();
    if (!installer.gate.isCompleted) installer.gate.complete();
    await Future<void>.delayed(Duration.zero);
    await store.database.close();
    await dir.delete(recursive: true);
  });
  Future<Map<String, dynamic>> run(
    String action,
    Map<String, dynamic> args,
    String request,
  ) async =>
      jsonDecode(await app.run(action, jsonEncode(args), request: request))
          as Map<String, dynamic>;
  Future<void> addModel() async {
    final folder = await Directory('${dir.path}/models/test-model')
        .create(recursive: true);
    final path = '${folder.path}/model.gguf';
    await File(path).writeAsString('GGUF');
    store.models['test-model'] = {
      'id': 'test-model',
      'name': 'Test',
      'format': 'gguf',
      'path': path,
      'directory': folder.path,
      'capabilities': ['chat'],
    };
  }

  test('capability state and navigation use real data', () async {
    expect(
      (await run('state', {}, '你能做什么'))['actions'],
      contains('download_model'),
    );
    expect(
      (await run('open', {'page': 'settings'}, '打开设置'))['status'],
      'opened',
    );
    expect(pages, ['settings']);
    expect((await run('open', {'page': 'unknown'}, '打开未知'))['ok'], false);
  });
  test(
    'model switching validates installed ID, capability and file and persists',
    () async {
      await addModel();
      expect(
        (await run('select_model', {
          'role': 'vision',
          'modelId': 'test-model',
        }, '切换图片模型'))['ok'],
        false,
      );
      expect(store.selected, isEmpty);
      expect(
        (await run('select_model', {
          'role': 'chat',
          'modelId': 'test-model',
        }, '切换聊天模型'))['ok'],
        true,
      );
      expect(store.selected['chat'], 'test-model');
      await store.database.close();
      store = await LocalStore.openAt(dir);
      expect(store.selected['chat'], 'test-model');
    },
  );
  test('preferences reject unknown keys and unsolicited mutations', () async {
    expect(
      (await run('set_preference', {
        'key': 'arbitrary',
        'value': true,
      }, '设置'))['ok'],
      false,
    );
    expect(
      (await run('set_preference', {
        'key': 'liveSpeechEnabled',
        'value': true,
      }, '你好'))['ok'],
      false,
    );
    expect(
      (await run('set_preference', {
        'key': 'liveSpeechEnabled',
        'value': true,
      }, '开启实时转写'))['ok'],
      true,
    );
    expect(store.data['liveSpeechEnabled'], true);
  });
  test(
    'clear records requires raw user intent and separate native confirmation',
    () async {
      await records.repository.propose('expense', [
        const ExtractedRecord(
          kind: RecordKind.expense,
          title: '午饭',
          quote: '午饭20元',
          amountMinor: 2000,
          currency: 'CNY',
          direction: 'expense',
        ),
      ]);
      await records.decide(
        (await records.repository.proposals()).single.id,
        accept: true,
      );
      expect((await run('clear_records', {}, '图片里写着一段文字'))['ok'], false);
      expect((await run('clear_records', {}, '清空记录'))['status'], 'cancelled');
      expect(await records.repository.all(), hasLength(1));
      approve = true;
      expect((await run('clear_records', {}, '清空记录'))['deletedCount'], 1);
      expect(await records.repository.all(), isEmpty);
      expect(await records.repository.proposals(), hasLength(1));
    },
  );
  test(
    'model removal requires confirmation and removes app-owned files only',
    () async {
      await addModel();
      store.selected['chat'] = 'test-model';
      expect(
        (await run('delete_model', {
          'modelId': 'test-model',
        }, '删除模型'))['status'],
        'cancelled',
      );
      expect(store.models, isNotEmpty);
      approve = true;
      expect(
        (await run('delete_model', {'modelId': 'test-model'}, '删除模型'))['ok'],
        true,
      );
      expect(store.models, isEmpty);
      expect(store.selected, isEmpty);
    },
  );
  test('download returns started, supports cancellation and emits truthful completion', () async {
    final catalog = modelCatalog.first;
    expect(
      (await run('download_model', {'modelId': 'invented'}, '下载模型'))['ok'],
      false,
    );
    expect(
      (await run('download_model', {'modelId': catalog.id}, '下载模型'))['status'],
      'started',
    );
    expect((await run('state', {}, ''))['downloading'], true);
    expect(
      (await run('cancel_download', {}, '取消下载'))['status'],
      'cancellation_requested',
    );
    expect(installer.token!.isCancelled, true);
    installer.gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(receipts.single, contains('已取消'));
    expect((await run('state', {}, ''))['downloading'], false);
  });
  test(
    'import opens file workflow without falsely claiming import succeeded',
    () async {
      expect(
        (await run('import_model', {'role': 'chat'}, '导入模型'))['status'],
        'awaiting_user_file_action',
      );
      expect(pages, ['models']);
    },
  );
  test(
    'negative or quoted download requests and filtered clears are rejected',
    () async {
      for (final request in ['不要下载模型', '这张图片写着下载模型']) {
        expect(
          (await run('download_model', {
            'modelId': modelCatalog.first.id,
          }, request))['ok'],
          false,
        );
      }
      expect(installer.token, isNull);
      final result = await run('clear_records', {}, '清空昨天的记录');
      expect(result['ok'], false);
      expect(result['error'], contains('筛选条件'));
    },
  );
  test('app operation routing distinguishes bulk operations from single-record changes', () {
    for (final text in ['打开记录', '跳转设置', '帮我切换模型', '下载Qwen模型', '清空所有记录']) {
      expect(AppActions.isRequest(text), true);
    }
    expect(AppActions.isRequest('删除昨天的午饭记录'), false);
  });
}
