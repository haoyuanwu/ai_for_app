import 'package:ai_for_app/core/conversation_route.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:io';

void main() {
  final history = [
    {'role': 'user', 'status': 'done', 'image': '/old.png'},
    {'role': 'assistant', 'status': 'done', 'text': '旧图片'},
    {'role': 'user', 'status': 'done', 'image': '/recent.png'},
    {'role': 'assistant', 'status': 'done', 'text': '新图片'},
  ];
  test('new attachment takes priority over previous image', () {
    final route = ConversationRoute.resolve(
      '这张图片',
      attachedImage: '/new.png',
      history: history,
    );
    expect(route.role, ModelRole.vision);
    expect(route.image, '/new.png');
  });
  test('references use most recent completed user image', () {
    for (final text in ['刚才图片上是什么？', '上一张是什么颜色', '图中有几个人', '这张照片里写了什么']) {
      final route = ConversationRoute.resolve(text, history: history);
      expect(route.role, ModelRole.vision);
      expect(route.image, '/recent.png');
    }
  });
  test('short follow-ups retain photo context until topic changes', () {
    expect(
      ConversationRoute.resolve('多少钱？', history: history).image,
      '/recent.png',
    );
    final changed = [
      ...history,
      {'role': 'user', 'status': 'done', 'text': '讲个笑话'},
    ];
    expect(
      ConversationRoute.resolve('继续', history: changed).role,
      ModelRole.chat,
    );
    expect(
      ConversationRoute.resolve('确认', history: history).role,
      ModelRole.chat,
    );
  });
  test(
    'deictic record requests refer to immediate image but not a changed topic',
    () {
      for (final request in [
        '帮我记录这三个人的身份证信息',
        '把他们的信息保存下来',
        '记下这几个人的姓名',
        '保存上面的内容',
      ]) {
        expect(
          ConversationRoute.resolve(request, history: history).image,
          '/recent.png',
        );
        expect(
          ConversationRoute.resolve(
            request,
            history: [
              ...history,
              {'role': 'user', 'status': 'done', 'text': '换个话题'},
            ],
          ).image,
          isNull,
        );
      }
      expect(
        ConversationRoute.resolve('帮我记录今天体重65公斤', history: history).image,
        isNull,
      );
    },
  );
  test('unrelated text and record operations stay on chat', () {
    for (final text in ['你好', '查一下我的生日', '删除我的收据记录', '图片文件怎么导出']) {
      expect(
        ConversationRoute.resolve(text, history: history).role,
        ModelRole.chat,
      );
    }
    expect(
      ConversationRoute.resolve('刚才图片是什么', history: []).role,
      ModelRole.chat,
    );
  });
  test('no preference chooses compatible installed model without changing settings', () {
    final store = LocalStore(Directory.systemTemp);
    store.models.addAll({
      'text': {
        'name': '文字',
        'capabilities': ['chat'],
      },
      'multi': {
        'name': '多模态',
        'capabilities': ['chat', 'vision'],
      },
      'speech': {
        'name': '语音',
        'capabilities': ['speech'],
      },
    });
    expect(store.model(ModelRole.chat)?['name'], '文字');
    expect(store.model(ModelRole.vision)?['name'], '多模态');
    expect(store.model(ModelRole.speech)?['name'], '语音');
    expect(store.selected, isEmpty);
    store.selected['chat'] = 'multi';
    expect(store.model(ModelRole.chat)?['name'], '多模态');
    store.models.remove('multi');
    expect(store.model(ModelRole.vision), isNull);
  });
  test('one multi-capability model can be shared by all supported roles', () {
    final store = LocalStore(Directory.systemTemp);
    store.models['shared'] = {
      'name': '共享模型',
      'capabilities': ['chat', 'vision', 'speech'],
    };
    for (final role in ModelRole.values) {
      expect(store.model(role)?['name'], '共享模型');
    }
  });
}
