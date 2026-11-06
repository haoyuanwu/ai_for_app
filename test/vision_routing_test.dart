import 'package:ai_for_app/ui/record_media_view.dart';

import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:ai_for_app/core/ai_engine.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/main.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'voice_input_test.dart' show FakeRecorder;

class Gallery extends ImagePickerPlatform {
  Gallery(this.path);
  final String path;
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile(path);
}

class VisionEngine extends AiEngine {
  ModelRole? extractionRole;
  String? extractedText;
  String? replyModel;
  String? lastImage;
  bool fail = false;
  bool failImage = false;
  String? replyPrompt;
  bool failTranscription = false;
  @override
  Stream<String> transcribeStream(LocalStore store, String audio) async* {
    if (failTranscription) throw StateError('识别失败');
    yield '看看这张图片';
  }

  @override
  Stream<String> reply(
    LocalStore store,
    String text, {
    String? image,
    void Function(String)? onRelationSaved,
    RecordService? recordService,
    void Function(String)? onMutationError,
  }) async* {
    replyPrompt = text;
    lastImage = image;
    replyModel = store.selected[image == null ? 'chat' : 'vision'] as String?;
    if (fail) throw StateError('视觉推理失败');
    yield '图片中是午饭收据，金额20元。';
  }

  bool receipt = false;
  String? extractionImage, extractionInstruction;
  bool identities = false;
  bool mixed = false;
  bool phoneOnlyOcr = false;
  int imageExtractions = 0;
  Completer<void>? imageExtractionGate;
  @override
  Future<({String text, List<ExtractedRecord> records})> extractImage(
    LocalStore store,
    String image,
    DateTime now, {
    String instruction = '',
  }) async {
    if (phoneOnlyOcr) {
      return (text: '张三电话13800138000', records: <ExtractedRecord>[]);
    }
    imageExtractions++;
    if (failImage) throw StateError('图片识别失败');
    extractionImage = image;
    extractionInstruction = instruction;
    if (identities) {
      const source =
          '张甲 身份证号 110101199001010010\n李乙 身份证号 110101199002020020\n王丙 身份证号 110101199003030030';
      return (
        text: source,
        records: instruction.contains('身份证')
            ? [
                for (final line in source.split('\n'))
                  ExtractedRecord(
                    kind: RecordKind.note,
                    title: line.split(' ').first,
                    quote: line,
                    category: '身份信息',
                    fields: [
                      {'label': '姓名', 'value': line.split(' ').first},
                      {'label': '身份证号', 'value': line.split(' ').last},
                    ],
                  ),
              ]
            : <ExtractedRecord>[],
      );
    }
    if (mixed) {
      return (
        text:
            '妈妈生日1980年5月10日\n张三电话13800138000\n王五身份证号110101199001010010\n午饭花20元',
        records: [
          ExtractedRecord(
            kind: RecordKind.date,
            title: '妈妈生日',
            quote: '妈妈生日1980年5月10日',
            template: 'birthday',
            date: '1980-05-10',
          ),
          ExtractedRecord(
            kind: RecordKind.phone,
            title: '张三',
            quote: '张三电话13800138000',
            phone: '13800138000',
          ),
          ExtractedRecord(
            kind: RecordKind.note,
            title: '王五',
            quote: '王五身份证号110101199001010010',
            category: '身份信息',
            fields: [
              {'label': '身份证号', 'value': '110101199001010010'},
            ],
          ),
          ExtractedRecord(
            kind: RecordKind.expense,
            title: '午饭',
            quote: '午饭花20元',
            amountMinor: 2000,
            currency: 'CNY',
            direction: 'expense',
          ),
        ],
      );
    }
    await imageExtractionGate?.future;
    extractionRole = ModelRole.vision;
    extractedText = '早餐店付款金额20元\n书店付款金额30元';
    return (
      text: extractedText!,
      records: receipt
          ? [
              const ExtractedRecord(
                kind: RecordKind.expense,
                title: '早餐店',
                quote: '早餐店付款金额20元',
                amountMinor: 2000,
                currency: 'CNY',
                direction: 'expense',
              ),
              const ExtractedRecord(
                kind: RecordKind.expense,
                title: '书店',
                quote: '书店付款金额30元',
                amountMinor: 3000,
                currency: 'CNY',
                direction: 'expense',
              ),
            ]
          : <ExtractedRecord>[],
    );
  }

