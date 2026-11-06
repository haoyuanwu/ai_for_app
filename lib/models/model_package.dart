import 'gguf_context_metadata.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../core/local_store.dart';
import 'speech_bundle.dart';

const _manifestName = 'model-package.json';
const _formats = {'gguf', 'whisper', 'sensevoice', 'qwen3asr'};
bool _safeName(String name) {
  final stripped = name.endsWith('/')
      ? name.substring(0, name.length - 1)
      : name;
  return stripped.isNotEmpty &&
      !p.posix.isAbsolute(name) &&
      !name.contains('\\') &&
      !name.contains(':') &&
      stripped
          .split('/')
          .every((part) => part.isNotEmpty && part != '.' && part != '..');
}

/// Portable packages contain only model assets and relative metadata, no chat data.
class ModelPackage {
  static Future<File> create(LocalStore store, String id, File target) async {
    final model = store.models[id] as Map<String, dynamic>?;
    if (model == null) throw StateError('模型不存在');
    final format = model['format'] as String;
    if (!_formats.contains(format)) throw const FormatException('不支持导出此模型格式');
    final assets = <({String source, String name})>[];
    Future<void> add(String source, String name) async {
      if (await FileSystemEntity.type(source, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError('模型文件缺失或为链接，无法导出：${p.basename(source)}');
      }
      assets.add((source: source, name: name));
    }

    final source = model['path'] as String;
    String primary;
    String? projection;
    if (format == 'gguf') {
      primary = 'files/model.gguf';
      await add(source, primary);
      if (model['projection'] != null) {
        projection = 'files/mmproj.gguf';
        await add(model['projection'] as String, projection);
      }
    } else {
      if (await FileSystemEntity.type(source, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw StateError('语音模型目录不存在，无法导出');
      }
      primary = 'files';
      await for (final entry in Directory(
        source,
      ).list(recursive: true, followLinks: false)) {
        if (entry is Link) throw const FormatException('模型目录包含链接，无法导出');
        if (entry is File) {
          await add(
            entry.path,
            'files/${p.relative(entry.path, from: source).split(p.separator).join('/')}',
          );
        }
      }
      if (assets.isEmpty) throw StateError('语音模型目录为空');
    }
    final manifest = <String, dynamic>{
      'version': 1,
      'name': model['name'],
      'format': format,
      'capabilities': LocalStore.capabilities(model),
      'path': primary,
      'projection': projection,
      'quantization': model['quantization'],
      'files': [for (final asset in assets) asset.name],
    };
    await target.parent.create(recursive: true);
    try {
      await Isolate.run(() => _writePackage(target.path, manifest, assets));
      return target;
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  static Future<String> import(LocalStore store, String source) async {
    final id = 'import-${DateTime.now().microsecondsSinceEpoch}';
    var directory = await Directory('${store.root.path}/models/.partial-$id')
        .create(recursive: true);
    var committed = false;
    try {
      final manifest = await Isolate.run(() => _unpack(source, directory.path));
      final relative = manifest['path'] as String;
      final format = manifest['format'] as String;
      if (format == 'gguf') {
        await _checkGguf('${directory.path}/$relative');
        if (manifest['projection'] != null) {
          await _checkGguf('${directory.path}/${manifest['projection']}');
        }
        if ((manifest['capabilities'] as List).any(
              (c) => c == 'vision' || c == 'speech',
            ) &&
            manifest['projection'] == null) {
          throw const FormatException('多模态模型缺少配套投影');
        }
      } else {
        final bundle = await SpeechBundle.detect(
          Directory('${directory.path}/files'),
        );
        if (bundle.format != format ||
            bundle.path != '${directory.path}/$relative') {
          throw const FormatException('语音模型格式或目录不匹配');
        }
      }
      directory = await directory.rename('${store.root.path}/models/$id');
      final previous = Map<String, dynamic>.from(store.selected);
      store.models[id] = {
        'id': id,
        'name': manifest['name'],
        'format': format,
        'capabilities': manifest['capabilities'],
        'path': '${directory.path}/$relative',
        'directory': directory.path,
        'projection': manifest['projection'] == null
            ? null
            : '${directory.path}/${manifest['projection']}',
        'quantization': manifest['quantization'],
      };
      await GgufContextMetadata.enrich(
        store.models[id] as Map<String, dynamic>,
      );
      for (final role in manifest['capabilities'] as List) {
        store.selected.putIfAbsent(role as String, () => id);
      }
      try {
        await store.save();
      } catch (_) {
        store.models.remove(id);
        store.selected
          ..clear()
          ..addAll(previous);
        rethrow;
      }
      committed = true;
      return id;
    } finally {
      if (!committed && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }
}

Future<void> _checkGguf(String path) async {
  final input = await File(path).open();
  try {
    if (String.fromCharCodes(await input.read(4)) != 'GGUF') {
      throw const FormatException('模型包内不是有效的 GGUF 文件');
    }
  } finally {
    await input.close();
  }
}

Future<void> _writePackage(
  String target,
  Map<String, dynamic> manifest,
  List<({String source, String name})> assets,
) async {
  final encoder = ZipFileEncoder()..create(target, level: 0);
  try {
    final bytes = utf8.encode(jsonEncode(manifest));
    encoder.addArchiveFile(ArchiveFile(_manifestName, bytes.length, bytes));
    for (final asset in assets) {
      await encoder.addFile(File(asset.source), asset.name, 0);
    }
  } finally {
    await encoder.close();
  }
}

Future<Map<String, dynamic>> _unpack(String source, String target) async {
  final input = InputFileStream(source);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final names = <String>{};
    for (final entry in archive) {
      if (!_safeName(entry.name) ||
          entry.isSymbolicLink ||
          !names.add(entry.name)) {
        throw const FormatException('模型包包含不安全或重复的文件路径');
      }
      if (entry.name != _manifestName && !entry.name.startsWith('files/')) {
        throw const FormatException('模型包包含清单之外的目录');
      }
    }
    final metadata = archive.findFile(_manifestName);
    if (metadata == null || metadata.size > 65536) {
      throw const FormatException('请选择应用导出的完整模型包 ZIP');
    }
    final manifest =
        jsonDecode(utf8.decode(metadata.content)) as Map<String, dynamic>;
    final capabilities = manifest['capabilities'];
    final files = manifest['files'];
    if (manifest['version'] != 1 ||
        manifest['name'] is! String ||
        !_formats.contains(manifest['format']) ||
        capabilities is! List ||
        capabilities.isEmpty ||
        capabilities.any((c) => !['chat', 'vision', 'speech'].contains(c)) ||
        files is! List ||
        files.isEmpty ||
        files.any(
          (f) =>
              f is! String ||
              !_safeName(f) ||
              !f.startsWith('files/') ||
              !names.contains(f),
        )) {
      throw const FormatException('模型包清单无效');
    }
    for (final entry in archive.where(
      (e) => e.isFile && e.name != _manifestName,
    )) {
      if (!files.contains(entry.name)) {
        throw const FormatException('模型包有未声明的文件');
      }
    }
    for (final key in ['path', 'projection']) {
      final value = manifest[key];
      if (value == null && key == 'projection') continue;
      if (value is! String ||
          !_safeName(value) ||
          !(value == 'files' || value.startsWith('files/'))) {
        throw const FormatException('模型包路径无效');
      }
    }
    await extractArchiveToDisk(archive, target);
    return manifest;
  } finally {
    await input.close();
  }
}
