import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/models/model_library.dart';
import 'package:ai_for_app/ui/models_page.dart';

class FailingSaveStore extends LocalStore {
  FailingSaveStore(super.root);
  @override
  Future<void> save() async => throw StateError('disk unavailable');
}

void main() {
  late Directory root;
  late LocalStore store;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('model_delete');
    store = await LocalStore.openAt(root);
  });
  tearDown(() async {
    await store.database.close();
    await root.delete(recursive: true);
  });
  Future<Directory> register(String id, {bool whisper = false}) async {
    final dir = await Directory('${root.path}/models/$id')
        .create(recursive: true);
    final path = whisper ? '${dir.path}/whisper/nested' : dir.path;
    await Directory(path).create(recursive: true);
    await File('$path/${whisper ? 'encoder.onnx' : 'model.gguf'}')
        .writeAsString('sample');
    await File('${dir.path}/mmproj.gguf').writeAsString('projection');
    store.models[id] = {
      'id': id,
      'name': id,
      'path': whisper ? path : '$path/model.gguf',
      'projection': '${dir.path}/mmproj.gguf',
      'capabilities': ['chat', 'vision'],
      'format': whisper ? 'whisper' : 'gguf',
    };
    return dir;
  }

  test('deleting a shared-function model clears every assignment and all companion files, preserving records and originals', () async {
    final dir = await register('shared');
    await register('other');
    final original = await File('${root.path}/original.gguf')
        .writeAsString('original');
    store.selected.addAll({
      'chat': 'shared',
      'vision': 'shared',
      'speech': 'other',
    });
    store.messages.add({'text': '历史对话'});
    store.notes.add({'text': '收藏'});
    await store.save();
    final result = await ModelLibrary(store).delete('shared');
    expect(result.warning, isNull);
    expect(await dir.exists(), false);
    expect(await original.exists(), true);
    expect(store.models.keys, ['other']);
    expect(store.selected, {'speech': 'other'});
    expect(store.messages.single['text'], '历史对话');
    expect(store.notes.length, 1);
    await store.database.close();
    store = await LocalStore.openAt(root);
    expect(store.models.containsKey('shared'), false);
    expect(store.selected, {'speech': 'other'});
  });
  test('legacy imported Whisper directories and nested files are removed without explicit directory metadata', () async {
    final dir = await register('whisper', whisper: true);
    await ModelLibrary(store).delete('whisper');
    expect(await dir.exists(), false);
  });
  test(
    'shared physical files referenced by another entry are retained',
    () async {
      final dir = await register('shared');
      store.models['alias'] = {
        ...store.models['shared'] as Map<String, dynamic>,
        'id': 'alias',
      };
      final result = await ModelLibrary(store).delete('shared');
      expect(result.filesRemoved, false);
      expect(await dir.exists(), true);
      expect(store.models.containsKey('alias'), true);
    },
  );
  test(
    'a missing file can still be unregistered and deletion is idempotent',
    () async {
      store.models['missing'] = {
        'name': 'missing',
        'path': '${root.path}/models/missing/model.gguf',
      };
      store.selected['chat'] = 'missing';
      await ModelLibrary(store).delete('missing');
      await ModelLibrary(store).delete('missing');
      expect(store.models, isEmpty);
      expect(store.selected, isEmpty);
    },
  );
  test(
    'failed persistence keeps registration, assignments and files intact',
    () async {
      final dir = await register('keep');
      final failing = FailingSaveStore(root)..data = store.data;
      store.selected['chat'] = 'keep';
      await expectLater(ModelLibrary(failing).delete('keep'), throwsStateError);
      expect(failing.models.containsKey('keep'), true);
      expect(failing.selected['chat'], 'keep');
      expect(await dir.exists(), true);
    },
  );
  test('symlink escapes never delete external files and failed cleanup survives restart and retries', () async {
    final outside = await Directory.systemTemp.createTemp('outside_model');
    try {
      final original = await File('${outside.path}/private.gguf')
          .writeAsString('keep');
      await Directory('${root.path}/models').create();
      await Link('${root.path}/models/unsafe').create(outside.path);
      store.models['unsafe'] = {
        'name': 'unsafe',
        'path': '${root.path}/models/unsafe/private.gguf',
      };
      final result = await ModelLibrary(store).delete('unsafe');
      expect(result.warning, isNotNull);
      expect(await original.exists(), true);
      await store.database.close();
      store = await LocalStore.openAt(root);
      expect(store.data['modelCleanup'], contains('unsafe'));
      await Link('${root.path}/models/unsafe').delete();
      await Directory('${root.path}/models/unsafe').create();
      await ModelLibrary(store).cleanupFiles();
      expect(store.data['modelCleanup'], isEmpty);
      expect(await Directory('${root.path}/models/unsafe').exists(), false);
      expect(await original.exists(), true);
    } finally {
      await outside.delete(recursive: true);
    }
  });
  test('symlinks inside a model directory are unlinked without following their targets', () async {
    final dir = await register('safe');
    final original = await File('${root.path}/outside.gguf')
        .writeAsString('keep');
    await Link('${dir.path}/linked.gguf').create(original.path);
    await ModelLibrary(store).delete('safe');
    expect(await original.exists(), true);
  });
  testWidgets(
    'deletion requires review and the user can cancel or confirm in the model library',
    (tester) async {
      await tester.runAsync(() async {
        await register('shared');
        store.selected.addAll({'chat': 'shared', 'vision': 'shared'});
        await store.save();
      });
      await tester.pumpWidget(MaterialApp(home: ModelsPage(store: store)));
      await tester.tap(find.byTooltip('删除模型'));
      await tester.pumpAndSettle();
      expect(find.textContaining('文字对话、图片识别'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.models.containsKey('shared'), true);
      await tester.tap(find.byTooltip('删除模型'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除模型'));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(store.models, isEmpty);
      expect(store.selected, isEmpty);
      expect(find.byTooltip('删除模型'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
