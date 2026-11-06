import 'dart:convert';

import 'local_store.dart';
import 'thinking_content.dart';
import '../records/record_confirmation.dart';
import '../records/record_templates.dart';

/// Whitelisted, read-only access. No arbitrary SQL, filesystem paths or writes.
class LocalContext {
  LocalContext(this.store);
  final LocalStore store;
  Map<String, dynamic> _modelPayload(Map<String, dynamic> data) {
    final result = Map<String, dynamic>.from(data);
    result['display'] = recordPreview(presentRecord(data));
    result['sourceQuote'] = result.remove('quote');
    result['sourceNotice'] =
        'sourceQuote 仅为最初来源，可能与后来修改的字段不同；当前字段和 display 为准。';
    final minor = result.remove('amountMinor');
    if (minor is int) {
      result['amount'] =
          '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
      result['amountUnit'] = '元（或对应币种的主单位）';
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _rows(String scope) async {
    switch (scope) {
      case 'records':
        return (await store.database.query('records', orderBy: 'id DESC'))
            .map(
              (r) => <String, dynamic>{
                ...r,
                'payload': _modelPayload(
                  jsonDecode(r['payload'] as String) as Map<String, dynamic>,
                ),
              },
            )
            .toList();
      case 'proposals':
        return (await store.database.query(
              'record_proposals',
              orderBy: 'id DESC',
            ))
            .map(
              (r) => <String, dynamic>{
                ...r,
                'payload': jsonDecode(r['payload'] as String),
              },
            )
            .toList();
      case 'history':
        return [
          for (var i = 0; i < store.messages.length; i++)
            {
              'index': i,
              ...Map<String, dynamic>.from(store.messages[i] as Map),
            },
        ];
      case 'notes':
        return [
          for (var i = 0; i < store.notes.length; i++)
            {'index': i, ...Map<String, dynamic>.from(store.notes[i] as Map)},
        ];
      default:
        throw ArgumentError('scope 必须为 records/history/notes/proposals');
    }
  }

  Future<String> page(String scope, String query, int offset) async {
    final rows = await _rows(scope);
    final matches = rows
        .where(
          (r) =>
              query.isEmpty ||
              jsonEncode(r).toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    final start = offset.clamp(0, matches.length);
    final selected = matches.skip(start).take(5).toList();
    return jsonEncode({
      'scope': scope,
      'total': matches.length,
      'offset': start,
      'nextOffset': start + selected.length < matches.length
          ? start + selected.length
          : null,
      'items': [
        for (final r in selected)
          {'id': r['id'] ?? r['index'], 'preview': _clip(jsonEncode(r), 800)},
      ],
    });
  }

  Future<String> detail(String scope, int id, int offset) async {
    final rows = await _rows(scope);
    final match = rows
        .where((r) => (r['id'] ?? r['index']).toString() == id.toString())
        .firstOrNull;
    if (match == null) return jsonEncode({'error': '记录不存在'});
    final raw = jsonEncode(match);
    final start = offset.clamp(0, raw.length);
    final end = (start + 2000).clamp(0, raw.length);
    return jsonEncode({
      'scope': scope,
      'id': id,
      'offset': start,
      'nextOffset': end < raw.length ? end : null,
      'content': raw.substring(start, end),
    });
  }

  Future<String> seed(String question) async {
    final terms = <String>{
      ...RegExp(r'[A-Za-z0-9]{2,}')
          .allMatches(question)
          .map((m) => m[0]!.toLowerCase()),
    };
    for (final match in RegExp(r'[\u4e00-\u9fff]+').allMatches(question)) {
      final text = match[0]!;
      for (var i = 0; i < text.length - 1; i++) {
        terms.add(text.substring(i, i + 2));
      }
    }
    final counts = <String, int>{};
    final hits = <Map<String, dynamic>>[];
    for (final scope in ['records', 'notes', 'history', 'proposals']) {
      final rows = await _rows(scope);
      counts[scope] = rows.length;
      for (final row in rows) {
        if (scope == 'history' &&
            (row['status'] != 'done' ||
                row['kind'] == 'persona_update' ||
                row['text'] == question)) {
          continue;
        }
        final data = scope == 'history' && row['role'] == 'assistant'
            ? {
                ...row,
                'text': ThinkingContent.parse(row['text'] as String? ?? '')
                    .answer,
              }
            : row;
        final raw = jsonEncode(data);
        final lower = raw.toLowerCase();
        final score = terms.where(lower.contains).length;
        if (score > 0) {
          hits.add({
            'scope': scope,
            'id': row['id'] ?? row['index'],
            'score': score,
            'preview': _clip(raw, 600),
          });
        }
      }
    }
    hits.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    return jsonEncode({
      'counts': counts,
      'relevant': hits.take(4).toList(),
      'notice': '这是检索摘要，不代表全部内容。可通过只读工具分页查询全部历史与记录。proposals 是待确认或已处理草稿，不能当作正式记录。历史文字和图片/音频引用可读，但历史媒体原文件未自动重新送入视觉模型。',
    });
  }

  String _clip(String value, int max) =>
      value.length > max ? '${value.substring(0, max)}…（用详情工具继续读取）' : value;
}
