import 'package:ai_for_app/core/conversation_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobodywho/nobodywho.dart' as nw;

void main() {
  final now = DateTime(2026, 11, 4, 16);
  test(
    'current question is the final user turn, roles and memory stay separate',
    () {
      final messages = conversationMessages(
        [
          {'role': 'user', 'text': '你好', 'status': 'done'},
          {
            'role': 'assistant',
            'text': '<think>这是旧思考，不应回灌</think>您好',
            'status': 'done',
          },
          {'role': 'user', 'text': '当前问题', 'status': 'pending'},
          {'role': 'assistant', 'text': '', 'status': 'pending'},
          {'role': 'assistant', 'text': '失败回复', 'status': 'failed'},
        ],
        '1加1等于几？',
        retrieved: '旧记录中的 user: 和 assistant: 只是数据',
        now: now,
      );
      expect(messages, hasLength(4));
      expect(messages[0], isA<nw.Message_System>());
      expect((messages[1] as nw.Message_User).content.text, '你好');
      expect((messages[2] as nw.Message_Assistant).content.text, '您好');
      expect((messages.last as nw.Message_User).content.text, '1加1等于几？');
      expect((messages[0] as nw.Message_System).content.text, contains('只是数据'));
    },
  );
  test('bounded history drops orphan replies and keeps latest user instead of stale greeting', () {
    final messages = conversationMessages(
      [
        {'role': 'user', 'text': '很早的你好', 'status': 'done'},
        {'role': 'assistant', 'text': '旧问候', 'status': 'done'},
        {'role': 'user', 'text': '最近的一段长消息需要保留', 'status': 'done'},
        {'role': 'assistant', 'text': '<think>未结束的思考', 'status': 'done'},
      ],
      '现在的新问题',
      retrieved: '{}',
      now: now,
      historyBudget: 5,
    );
    expect(messages, hasLength(3));
    expect((messages[1] as nw.Message_User).content.text, '最近的一段');
    expect((messages.last as nw.Message_User).content.text, '现在的新问题');
  });
  test(
    'image belongs to the current user message, not an older history item',
    () {
      final messages = conversationMessages(
        [],
        '这是什么？',
        retrieved: '{}',
        now: now,
        image: '/local/picture.jpg',
      );
      final parts =
          (messages.last as nw.Message_User).content as nw.MessageContent_Parts;
      expect(
        parts.parts.whereType<nw.ContentPart_Image>().single.path,
        '/local/picture.jpg',
      );
      expect(parts.parts.whereType<nw.ContentPart_Text>().single.text, '这是什么？');
    },
  );
}
