import 'dart:io';

import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/models/model_package.dart';
import 'package:ai_for_app/models/speech_bundle.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'model_deletion_test.dart' show FailingSaveStore;

void main() {
  late Directory root;
  late LocalStore store;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('model_package');
    store = await LocalStore.openAt(root);
  });
  tearDown(() async {
    await store.database.close();
    await root.delete(recursive: true);
  });
  Future<void> gguf() async {
    final dir = await Directory('${root.path}/models/model')
        .create(recursive: true);
    await File('${dir.path}/main.gguf').writeAsString('GGUFmodel-data');
    await File('${dir.path}/projector.gguf')
        .writeAsString('GGUFprojection-data');
    store.models['model'] = {
      'name': 'Qwen3.5 0.8B',
      'format': 'gguf',
      'capabilities': ['chat', 'vision'],
      'path': '${dir.path}/main.gguf',
      'projection': '${dir.path}/projector.gguf',
      'directory': dir.path,
    };
    store.messages.add({'text': '聊天不会导出'});
    await store.save();
  }

  test('full GGUF export/import retains both assets without exporting chats or absolute paths', () async {
    await gguf();
    final file = await ModelPackage.create(
      store,
      'model',
      File('${root.path}/backup.zip'),
    );
    final input = InputFileStream(file.path);
    final archive = ZipDecoder().decodeStream(input);
    final manifest = String.fromCharCodes(
      archive.findFile('model-package.json')!.content,
    );
    expect(manifest, isNot(contains(root.path)));
    expect(archive.length, 3);
    await input.close();
    final id = await ModelPackage.import(store, file.path);
    final model = store.models[id];
    expect(
      await File(model['path'] as String).readAsString(),
      'GGUFmodel-data',
    );
    expect(
      await File(model['projection'] as String).readAsString(),
      'GGUFprojection-data',
    );
    expect(model['capabilities'], ['chat', 'vision']);
    expect(store.messages.single['text'], '聊天不会导出');
  });
  for (final format in ['sensevoice', 'qwen3asr']) {
    test(
      'speech $format exports and imports tokenizer directory structure',
      () async {
        final folder = '${root.path}/models/speech';
        for (final name in SpeechBundle.filesFor(format)) {
          final file = File('$folder/$name');
          await file.parent.create(recursive: true);
          await file.writeAsString('fixture');
        }
        store.models['speech'] = {
          'name': format,
          'format': format,
          'path': folder,
          'directory': folder,
          'capabilities': ['speech'],
          'quantization': 'int8',
        };
        final zip = await ModelPackage.create(
          store,
          'speech',
          File('${root.path}/speech.zip'),
        );
        final id = await ModelPackage.import(store, zip.path);
        final model = store.models[id];
        expect(model['format'], format);
        expect(model['quantization'], 'int8');
        for (final name in SpeechBundle.filesFor(format)) {
          expect(await File("${model['path']}/$name").exists(), isTrue);
        }
        expect(store.selected['speech'], id);
      },
    );
  }
  test(
    'unsafe ZIP paths are rejected before extraction or registration',
    () async {
      final archive = Archive()
        ..addFile(ArchiveFile('../outside.gguf', 4, [71, 71, 85, 70]));
      final file = File('${root.path}/unsafe.zip');
      await file.writeAsBytes(ZipEncoder().encode(archive));
      await expectLater(
        ModelPackage.import(store, file.path),
        throwsFormatException,
      );
      expect(store.models, isEmpty);
      expect(await Directory('${root.path}/models').list().toList(), isEmpty);
      expect(await File('${root.parent.path}/outside.gguf').exists(), isFalse);
    },
  );
  test('failed model package persistence restores selections and removes partial assets', () async {
    await gguf();
    final file = await ModelPackage.create(
      store,
      'model',
      File('${root.path}/backup.zip'),
    );
    store.selected['chat'] = 'model';
    final failing = FailingSaveStore(root)..data = store.data;
    await expectLater(
      ModelPackage.import(failing, file.path),
      throwsStateError,
    );
    expect(store.models.keys, ['model']);
    expect(store.selected, {'chat': 'model'});
    expect((await Directory('${root.path}/models').list().toList()).length, 1);
  });
}
