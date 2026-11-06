import 'dart:io';

import '../core/local_store.dart';

class ModelDeletionResult {
  const ModelDeletionResult({required this.filesRemoved, this.warning});
  final bool filesRemoved;
  final String? warning;
}

/// Removes model registrations and only their app-owned storage directories.
class ModelLibrary {
  ModelLibrary(this.store);
  final LocalStore store;
  List<String> get _cleanup =>
      List<String>.from(store.data['modelCleanup'] as List? ?? []);
  String _folder(String id) => '${store.root.absolute.path}/models/$id';
  bool _validId(String id) => RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id);
  bool _shared(String id) {
    final folder = _folder(id);
    return store.models.entries.any(
      (entry) =>
          entry.key != id &&
          ['path', 'projection', 'directory'].any((key) {
            final path = entry.value[key];
            if (path is! String) return false;
            final absolute = File(path).absolute.path;
            return absolute == folder ||
                absolute.startsWith('$folder${Platform.pathSeparator}');
          }),
    );
  }

  Future<void> _deleteFiles(String id) async {
    if (!_validId(id)) throw StateError('模型目录标识无效，未删除文件');
    if (_shared(id)) return;
    final directory = Directory(_folder(id));
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return;
    final canonicalRoot = await store.root.resolveSymbolicLinks();
    if (type != FileSystemEntityType.directory ||
        await directory.resolveSymbolicLinks() != '$canonicalRoot/models/$id') {
      throw StateError('模型目录不是应用管理的普通目录，未删除文件');
    }
    // Directory.delete recursively unlinks symlinks instead of following them.
    await directory.delete(recursive: true);
  }

  Future<ModelDeletionResult> delete(String id) async {
    if (!store.models.containsKey(id)) {
      return const ModelDeletionResult(filesRemoved: false);
    }
    final model = store.models[id];
    final previousSelections = Map<String, dynamic>.from(store.selected);
    final previousCleanup = _cleanup;
    final shared = _shared(id);
    final cleanup = {
      ...previousCleanup,
      if (!shared && _validId(id)) id,
    }.toList();
    store.models.remove(id);
    store.selected.removeWhere((key, value) => value == id);
    store.data['modelCleanup'] = cleanup;
    try {
      await store.save();
    } catch (_) {
      store.models[id] = model;
      store.selected
        ..clear()
        ..addAll(previousSelections);
      store.data['modelCleanup'] = previousCleanup;
      rethrow;
    }
    if (shared) {
      return const ModelDeletionResult(
        filesRemoved: false,
        warning: '文件仍被其他模型配置引用，已保留共享文件。',
      );
    }
    if (!_validId(id)) {
      return const ModelDeletionResult(
        filesRemoved: false,
        warning: '已移除模型配置；目录标识无效，未清理文件。',
      );
    }
    final errors = await cleanupFiles();
    return ModelDeletionResult(
      filesRemoved: !errors.containsKey(id),
      warning: errors[id],
    );
  }

  /// Persisted cleanup work is retried after deletion and on app startup.
  Future<Map<String, String>> cleanupFiles() async {
    final pending = _cleanup;
    final remaining = <String>[];
    final errors = <String, String>{};
    for (final id in pending) {
      if (store.models.containsKey(id)) {
        remaining.add(id);
        continue;
      }
      try {
        await _deleteFiles(id);
      } catch (e) {
        remaining.add(id);
        errors[id] = '文件清理未完成：$e。应用下次启动会重试。';
      }
    }
    if (remaining.length != pending.length) {
      store.data['modelCleanup'] = remaining;
      try {
        await store.save();
      } catch (_) {
        store.data['modelCleanup'] = pending;
        // Registrations are already removed; the old persisted queue is safe to retry.
      }
    }
    return errors;
  }
}
