import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/ui/model_catalog_page.dart';
import 'package:ai_for_app/ui/models_page.dart';

void main() {
  late Directory directory;
  late LocalStore store;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('catalog_ui');
    store = await LocalStore.openAt(directory);
  });
  tearDown(() async {
    await store.database.close();
    await directory.delete(recursive: true);
  });
  testWidgets(
    'domestic catalog bundles vision files and offers domestic speech models',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: ModelsPage(store: store)));
      await tester.tap(find.text('浏览模型列表'));
      await tester.pumpAndSettle();
      expect(find.text('Qwen3.5 0.8B'), findsOneWidget);
      expect(find.text('Qwen3 0.6B'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, '图片'));
      await tester.pumpAndSettle();
      expect(find.text('Qwen3.5 0.8B'), findsOneWidget);
      expect(find.text('Whisper Tiny'), findsNothing);
      expect(find.text('Qwen3 0.6B'), findsNothing);
      await tester.ensureVisible(find.text('下载 737.5 MB'));
      await tester.tap(find.text('下载 737.5 MB'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 个文件'), findsOneWidget);
      expect(find.text('开始下载'), findsOneWidget);
      expect(find.text('下载保存位置'), findsOneWidget);
      expect(find.text('应用内（默认）'), findsOneWidget);
      await tester.ensureVisible(find.text('应用内（默认）'));
      await tester.tap(find.text('应用内（默认）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机文件 + 应用内副本').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('下载完成后选择手机文件中的保存位置'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.models, isEmpty);
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '语音'));
      await tester.pumpAndSettle();
      expect(find.text('SenseVoice Small'), findsOneWidget);
      expect(find.text('Qwen3-ASR 0.6B'), findsOneWidget);
      expect(find.text('开始下载'), findsNothing);
    },
  );
  testWidgets(
    'catalog scrolls on small screens, landscape, large text and dark mode',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final (size, scale) in [
        (const Size(375, 812), 1.0),
        (const Size(812, 375), 1.8),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: ModelCatalogPage(store: store),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView), const Offset(0, -250));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'vendor filtering exposes Xiaomi with high memory warning and handles empty capability combinations',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ModelCatalogPage(store: store)),
      );
      await tester.tap(find.text('全部厂商'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('小米 · MiMo').last);
      await tester.tap(find.text('小米 · MiMo').last);
      await tester.pumpAndSettle();
      expect(find.text('小米 MiMo 7B RL'), findsOneWidget);
      expect(find.text('Qwen3 0.6B'), findsNothing);
      await tester.ensureVisible(find.text('下载 4.68 GB'));
      await tester.tap(find.text('下载 4.68 GB'));
      await tester.pumpAndSettle();
      expect(find.textContaining('高内存设备候选：'), findsOneWidget);
      expect(find.text('查看厂商模型与许可'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '语音'));
      await tester.pumpAndSettle();
      expect(find.text('该厂商暂无此用途的模型，请切换筛选。'), findsOneWidget);
      expect(store.models, isEmpty);
    },
  );
}
