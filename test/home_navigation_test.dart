import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/main.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/ui/settings_page.dart';
import 'package:ai_for_app/ui/models_page.dart';
import 'package:ai_for_app/core/assistant_persona.dart';

void main() {
  late Directory root;
  late LocalStore store;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('home_navigation');
    store = await LocalStore.openAt(root);
  });
  tearDown(() async {
    await store.database.close();
    await root.delete(recursive: true);
  });
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'function model choices live in settings and persist per capability',
    (tester) async {
      store.models.addAll({
        'shared': {
          'name': '共享模型',
          'capabilities': ['chat', 'vision'],
        },
        'speech': {
          'name': '语音模型',
          'capabilities': ['speech'],
        },
      });
      await tester.pumpWidget(MaterialApp(home: SettingsPage(store: store)));
      expect(find.text('功能使用的模型'), findsOneWidget);
      final chat = find.byKey(const ValueKey('function-model-chat-null'));
      await tester.ensureVisible(chat);
      await tester.pumpAndSettle();
      await tester.tap(chat);
      await tester.pumpAndSettle();
      await tester.tap(find.text('共享模型').last);
      await flush(tester);
      expect(store.selected['chat'], 'shared');
      expect(store.selected['vision'], isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await store.database.close();
        store = await LocalStore.openAt(root);
      });
      expect(store.selected['chat'], 'shared');
      await tester.pumpWidget(MaterialApp(home: ModelsPage(store: store)));
      expect(find.text('功能使用的模型'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('live speech switch defaults off and persists across reopening', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(store: store));
    await flush(tester);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('边说边识别'));
    await flush(tester);
    expect(store.data['liveSpeechEnabled'], isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await store.database.close();
      store = await LocalStore.openAt(root);
    });
    await tester.pumpWidget(MyApp(store: store));
    await flush(tester);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('边说边识别'));
    await flush(tester);
    expect(store.data['liveSpeechEnabled'], isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'settings lists models and editable persona without chat receipts',
    (tester) async {
      await tester.pumpWidget(MyApp(store: store));
      await flush(tester);
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(find.text('模型'), findsOneWidget);
      expect(find.text('AI 人设'), findsOneWidget);
      await tester.tap(find.text('模型'));
      await tester.pumpAndSettle();
      expect(find.text('模型中心'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 人设'));
      await tester.pumpAndSettle();
      expect(find.text('随记'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('persona_name')), '小白');
      await tester.enterText(
        find.byKey(const ValueKey('persona_personality')),
        '温柔',
      );
      await tester.enterText(
        find.byKey(const ValueKey('persona_interests')),
        '音乐',
      );
      await tester.enterText(find.byKey(const ValueKey('persona_style')), '简洁');
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await flush(tester);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('小白'), findsOneWidget);
      expect(AssistantPersona.read(store.data), {
        'name': '小白',
        'personality': '温柔',
        'interests': '音乐',
        'style': '简洁',
      });
      expect(store.messages, isEmpty);
      await tester.tap(find.text('AI 人设'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('persona_name')), '');
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入姓名'), findsOneWidget);
      expect(AssistantPersona.read(store.data)['name'], '小白');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await store.database.close();
        store = await LocalStore.openAt(root);
      });
      expect(AssistantPersona.read(store.data)['name'], '小白');
    },
  );

  testWidgets(
    'chat has no bottom tabs and opens records from the header, including large text landscape',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(MyApp(store: store));
      await flush(tester);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.byTooltip('我的记录'));
      await flush(tester);
      expect(find.text('我的记录'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(844, 390),
              textScaler: TextScaler.linear(1.8),
            ),
            child: HomePage(store: store),
          ),
        ),
      );
      await flush(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
