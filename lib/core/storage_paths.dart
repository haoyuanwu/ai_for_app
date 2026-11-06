import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Persist app-owned paths relative to the current data container.
/// The live store still exposes absolute paths to inference and file APIs.
class StoragePaths {
  StoragePaths(Directory directory)
    : root = p.normalize(directory.absolute.path);
  final String root;

  Iterable<({Map<String, dynamic> item, String key, String area})> _fields(
    Map<String, dynamic> data,
  ) sync* {
    for (final value in (data['models'] as Map? ?? {}).values) {
      if (value is! Map<String, dynamic>) continue;
      for (final key in ['path', 'projection', 'directory']) {
        yield (item: value, key: key, area: 'models');
      }
    }
    for (final collection in ['messages', 'notes']) {
      for (final value in data[collection] as List? ?? []) {
        if (value is! Map<String, dynamic>) continue;
        for (final key in ['image', 'contextImage', 'audio']) {
          yield (item: value, key: key, area: 'media');
        }
      }
    }
  }

  bool _safeRelative(String path, String area) =>
      !p.isAbsolute(path) &&
      !path.contains('\\') &&
      !p.split(path).contains('..') &&
      (path == area || path.startsWith('$area/'));

  Map<String, dynamic> snapshot(Map<String, dynamic> data) {
    final copy = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    for (final field in _fields(copy)) {
      final value = field.item[field.key];
      if (value is! String || !p.isAbsolute(value)) continue;
      final normalized = p.normalize(value);
      if (p.isWithin(p.join(root, field.area), normalized) ||
          normalized == p.join(root, field.area)) {
        field.item[field.key] = p.relative(normalized, from: root);
      }
    }
    copy['storagePathsVersion'] = 1;
    return copy;
  }

  Future<void> restore(Map<String, dynamic> data) async {
    for (final field in _fields(data)) {
      final value = field.item[field.key];
      if (value is! String) continue;
      if (_safeRelative(value, field.area)) {
        field.item[field.key] = p.join(root, value);
        continue;
      }
      if (!p.isAbsolute(value) || p.isWithin(root, p.normalize(value))) {
        continue;
      }
      // Recover old absolute paths only when their app-owned relative counterpart
      // actually exists. Existing external model paths remain untouched.
      if (await FileSystemEntity.type(value, followLinks: false) !=
          FileSystemEntityType.notFound) {
        continue;
      }
      final marker = '/${field.area}/';
      final index = value.lastIndexOf(marker);
      if (index < 0) continue;
      final relative = value.substring(index + 1);
      if (!_safeRelative(relative, field.area)) continue;
      final candidate = p.join(root, relative);
      final type = await FileSystemEntity.type(candidate, followLinks: false);
      if (type == FileSystemEntityType.file ||
          type == FileSystemEntityType.directory) {
        field.item[field.key] = candidate;
      }
    }
  }
}
