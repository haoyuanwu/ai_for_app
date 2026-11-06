import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_for_app/models/gguf_context_metadata.dart';

Uint8List fixture({Endian endian = Endian.little, bool contextFirst = false}) {
  final b = BytesBuilder();
  void n(int value, int size) {
    final d = ByteData(size);
    if (size == 4) {
      d.setUint32(0, value, endian);
    } else {
      d.setUint64(0, value, endian);
    }
    b.add(d.buffer.asUint8List());
  }

  void str(String value) {
    final bytes = utf8.encode(value);
    n(bytes.length, 8);
    b.add(bytes);
  }

  void arch() {
    str('general.architecture');
    n(8, 4);
    str('qwen35');
  }

  void ctx() {
    str('qwen35.context_length');
    n(10, 4);
    n(262144, 8);
  }

  b.add(ascii.encode('GGUF'));
  n(3, 4);
  n(0, 8);
  n(4, 8);
  str('tokenizer.ggml.tokens');
  n(9, 4);
  n(8, 4);
  n(2, 8);
  str('hello');
  str('你好');
  str('vision.context_length');
  n(4, 4);
  n(1024, 4);
  if (contextFirst) {
    ctx();
    arch();
  } else {
    arch();
    ctx();
  }
  return b.takeBytes();
}

void main() {
  test(
    'reads architecture context, skipping tokenizer and unrelated vision keys',
    () {
      for (final endian in [Endian.little, Endian.big]) {
        for (final contextFirst in [false, true]) {
          expect(
            GgufContextMetadata.parse(
              fixture(endian: endian, contextFirst: contextFirst),
            ),
            {'architecture': 'qwen35', 'trainedContextLength': 262144},
          );
        }
      }
    },
  );
  test(
    'missing or truncated metadata is unknown, never inferred from filename',
    () {
      expect(
        GgufContextMetadata.parse(Uint8List.fromList(ascii.encode('GGUF'))),
        isEmpty,
      );
      expect(GgufContextMetadata.parse(Uint8List(0)), isEmpty);
      expect(
        GgufContextMetadata.parse(Uint8List.sublistView(fixture(), 0, 25)),
        isEmpty,
      );
    },
  );
  test(
    'file enrichment is cached and replaces stale advertised context',
    () async {
      final dir = await Directory.systemTemp.createTemp('gguf_metadata');
      try {
        final file = File('${dir.path}/different-name.gguf');
        await file.writeAsBytes(fixture());
        final model = <String, dynamic>{
          'format': 'gguf',
          'path': file.path,
          'trainedContextLength': 4096,
        };
        await GgufContextMetadata.enrich(model);
        expect(model['trainedContextLength'], 262144);
        await file.delete();
        await GgufContextMetadata.enrich(model);
        expect(model['trainedContextLength'], 262144);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