  @override
  Future<List<ExtractedRecord>> extract(
    LocalStore store,
    String text,
    DateTime now, {
    String? previousJson,
    ModelRole? role,
  }) async {
    extractionRole = role;
    extractedText = text;
    if (phoneOnlyOcr) {
      return [
        const ExtractedRecord(
          kind: RecordKind.phone,
          title: '张三',
          quote: '张三电话13800138000',
          phone: '13800138000',
        ),
      ];
    }
    if (identities && text.startsWith('帮我记录') && text.contains('身份证')) {
      return [
        for (final line
            in text.split('\n').where((line) => line.contains(' 身份证号 ')))
          ExtractedRecord(
            kind: RecordKind.note,
            title: line.split(' ').first,
            quote: line,
            category: '身份信息',
            fields: [
              {'label': '姓名', 'value': line.split(' ').first},
              {'label': '身份证号', 'value': line.split(' ').last},
            ],
          ),
      ];
    }
    return [];
  }
}

void main() {
  late Directory root;
  late LocalStore store;
  late String photo;
  late ImagePickerPlatform originalGallery;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vision_routing');
    store = await LocalStore.openAt(root);
    photo = '${root.path}/photo.png';
    await File(photo).writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9XkAAAAASUVORK5CYII=',
      ),
    );
    store.models.addAll({
      'chat': {
        'name': '文字模型',
        'path': '${root.path}/chat-missing.gguf',
        'capabilities': ['chat'],
      },
      'vision': {
        'name': '视觉模型',
        'path': '${root.path}/vision-missing.gguf',
        'capabilities': ['chat', 'vision'],
      },
      'vision2': {
        'name': '另一个视觉模型',
        'path': '${root.path}/vision2.gguf',
        'capabilities': ['chat', 'vision'],
      },
    });
    store.selected.addAll({'chat': 'chat', 'vision': 'vision'});
    originalGallery = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = Gallery(photo);
  });
  tearDown(() async {
    ImagePickerPlatform.instance = originalGallery;
    await store.database.close();
    await root.delete(recursive: true);
  });
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> attach(WidgetTester tester, AiEngine engine) async {
    await tester.pumpWidget(MyApp(store: store, aiEngine: engine));
    await flush(tester);
    await tester.tap(find.byTooltip('选择图片'));
    await flush(tester);
    expect(
      find.byKey(const ValueKey('composer-image-preview')),
      findsOneWidget,
    );
    final preview = tester.getRect(
      find.byKey(const ValueKey('composer-image-preview')),
    );
    final composer = tester.getRect(
      find.byKey(const ValueKey('chat-composer')),
    );
    expect(preview.left, composer.left + 12);
    expect(preview.bottom, lessThanOrEqualTo(composer.top));
  }

  Future<void> recordDraft(WidgetTester tester, VisionEngine engine) async {
    store.models['speech'] = {
      'name': '语音模型',
      'capabilities': ['speech'],
    };
    await tester.pumpWidget(
      MyApp(store: store, aiEngine: engine, voiceRecorder: FakeRecorder()),
    );
    await flush(tester);
    final touch = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await flush(tester);
    await touch.up();
    await flush(tester);
  }

  testWidgets('clearing voice draft keeps next photo free of stale recording', (
    tester,
  ) async {
    await recordDraft(tester, VisionEngine());
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byTooltip('选择图片'));
    await flush(tester);
    await tester.tap(find.byTooltip('发送'));
    await flush(tester);
    final user = store.messages.firstWhere((m) => m['role'] == 'user');
    expect(user['image'], isNotNull);
    expect(user['audio'], isNull);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is RecordMediaView && widget.audio != null,
      ),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('failed transcription does not attach recording to a photo', (
    tester,
  ) async {
    await recordDraft(tester, VisionEngine()..failTranscription = true);
    await tester.tap(find.byTooltip('选择图片'));
    await flush(tester);
    await tester.tap(find.byTooltip('发送'));
    await flush(tester);
    final user = store.messages.firstWhere((m) => m['role'] == 'user');
    expect(user['image'], isNotNull);
    expect(user['audio'], isNull);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is RecordMediaView && widget.audio != null,
      ),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'photo with an actual spoken caption retains its own recording only',
    (tester) async {
      await recordDraft(tester, VisionEngine());
      await tester.tap(find.byTooltip('选择图片'));
      await flush(tester);
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      final first = store.messages.firstWhere((m) => m['role'] == 'user');
      expect(first['audio'], isNotNull);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is RecordMediaView && widget.audio != null,
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('选择图片'));
      await flush(tester);
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      final users = store.messages.where((m) => m['role'] == 'user').toList();
      expect(users.last['audio'], isNull);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is RecordMediaView && widget.audio != null,
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('images select vision automatically without a picker', (
    tester,
  ) async {
    final engine = VisionEngine();
    await attach(tester, engine);
    expect(find.byKey(const ValueKey('conversation-model')), findsNothing);
    await tester.tap(find.byTooltip('发送'));
    await flush(tester);
    expect(engine.replyModel, 'vision');
    expect(store.selected, {'chat': 'chat', 'vision': 'vision'});
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'follow-up image questions reuse image and ordinary questions return to text',
    (tester) async {
      final engine = VisionEngine();
      await attach(tester, engine);
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      final image = engine.lastImage;
      await tester.enterText(find.byType(TextField), '刚才图片里一共多少钱？');
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      expect(engine.replyModel, 'vision');
      expect(engine.lastImage, image);
      final followup = store.messages.lastWhere((m) => m['role'] == 'user');
      expect(followup['image'], isNull);
      expect(followup['contextImage'], image);
      expect(
        find.byKey(const ValueKey('composer-image-preview')),
        findsNothing,
      );
      await tester.enterText(find.byType(TextField), '讲个笑话');
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      expect(engine.replyModel, 'chat');
      expect(engine.lastImage, isNull);
      for (final text in ['你好', '今天心情不错']) {
        await tester.enterText(find.byType(TextField), text);
        await tester.tap(find.byTooltip('发送'));
        await flush(tester);
        final plain = store.messages.lastWhere((m) => m['role'] == 'user');
        expect(plain['image'], isNull);
        expect(plain['contextImage'], isNull);
        expect(engine.lastImage, isNull);
      }
      expect(
        store.messages.where((m) => m['role'] == 'user' && m['image'] != null),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'photo reply and automatic extraction both use vision with recognized content',
    (tester) async {
      final engine = VisionEngine();
      await attach(tester, engine);
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      expect(engine.replyModel, 'vision');
      expect(engine.extractionRole, ModelRole.vision);
      expect(engine.extractedText, contains('金额20元'));
      expect(find.textContaining('自动整理失败'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'image-only complete receipt saves every transaction after replying',
    (tester) async {
      final engine = VisionEngine()..receipt = true;
      await attach(tester, engine);
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      final user = store.messages.firstWhere((m) => m['role'] == 'user');
      expect(user['text'], '');
      expect(find.text('请描述并整理这张图片中的信息。'), findsNothing);
      expect(find.text('确认记录'), findsNothing);
      final proposals = (await tester.runAsync(
        () => RecordRepository(store.database).proposals(),
      ))!;
      expect(proposals.single.items, hasLength(2));
      expect(proposals.single.status, 'accepted');
      expect(
        await tester.runAsync(() => store.database.query('records')),
        hasLength(2),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'editing an image restores attachment and caption without sending',
    (tester) async {
      final engine = VisionEngine();
      await attach(tester, engine);
      await tester.enterText(find.byType(TextField), '这张账单');
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      final count = store.messages.length;
      final original = store.messages.firstWhere((m) => m['role'] == 'user');
      await tester.longPress(find.text('这张账单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('composer-image-preview')),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '这张账单',
      );
      expect(store.messages.length, count);
      expect(original['image'], isNotNull);
      await tester.tap(find.byTooltip('移除图片'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('composer-image-preview')),
        findsNothing,
      );
      expect(store.messages.length, count);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'input accepts the next draft while image extraction is pending',
    (tester) async {
      final gate = Completer<void>();
      final engine = VisionEngine()..imageExtractionGate = gate;
      await attach(tester, engine);
      await tester.tap(find.byTooltip('发送'));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        find.byKey(const ValueKey('assistant-waiting-bubble')),
        findsOneWidget,
      );
      expect(find.text('正在识别图片并整理可记录的信息…'), findsOneWidget);
      expect(engine.replyPrompt, isNull);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(
                IconButton,
                Icons.add_photo_alternate_outlined,
              ),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('选择图片'));
      await flush(tester);
      expect(
        find.byKey(const ValueKey('composer-image-preview')),
        findsOneWidget,
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput.enterText('下一条消息');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '下一条消息',
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('send-message')))
            .onPressed,
        isNotNull,
      );
      gate.complete();
      await flush(tester);
      expect(engine.replyPrompt, contains('早餐店付款金额20元'));
      expect(engine.imageExtractions, 1);
      expect(
        find.byKey(const ValueKey('assistant-waiting-bubble')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('composer-image-preview')),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '下一条消息',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'record these three identities reuses original image and saves separate people',
    (tester) async {
      final engine = VisionEngine()..identities = true;
      await attach(tester, engine);
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      final sourceImage = store.messages.firstWhere(
        (m) => m['role'] == 'user',
      )['image'];
      const request = '帮我记录这三个人的身份证信息';
      await tester.enterText(find.byType(TextField), request);
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      expect(engine.extractionImage, sourceImage);
      expect(engine.imageExtractions, 1);
      expect(engine.extractedText, contains(request));
      expect(engine.extractedText, contains('张甲 身份证号'));
      final rows = (await tester.runAsync(
        () => store.database.query('records'),
      ))!;
      expect(rows, hasLength(3));
      final payloads = rows
          .map((row) => jsonDecode(row['payload'] as String))
          .toList();
      expect(payloads.map((p) => p['title']), ['张甲', '李乙', '王丙']);
      expect(payloads.every((p) => p['kind'] == 'note'), isTrue);
      expect(
        (payloads.first['fields'] as List).last['value'],
        '110101199001010010',
      );
      expect(find.textContaining('未识别到可记录'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('complete mixed image facts automatically save each type', (
    tester,
  ) async {
    final engine = VisionEngine()..mixed = true;
    await attach(tester, engine);
    await tester.tap(find.byTooltip('发送'));
    await flush(tester);
    final draft = (await tester.runAsync(
      () => RecordRepository(store.database).proposals(),
    ))!.single;
    expect(draft.status, 'accepted');
    expect(draft.items.map((item) => item['kind']), [
      'date',
      'phone',
      'note',
      'expense',
    ]);
    expect(
      await tester.runAsync(() => store.database.query('records')),
      hasLength(4),
    );
    expect(find.text('确认记录'), findsNothing);
    final rows = (await tester.runAsync(
      () => store.database.query('records'),
    ))!;
    expect(rows.map((row) => row['kind']), [
      'date',
      'phone',
      'note',
      'expense',
    ]);
    expect(engine.imageExtractions, 1);
    expect(
      store.messages.any((m) => (m['recordIds'] as List? ?? []).length == 4),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'complete OCR phone facts save even without vision structured records',
    (tester) async {
      final engine = VisionEngine()..phoneOnlyOcr = true;
      await attach(tester, engine);
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      expect(engine.extractedText, contains('张三电话13800138000'));
      final draft = (await tester.runAsync(
        () => RecordRepository(store.database).proposals(),
      ))!.single;
      expect(draft.status, 'accepted');
      expect(draft.items.single['kind'], 'phone');
      expect(
        await tester.runAsync(() => store.database.query('records')),
        hasLength(1),
      );
      expect(find.text('确认记录'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'failed photo reply retains completed image analysis and reports error',
    (tester) async {
      final engine = VisionEngine()..fail = true;
      await attach(tester, engine);
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      expect(engine.extractedText, contains('早餐店付款金额20元'));
      expect(find.textContaining('图片识别模型“视觉模型”生成失败'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('failed image analysis prevents any chat reply', (tester) async {
    final engine = VisionEngine()..failImage = true;
    await attach(tester, engine);
    await tester.tap(find.byTooltip('发送'));
    await flush(tester);
    expect(engine.replyPrompt, isNull);
    expect(find.textContaining('图片分析未完成'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'missing photo model reports vision path, not missing text model',
    () async {
      await expectLater(
        AiEngine().reply(store, '看图', image: photo).toList(),
        throwsA(
          predicate(
            (e) => '$e'.contains('图片识别模型“视觉模型”文件不存在') && !'$e'.contains('文字模型'),
          ),
        ),
      );
      await expectLater(
        AiEngine().extract(
          store,
          '收据20元',
          DateTime.now(),
          role: ModelRole.vision,
        ),
        throwsA(predicate((e) => '$e'.contains('图片识别模型“视觉模型”文件不存在'))),
      );
    },
  );
  test('missing projection is reported before loading model', () async {
    final path = '${root.path}/exists.gguf';
    await File(path).writeAsBytes([1]);
    store.models['vision']['path'] = path;
    await expectLater(
      AiEngine().reply(store, '看图', image: photo).toList(),
      throwsA(predicate((e) => '$e'.contains('缺少视觉投影文件 mmproj'))),
    );
  });
}
