import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/models/model_catalog.dart';
import 'package:ai_for_app/models/catalog_installer.dart';

class FakeFiles implements HttpClientAdapter {
  FakeFiles(this.files);
  final Map<String, List<int>> files;
  int calls = 0;
  void Function(int)? onFetch;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    onFetch?.call(calls);
    final bytes = files[options.uri.pathSegments.last];
    return ResponseBody.fromBytes(
      bytes ?? [],
      bytes == null ? 404 : 200,
      headers: {
        Headers.contentLengthHeader: ['${bytes?.length ?? 0}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory directory;
  late LocalStore store;
  late FakeFiles adapter;
  late Dio dio;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('catalog_test');
    store = await LocalStore.openAt(directory);
    adapter = FakeFiles({
      'main.gguf': utf8.encode('GGUFsample'),
      'mmproj.gguf': utf8.encode('GGUFprojection'),
      'config.json': utf8.encode('{}'),
    });
    dio = Dio()..httpClientAdapter = adapter;
  });
  tearDown(() async {
    dio.close();
    await store.database.close();
    await directory.delete(recursive: true);
  });
  CatalogModel sample({bool speech = false}) => CatalogModel(
    id: 'test-model',
    name: 'Sample',
    repo: 'owner/repo',
    revision: '123',
    format: speech ? 'whisper' : 'gguf',
    capabilities: speech ? ['speech'] : ['chat', 'vision'],
    description: 'test',
    variant: 'test',
    quantization: speech ? 'int8' : null,
    files: [
      for (final name
          in speech ? ['config.json'] : ['main.gguf', 'mmproj.gguf'])
        CatalogFile(
          path: name,
          bytes: adapter.files[name]!.length,
          sha256: sha256.convert(adapter.files[name]!).toString(),
        ),
    ],
  );
  test('catalog contains only domestic vendors with pinned sources and paired projection', () {
    expect(modelCatalog.length, 13);
    expect(
      modelCatalog.any(
        (m) => {
          'qwen3-06b-q4',
          'qwen3-17b-q8',
          'qwen3-4b-q4',
          'qwen3-8b-q4',
        }.contains(m.id),
      ),
      isFalse,
    );
    expect(
      modelCatalog
          .where((m) => m.id.startsWith('qwen35-'))
          .map((m) => m.name)
          .toSet(),
      {'Qwen3.5 0.8B', 'Qwen3.5 2B', 'Qwen3.5 4B', 'Qwen3.5 9B'},
    );
    expect(
      modelCatalog.map((m) => m.vendor).toSet(),
      equals({
        '阿里 · Qwen',
        '面壁智能 · MiniCPM',
        '阿里 · FunAudioLLM',
        'DeepSeek',
        '小米 · MiMo',
      }),
    );
    expect(
      modelCatalog.singleWhere((m) => m.id == 'mimo-7b-rl-q4').highMemory,
      isTrue,
    );
    expect(modelCatalog.map((m) => m.id).toSet().length, modelCatalog.length);
    for (final model in modelCatalog) {
      expect(model.revision, matches(RegExp(r'^[a-f0-9]{40}$')));
      expect(
        model.files.every((f) => f.bytes > 0 && f.sha256.length == 64),
        isTrue,
      );
      expect(model.downloadUrl(model.files.first).scheme, 'https');
      if (model.capabilities.contains('vision')) {
        expect(model.files.any((f) => f.path.startsWith('mmproj')), isTrue);
      }
    }
    expect(
      modelCatalog
          .where((m) => m.capabilities.contains('speech'))
          .map((m) => m.format)
          .toSet(),
      {'sensevoice', 'qwen3asr'},
    );
    expect(
      modelCatalog.map((m) => m.id),
      containsAll([
        'qwen35-4b-q4',
        'minicpm5-2b-q4',
        'qwen3vl-4b-q4',
        'minicpmv-47-1b-q4',
      ]),
    );
  });
  test(
    'domestic ASR installs a complete local bundle and selects speech only',
    () async {
      adapter.files.addAll({
        'model.int8.onnx': utf8.encode('onnx fixture'),
        'tokens.txt': utf8.encode('token 1'),
      });
      final model = CatalogModel(
        id: 'test-sense',
        name: 'SenseVoice',
        repo: 'owner/repo',
        revision: '123',
        format: 'sensevoice',
        capabilities: ['speech'],
        description: 'test',
        variant: 'int8',
        files: [
          for (final name in ['model.int8.onnx', 'tokens.txt'])
            CatalogFile(
              path: name,
              bytes: adapter.files[name]!.length,
              sha256: sha256.convert(adapter.files[name]!).toString(),
            ),
        ],
      );
      final id = await CatalogInstaller(dio: dio).install(
        model,
        store,
        cancelToken: CancelToken(),
        onProgress: (_, total, phase) {},
      );
      final config = store.models[id];
      expect(config['path'], config['directory']);
      expect(config['format'], 'sensevoice');
      expect(store.selected, {'speech': id});
      expect(
        await File("${config['path']}/tokens.txt").readAsString(),
        'token 1',
      );
    },
  );
  test('installs all files, shares one library entry across capabilities, persists and avoids duplicates', () async {
    final install = CatalogInstaller(dio: dio);
    final progress = <int>[];
    final id = await install.install(
      sample(),
      store,
      cancelToken: CancelToken(),
      onProgress: (done, total, phase) => progress.add(done),
    );
    expect(adapter.calls, 2);
    expect(store.selected['chat'], id);
    expect(store.selected['vision'], id);
    expect(store.model(ModelRole.chat), same(store.model(ModelRole.vision)));
    expect(
      await File(store.models[id]['projection'] as String).exists(),
      isTrue,
    );
    expect(progress.last, sample().bytes);
    await install.install(
      sample(),
      store,
      cancelToken: CancelToken(),
      onProgress: (_, _, _) {},
    );
    expect(adapter.calls, 2);
    expect(store.models.length, 1);
    await store.database.close();
    store = await LocalStore.openAt(directory);
    expect(store.selected['vision'], id);
  });
  test('a failed projection download leaves no model or partial directory and can retry', () async {
    final model = sample();
    adapter.files.remove('mmproj.gguf');
    final install = CatalogInstaller(dio: dio);
    await expectLater(
      install.install(
        model,
        store,
        cancelToken: CancelToken(),
        onProgress: (_, _, _) {},
      ),
      throwsA(isA<DioException>()),
    );
    expect(store.models, isEmpty);
    expect(
      await Directory('${directory.path}/models').list().toList(),
      isEmpty,
    );
    adapter.files['mmproj.gguf'] = utf8.encode('GGUFprojection');
    await install.install(
      model,
      store,
      cancelToken: CancelToken(),
      onProgress: (_, _, _) {},
    );
    expect(store.models.length, 1);
  });
  test(
    'corrupt content cannot register a model even if the file length matches',
    () async {
      final model = sample();
      adapter.files['main.gguf'] = utf8.encode('GGUFbroken');
      await expectLater(
        CatalogInstaller(dio: dio).install(
          model,
          store,
          cancelToken: CancelToken(),
          onProgress: (_, _, _) {},
        ),
        throwsFormatException,
      );
      expect(store.models, isEmpty);
      expect(store.selected, isEmpty);
      expect(
        await Directory('${directory.path}/models').list().toList(),
        isEmpty,
      );
    },
  );
  test(
    'cancellation between files cleans staging and preserves selected models',
    () async {
      store.selected['chat'] = 'previous';
      final token = CancelToken();
      await expectLater(
        CatalogInstaller(dio: dio).install(
          sample(),
          store,
          cancelToken: token,
          onProgress: (done, total, phase) {
            if (done > 0) token.cancel('test');
          },
        ),
        throwsA(isA<DioException>()),
      );
      expect(store.selected['chat'], 'previous');
      expect(store.models, isEmpty);
      expect(
        await Directory('${directory.path}/models').list().toList(),
        isEmpty,
      );
    },
  );
  test('speech quantization persists and existing function assignments stay unchanged', () async {
    store.selected['chat'] = 'previous';
    final id = await CatalogInstaller(dio: dio).install(
      sample(speech: true),
      store,
      cancelToken: CancelToken(),
      onProgress: (_, _, _) {},
    );
    expect(store.models[id]['quantization'], 'int8');
    expect(store.selected['speech'], id);
    expect(store.selected['chat'], 'previous');
  });
  test('manifest rejects unsafe filenames', () {
    expect(
      () => CatalogFile(path: '../model', bytes: 1, sha256: 'a' * 64),
      throwsFormatException,
    );
  });
}
