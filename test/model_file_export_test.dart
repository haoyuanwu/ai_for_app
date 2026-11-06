import 'dart:io';

import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/models/model_file_export.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalStore store;
  const channel = MethodChannel('flutter_file_dialog');
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('file_export');
    store = await LocalStore.openAt(root);
    final dir = await Directory('${root.path}/models/a')
        .create(recursive: true);
    await File('${dir.path}/model.gguf').writeAsString('GGUFdata');
    store.models['a'] = {
      'name': '模型 A',
      'format': 'gguf',
      'path': '${dir.path}/model.gguf',
      'capabilities': ['chat'],
    };
    store.selected['chat'] = 'a';
    await store.save();
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await store.database.close();
    await root.delete(recursive: true);
  });
  for (final mode in ['saved', 'cancelled', 'failed']) {
    test(
      'file export $mode keeps source and waits before cleaning temporary package',
      () async {
        String? temp;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'saveFile');
              final params = call.arguments as Map;
              expect(params['data'], isNull);
              temp = params['sourceFilePath'] as String;
              expect(await File(temp!).exists(), isTrue);
              await Future<void>.delayed(const Duration(milliseconds: 30));
              expect(await File(temp!).exists(), isTrue);
              if (mode == 'failed') throw PlatformException(code: 'disk_full');
              return mode == 'cancelled' ? null : '/phone/model.zip';
            });
        final future = exportModelToFiles(store, 'a', temporaryDirectory: root);
        if (mode == 'failed') {
          await expectLater(future, throwsA(isA<PlatformException>()));
        } else {
          expect(await future, mode == 'saved' ? '/phone/model.zip' : isNull);
        }
        expect(temp, isNotNull);
        expect(await File(temp!).exists(), isFalse);
        expect(
          await File(store.models['a']['path'] as String).exists(),
          isTrue,
        );
        expect(store.selected['chat'], 'a');
      },
    );
  }
}
