import 'dart:convert';
import 'dart:io';

import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/core/storage_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory parent;
  late Directory root;
  late LocalStore store;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    parent = await Directory.systemTemp.createTemp('model_relocate');
    root = await Directory('${parent.path}/old/Library/Application Support')
        .create(recursive: true);
    store = await LocalStore.openAt(root);
  });
  tearDown(() async {
    await store.database.close();
    await parent.delete(recursive: true);
  });
  Future<void> populate() async {
    final dir = await Directory('${root.path}/models/a')
        .create(recursive: true);
    await File('${dir.path}/model.gguf').writeAsString('GGUFweights');
    await File('${dir.path}/mmproj.gguf').writeAsString('GGUFprojection');
    store.models['a'] = {
      'id': 'a',
      'name': 'model',
      'format': 'gguf',
      'capabilities': ['chat', 'vision'],
      'path': '${dir.path}/model.gguf',
      'projection': '${dir.path}/mmproj.gguf',
      'directory': dir.path,
    };
    store.selected.addAll({'chat': 'a', 'vision': 'a'});
    await Directory('${root.path}/media').create();
    await File('${root.path}/media/photo.jpg').writeAsString('image');
    store.messages.add({
      'role': 'user',
      'text': '保留对话',
      'image': '${root.path}/media/photo.jpg',
    });
  }

  Future<void> relocate() async {
    await store.database.close();
    final newContainer = await Directory('${parent.path}/new').create();
    await Directory('${parent.path}/old/Library')
        .rename('${newContainer.path}/Library');
    root = Directory('${newContainer.path}/Library/Application Support');
    store = await LocalStore.openAt(root);
  }

  test(
    'persisted model paths are relative and work after data container moves',
    () async {
      await populate();
      await store.save();
      final row = (await store.database.query('app_state')).single;
      final saved = jsonDecode(row['payload'] as String);
      expect(saved['models']['a']['path'], 'models/a/model.gguf');
      expect(store.models['a']['path'], startsWith(root.path));
      await relocate();
      expect(
        await File(store.model(ModelRole.chat)!['path'] as String)
            .readAsString(),
        'GGUFweights',
      );
      expect(
        await File(store.models['a']['projection'] as String).exists(),
        isTrue,
      );
      expect(
        await File(store.messages.single['image'] as String).exists(),
        isTrue,
      );
      expect(store.messages.single['text'], '保留对话');
      expect(store.selected, {'chat': 'a', 'vision': 'a'});
    },
  );
  test('legacy absolute model and media paths recover from files in current container', () async {
    await populate();
    await store.database.update(
      'app_state',
      {'payload': jsonEncode(store.data)},
      where: 'id = ?',
      whereArgs: [1],
    );
    await relocate();
    expect(store.models['a']['path'], '${root.path}/models/a/model.gguf');
    expect(store.models['a']['directory'], '${root.path}/models/a');
    final saved = jsonDecode(
      (await store.database.query('app_state')).single['payload'] as String,
    );
    expect(saved['models']['a']['projection'], 'models/a/mmproj.gguf');
    expect(saved['messages'][0]['image'], 'media/photo.jpg');
  });
  test(
    'external model paths are preserved and traversal is never rebased',
    () async {
      final external = await File('${parent.path}/original.gguf')
          .writeAsString('keep');
      store.models['external'] = {'path': external.path};
      store.models['invalid'] = {'path': 'models/../../original.gguf'};
      await StoragePaths(root).restore(store.data);
      expect(store.models['external']['path'], external.path);
      expect(store.models['invalid']['path'], 'models/../../original.gguf');
      final saved = StoragePaths(root).snapshot(store.data);
      expect(saved['models']['external']['path'], external.path);
      expect(await external.readAsString(), 'keep');
    },
  );
  test('legacy reused image becomes context only and survives container relocation', () async {
    await Directory('${root.path}/media').create();
    final path = '${root.path}/media/photo.jpg';
    await File(path).writeAsString('image');
    store.messages.addAll([
      {'role': 'user', 'text': '', 'image': path},
      {
        'role': 'user',
        'text': '刚才图里是什么',
        'image': path,
        'imageContextText': '已识别内容',
      },
    ]);
    await store.save();
    await relocate();
    expect(store.messages.first['image'], isNotNull);
    expect(store.messages.last['image'], isNull);
    expect(store.messages.last['contextImage'], '${root.path}/media/photo.jpg');
    expect(
      await File(store.messages.last['contextImage'] as String).exists(),
      isTrue,
    );
  });
}
