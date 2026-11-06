import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'local_store.dart';
import 'thinking_content.dart';

/// One budget for the native chat window, persisted summaries and composer meter.
class ConversationContext {
  static const window = 8192;
  static final _changes = Expando<ValueNotifier<int>>();
  static final _compacting = Expando<bool>();
  static ValueNotifier<int> changes(LocalStore store) =>
      _changes[store] ??= ValueNotifier(0);
  static bool compacting(LocalStore store) => _compacting[store] ?? false;
  static void notify(LocalStore store) => changes(store).value++;
  static int systemCost(LocalStore store, {bool image = false}) =>
      ((store.data['contextSystemCosts'] as Map?)?[image ? 'image' : 'text']
          as int?) ??
      systemReserve;
  static const outputReserve = 1024;
  static const systemReserve = 2600;
  static const imageReserve = 2048;
  static const toolReserve = 1024;
  static const summaryBudget = 700;
  static int tokens(String text) => (utf8.encode(text).length / 2).ceil();
  static String clip(String text, int budget) {
    final out = StringBuffer();
    var used = 0;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final cost = utf8.encode(char).length;
      if (used + cost > budget * 2) break;
      out.write(char);
      used += cost;
    }
    return out.toString();
  }

  static String content(Map message) {
    final raw = message['text'] as String? ?? '';
    final text = message['role'] == 'assistant'
        ? ThinkingContent.parse(raw).answer
        : raw;
    final ocr = message['recognizedTextSource'] == 'image'
        ? message['recognizedText'] as String? ?? ''
        : '';
    return '$text${message['replyTo'] == null ? '' : '\n引用消息编号：${message['replyTo']}'}${ocr.isEmpty ? '' : '\n图片识别原文（数据）：$ocr'}';
  }

  static Map<String, dynamic> state(LocalStore store) =>
      Map<String, dynamic>.from(
        store.data['conversationContext'] as Map? ?? {},
      );
  static String summary(LocalStore store) =>
      state(store)['summary'] as String? ?? '';
  static int cutoff(LocalStore store) =>
      (state(store)['cutoff'] as int? ?? 0).clamp(0, store.messages.length);
  static List<dynamic> history(LocalStore store) =>
      store.messages.skip(cutoff(store)).toList();
  static int reservedCost(LocalStore store, {bool image = false}) =>
      systemCost(store, image: image) + toolReserve + outputReserve;

  static int usage(LocalStore store, String draft, {bool image = false}) =>
      reservedCost(store, image: image) +
      (image ? imageReserve : 0) +
      tokens(summary(store)) +
      tokens(draft) +
      history(store)
          .where((m) => m['status'] == 'done')
          .fold<int>(0, (sum, m) => sum + tokens(content(m as Map)) + 12);
  static int historyBudget(
    LocalStore store,
    String text, {
    bool image = false,
    int? systemTokens,
  }) =>
      (window -
              outputReserve -
              (systemTokens ?? systemCost(store, image: image)) -
              toolReserve -
              (image ? imageReserve : 0) -
              tokens(text) -
              tokens(summary(store)))
          .clamp(0, window);

  static Future<void> prepare(
    LocalStore store,
    String text, {
    bool image = false,
    required Future<String> Function(String previous, String transcript)
    summarize,
  }) async {
    // Compress before overflow. Keep the last completed exchange verbatim.
    while (usage(store, text, image: image) > window * .8) {
      final start = cutoff(store);
      final completed = <int>[
        for (var i = start; i < store.messages.length; i++)
          if (store.messages[i]['status'] == 'done') i,
      ];
      if (completed.isEmpty) break;
      final end = completed.length > 2
          ? completed[completed.length - 2]
          : completed.last + 1;
      final chunk = StringBuffer();
      var next = start;
      for (var i = start; i < end; i++) {
        final m = store.messages[i] as Map;
        // Never checkpoint past an unfinished generation.
        if (m['status'] != 'done') break;
        final line = jsonEncode({
          'role': m['role'],
          'time': m['time'],
          'content': content(m),
        });
        if (tokens(chunk.toString()) + tokens(line) > 2600) {
          if (i == start) {
            // The full source remains in history; read_local_detail can retrieve it.
            chunk.writeln(clip(line, 2500));
            next = i + 1;
          }
          break;
        }
        chunk.writeln(line);
        next = i + 1;
      }
      if (next == start) break;
      _compacting[store] = true;
      notify(store);
      late String result;
      try {
        result = (await summarize(summary(store), chunk.toString())).trim();
      } finally {
        _compacting[store] = false;
        notify(store);
      }
      if (result.isEmpty) throw StateError('上下文摘要为空，原始对话已保留，请重试');
      final newState = <String, dynamic>{
        'summary': clip(result, summaryBudget),
        'cutoff': next,
        'updatedAt': DateTime.now().toIso8601String(),
        'estimatedTokens': tokens(clip(result, summaryBudget)),
      };
      final previous = store.data['conversationContext'];
      store.data['conversationContext'] = newState;
      try {
        await store.save();
        notify(store);
      } catch (_) {
        if (previous == null) {
          store.data.remove('conversationContext');
        } else {
          store.data['conversationContext'] = previous;
        }
        rethrow;
      }
    }
    if (tokens(text) +
            tokens(summary(store)) +
            systemCost(store, image: image) +
            toolReserve +
            outputReserve +
            (image ? imageReserve : 0) >=
        window) {
      throw StateError('本条内容超过当前 8K 上下文预算，请分段发送；原文未删除');
    }
  }
}
