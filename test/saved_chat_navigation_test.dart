import 'package:ai_for_app/ui/record_media_view.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:ai_for_app/ui/app_theme.dart';
import 'package:ai_for_app/ui/records_view.dart';
import 'package:ai_for_app/ui/settings_page.dart';

import 'package:ai_for_app/core/ai_engine.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/core/voice_recorder.dart';
import 'package:ai_for_app/main.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'records_test.dart' show FakeScheduler;

class WarmupEngine extends AiEngine {
  final ready = Completer<void>();
  @override
  Future<void> warmLiveSpeech(LocalStore store) => ready.future;
}

class QuietRecorder implements VoiceRecorder {
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start(String path) async {}
  @override
  Future<String?> stop() async => null;
  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory root;
  late LocalStore store;
  late RecordService service;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('saved_chat');
    store = await LocalStore.openAt(root);
    service = RecordService(
      RecordRepository(store.database),
      FakeScheduler(),
      (t, n) async => [],
    );
  });
  tearDown(() async {
    await store.database.close();
    await root.delete(recursive: true);
  });
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('compact pages render with aligned controls at phone size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.runAsync(() async {
      final font = FontLoader('UiPreview')
        ..addFont(
          File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf')
              .readAsBytes()
              .then((b) => ByteData.sublistView(b)),
        );
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '/Users/why/fvm/versions/3.47.5/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await icons.load();
      await service.repository.insert('preview', [
        const ExtractedRecord(
          kind: RecordKind.expense,
          title: '午餐',
          quote: '午餐花了28元',
          amountMinor: 2800,
          currency: 'CNY',
          direction: 'expense',
        ),
      ]);
    });
    store.messages.addAll([
      {
        'id': 'preview',
        'role': 'user',
        'text': '帮我记下午餐花了28元',
        'status': 'done',
        'extraction': 'done',
      },
      {
        'role': 'assistant',
        'text': '保存好了。',
        'status': 'done',
        'recordIds': [1],
      },
    ]);
    final original = journalTheme();
    final theme = original.copyWith(
      textTheme: original.textTheme.apply(fontFamily: 'UiPreview'),
      appBarTheme: original.appBarTheme.copyWith(
        titleTextStyle: original.appBarTheme.titleTextStyle!.copyWith(
          fontFamily: 'UiPreview',
        ),
      ),
    );
    final pages = <String, Widget Function()>{
      'chat': () => HomePage(
        store: store,
        recordService: service,
        voiceRecorder: QuietRecorder(),
      ),
      'records': () => Scaffold(
        appBar: AppBar(title: const Text('我的记录')),
        body: RecordsView(store: store, service: service),
      ),
      'settings': () => SettingsPage(store: store),
    };
    for (final page in pages.entries) {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: page.value(),
          ),
        ),
      );
      await flush(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (page.key == 'records') {
        final edit = tester.getRect(find.byTooltip('编辑内容'));
        final delete = tester.getRect(find.byTooltip('删除记录'));
        expect(edit.center.dy, delete.center.dy);
        expect(edit.width, greaterThanOrEqualTo(44));
        expect(delete.width, greaterThanOrEqualTo(44));
      }
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${Directory.systemTemp.path}/compact-ui-${page.key}.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('only assistant save receipt opens matching saved data', (
    tester,
  ) async {
    final rows = (await tester.runAsync(() async {
      await service.repository.insert('source-chat', [
        const ExtractedRecord(
          kind: RecordKind.task,
          title: '目标事项',
          quote: '目标事项',
          fields: [
            {'label': '来源', 'value': '聊天'},
          ],
        ),
      ]);
      await service.repository.insert('other-chat', [
        const ExtractedRecord(
          kind: RecordKind.task,
          title: '其他事项',
          quote: '其他事项',
        ),
      ]);
      return service.repository.all();
    }))!;
    final id =
        rows.singleWhere((r) => r['source_id'] == 'source-chat')['id'] as int;
    store.messages.addAll([
      {
        'id': 'source-chat',
        'role': 'user',
        'text': '请保存目标事项',
        'audio': '/original-chat.wav',
        'status': 'done',
      },
      {
        'role': 'assistant',
        'text': '保存好了。',
        'status': 'done',
        'recordIds': [id],
      },
    ]);
    await tester.pumpWidget(MyApp(store: store, recordService: service));
    await flush(tester);
    expect(find.text('查看记录'), findsNothing);
    await tester.tap(find.text('请保存目标事项'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('record-$id')), findsNothing);
    await tester.tap(find.text('保存好了。'));
    await flush(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('record-$id')), findsOneWidget);
    expect(find.textContaining('其他事项'), findsNothing);
    expect(find.textContaining('来源：聊天'), findsNothing);
    expect(find.byType(RecordMediaView), findsNothing);
    expect(find.byTooltip('编辑内容'), findsOneWidget);
    expect(find.byTooltip('删除记录'), findsOneWidget);
    expect(find.text('编辑内容'), findsNothing);
    await tester.tap(find.text('查看全部记录'));
    await tester.pumpAndSettle();
    expect(find.textContaining('其他事项'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存好了。'));
    await flush(tester);
    expect(find.byKey(ValueKey('record-$id')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('model warmup displays loading and removes it when ready', (
    tester,
  ) async {
    final file = (await tester.runAsync(
      () => File('${root.path}/model.gguf').writeAsString('fixture'),
    ))!;
    store.models['speech'] = {
      'name': '语音模型',
      'path': file.path,
      'capabilities': ['speech'],
    };
    store.selected['speech'] = 'speech';
    store.data['liveSpeechEnabled'] = true;
    final engine = WarmupEngine();
    await tester.pumpWidget(
      MyApp(
        store: store,
        recordService: service,
        aiEngine: engine,
        voiceRecorder: QuietRecorder(),
      ),
    );
    await flush(tester);
    expect(
      find.byKey(const ValueKey('assistant-waiting-bubble')),
      findsOneWidget,
    );
    engine.ready.complete();
    await flush(tester);
    expect(
      find.byKey(const ValueKey('assistant-waiting-bubble')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
