import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late LocalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('local_ai_test');
    store = await LocalStore.openAt(directory);
  });
  tearDown(() async {
    await store.database.close();
    await directory.delete(recursive: true);
  });
  test(
    'role selections remain independent and persist with conversation',
    () async {
      for (final role in ModelRole.values) {
        store.models[role.name] = {
          'name': role.label,
          'path': '/local/${role.name}',
          'role': role.name,
        };
        store.selected[role.name] = role.name;
      }
      store.messages.add({'role': 'user', 'text': '明天买牛奶'});
      await store.save();
      store.models['shared'] = {
        'name': '多模态',
        'path': '/local/shared',
        'capabilities': ['chat', 'vision', 'speech'],
        'format': 'gguf',
      };
      for (final role in ModelRole.values) {
        store.selected[role.name] = 'shared';
      }
      expect(
        identical(store.model(ModelRole.chat), store.model(ModelRole.vision)),
        isTrue,
      );
      expect(
        identical(store.model(ModelRole.vision), store.model(ModelRole.speech)),
        isTrue,
      );
      store.selected['vision'] = 'vision';
      store.selected['speech'] = 'speech';
      store.selected['chat'] = 'another';
      await store.save();
      final restored = await LocalStore.openAt(directory);
      expect(restored.selected['chat'], 'another');
      expect(restored.model(ModelRole.vision)?['path'], '/local/vision');
      expect(restored.model(ModelRole.speech)?['path'], '/local/speech');
      expect(restored.messages.single['text'], '明天买牛奶');
    },
  );
  testWidgets(
    'first launch explains local models and opens independent role configuration',
    (tester) async {
      await tester.pumpWidget(MyApp(store: store));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('把生活，慢慢记下来'), findsOneWidget);
      await tester.tap(find.text('配置本地模型'));
      await tester.pumpAndSettle();
      expect(find.text('模型中心'), findsOneWidget);
      expect(find.text('文字对话'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('图片识别'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('图片识别'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsWidgets);
    },
  );
}
