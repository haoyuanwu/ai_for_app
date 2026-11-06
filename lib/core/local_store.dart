import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../records/record_repository.dart';
import '../models/gguf_context_metadata.dart';
import 'storage_paths.dart';

enum ModelRole { chat, vision, speech }

extension ModelRoleLabel on ModelRole {
  String get label => ['文字对话', '图片识别', '语音识别'][index];
}

class LocalStore {
  LocalStore(this.root);
  final Directory root;
  Map<String, dynamic> data = {
    'models': <String, dynamic>{},
    'selected': <String, dynamic>{},
    'messages': <dynamic>[],
    'notes': <dynamic>[],
  };
  late Database database;
  static Future<LocalStore> open() async =>
      openAt(await getApplicationSupportDirectory());
  static Future<LocalStore> openAt(Directory root) async {
    await root.create(recursive: true);
    final store = LocalStore(root);
    store.database = await openDatabase(
      '${root.path}/local_ai.db',
      version: 3,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE app_state (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)',
        );
        await RecordRepository.create(db);
        await RecordRepository.createProposals(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await RecordRepository.create(db);
        if (oldVersion < 3) await RecordRepository.createProposals(db);
      },
    );
    final rows = await store.database.query(
      'app_state',
      where: 'id = ?',
      whereArgs: [1],
    );
    if (rows.isNotEmpty) {
      store.data =
          jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>;
    } else {
      final legacy = File('${root.path}/state.json');
      if (await legacy.exists()) {
        store.data =
            jsonDecode(await legacy.readAsString()) as Map<String, dynamic>;
        await store.save();
      }
    }
    final stored = jsonEncode(store.data);
    // A dead OS process cannot resume a native decode. Keep partial text, never
    // present an interrupted reply as complete or automatically repeat actions.
    for (final message in store.messages) {
      if (message is Map && message['status'] == 'pending') {
        message['status'] = 'failed';
        message['interrupted'] = true;
      }
    }

    // Older follow-ups incorrectly rendered an internally reused image as an attachment.
    for (final message in store.messages) {
      if (message is Map &&
          message['imageContextText'] is String &&
          message['contextImage'] == null &&
          message['image'] is String) {
        message['contextImage'] = message['image'];
        message['image'] = null;
      }
    }
    final paths = StoragePaths(root);
    await paths.restore(store.data);
    for (final model in store.models.values) {
      await GgufContextMetadata.enrich(model as Map<String, dynamic>);
    }
    if (jsonEncode(paths.snapshot(store.data)) != stored) await store.save();
    return store;
  }

  Map<String, dynamic> get models => data['models'] as Map<String, dynamic>;
  Map<String, dynamic> get selected => data['selected'] as Map<String, dynamic>;
  List<dynamic> get messages => data['messages'] as List<dynamic>;
  List<dynamic> get notes => data['notes'] as List<dynamic>;

  /// Chronological page ending before [before], or at the latest message.
  /// The exclusive index keeps older pages stable when new messages arrive.
  List<dynamic> messagePage({int? before, int limit = 50}) {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    final end = (before ?? messages.length).clamp(0, messages.length);
    final start = (end - limit).clamp(0, end);
    return messages.sublist(start, end);
  }

  static List<String> capabilities(Map<String, dynamic> model) {
    if (model['capabilities'] != null) {
      return List<String>.from(model['capabilities'] as List);
    }
    // Read configurations created before the shared model library.
    return model['role'] == 'vision'
        ? ['chat', 'vision']
        : model['role'] is String
        ? [model['role'] as String]
        : <String>[];
  }

  Map<String, dynamic>? model(ModelRole role) {
    final id = selected[role.name];
    final preferred = id == null ? null : models[id] as Map<String, dynamic>?;
    if (preferred != null) return preferred;
    // Without a preference, use an installed model with the required capability.
    // Keep the choice ephemeral so each function can share the same model.
    for (final value in models.values) {
      final model = value as Map<String, dynamic>;
      if (capabilities(model).contains(role.name)) return model;
    }
    return null;
  }

  Future<void> _pending = Future.value();
  Future<void> save() {
    final snapshot = jsonEncode(StoragePaths(root).snapshot(data));
    return _pending = _pending.catchError((Object _) {}).then((_) async {
      await database.insert('app_state', {
        'id': 1,
        'payload': snapshot,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<String> copyMedia(String source) async {
    final dir = await Directory('${root.path}/media').create(recursive: true);
    final name = source.split(Platform.pathSeparator).last;
    return (await File(source)
            .copy('${dir.path}/${DateTime.now().microsecondsSinceEpoch}_$name'))
        .path;
  }
}
