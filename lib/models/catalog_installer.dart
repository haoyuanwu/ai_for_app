import 'gguf_context_metadata.dart';

import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';

import '../core/local_store.dart';
import 'model_catalog.dart';

typedef ModelProgress = void Function(int received, int total, String phase);

class CatalogInstaller {
  CatalogInstaller({Dio? dio})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 60),
            ),
          );
  final Dio dio;
  Future<String> install(
    CatalogModel model,
    LocalStore store, {
    required CancelToken cancelToken,
    required ModelProgress onProgress,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(model.id) ||
        model.files.isEmpty) {
      throw const FormatException('模型清单无效');
    }
    for (final entry in store.models.entries) {
      if (entry.value['catalogId'] == model.id &&
          entry.value['revision'] == model.revision) {
        final directory = entry.value['directory'] as String?;
        if (directory != null) {
          var complete = true;
          for (final file in model.files) {
            final local = File('$directory/${file.path}');
            if (!await local.exists() || await local.length() != file.bytes) {
              complete = false;
              break;
            }
          }
          if (complete) return entry.key;
        }
      }
    }
    final id = '${model.id}-${DateTime.now().microsecondsSinceEpoch}';
    var directory = await Directory('${store.root.path}/models/.partial-$id')
        .create(recursive: true);
    var committed = false;
    try {
      var completed = 0;
      for (var i = 0; i < model.files.length; i++) {
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        final file = model.files[i];
        final target = File('${directory.path}/${file.path}');
        await target.parent.create(recursive: true);
        final temp = File('${target.path}.part');
        await dio.download(
          model.downloadUrl(file).toString(),
          temp.path,
          cancelToken: cancelToken,
          deleteOnError: true,
          onReceiveProgress: (received, total) => onProgress(
            completed + received,
            model.bytes,
            '下载文件 ${i + 1}/${model.files.length}',
          ),
        );
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        onProgress(
          completed + file.bytes,
          model.bytes,
          '校验文件 ${i + 1}/${model.files.length}',
        );
        if (await temp.length() != file.bytes) {
          throw const FormatException('文件大小不匹配，请重新下载');
        }
        final digest = await crypto.sha256.bind(temp.openRead()).first;
        if (digest.toString() != file.sha256) {
          throw const FormatException('文件校验失败，请重新下载');
        }
        if (file.path.endsWith('.gguf')) {
          final handle = await temp.open();
          try {
            if (String.fromCharCodes(await handle.read(4)) != 'GGUF') {
              throw const FormatException('不是有效的 GGUF 文件');
            }
          } finally {
            await handle.close();
          }
        } else if (file.path.endsWith('.json')) {
          if (jsonDecode(await temp.readAsString()) is! Map) {
            throw const FormatException('模型配置文件无效');
          }
        }
        await temp.rename(target.path);
        completed += file.bytes;
      }
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      directory = await directory.rename('${store.root.path}/models/$id');
      final root = directory.path;
      final primary = model.format == 'gguf'
          ? '$root/${model.files.first.path}'
          : root;
      final projections = model.files.where((f) => f.path.startsWith('mmproj'));
      final previousSelections = Map<String, dynamic>.from(store.selected);
      store.models[id] = {
        'id': id,
        'catalogId': model.id,
        'revision': model.revision,
        'name': '${model.name} · ${model.variant}',
        'capabilities': model.capabilities,
        'format': model.format,
        'path': primary,
        'directory': root,
        'projection': projections.isEmpty
            ? null
            : '$root/${projections.single.path}',
        'quantization': model.quantization,
      };
      await GgufContextMetadata.enrich(
        store.models[id] as Map<String, dynamic>,
      );
      for (final capability in model.capabilities) {
        store.selected.putIfAbsent(capability, () => id);
      }
      try {
        await store.save();
      } catch (_) {
        store.models.remove(id);
        store.selected
          ..clear()
          ..addAll(previousSelections);
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
