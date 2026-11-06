import 'dart:io';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';

import '../core/local_store.dart';
import 'model_package.dart';

Future<String?> exportModelToFiles(
  LocalStore store,
  String id, {
  bool Function()? shouldPresent,
  Directory? temporaryDirectory,
}) async {
  final directory = await (temporaryDirectory ?? await getTemporaryDirectory())
      .createTemp('model_export_');
  try {
    final name = (store.models[id]['name'] as String).replaceAll(
      RegExp(r'[^a-zA-Z0-9\u4e00-\u9fff._-]'),
      '_',
    );
    final safeName = name.length > 80 ? name.substring(0, 80) : name;
    final file = await ModelPackage.create(
      store,
      id,
      File('${directory.path}/$safeName.zip'),
    );
    if (shouldPresent != null && !shouldPresent()) return null;
    return await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(sourceFilePath: file.path, localOnly: true),
    );
  } finally {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
