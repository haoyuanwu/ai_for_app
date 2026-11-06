import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// Bounded header inspection: never load the model weights into the UI isolate.
class GgufContextMetadata {
  static Future<void> enrich(Map<String, dynamic> model) async {
    if (model['format'] != 'gguf' || model['contextMetadataVersion'] == 1) {
      return;
    }
    final path = model['path'];
    if (path is! String) return;
    final metadata = await read(path);
    model.remove('trainedContextLength');
    model.remove('architecture');
    model.addAll(metadata);
    model['contextMetadataVersion'] = 1;
  }

  static Future<Map<String, dynamic>> read(String path) => Isolate.run(() {
    RandomAccessFile? file;
    try {
      file = File(path).openSync();
      final bytes = file.readSync(
        math.min(file.lengthSync(), 32 * 1024 * 1024),
      );
      return parse(bytes);
    } on FileSystemException {
      return <String, dynamic>{};
    } finally {
      file?.closeSync();
    }
  });

  static Map<String, dynamic> parse(Uint8List bytes) {
    try {
      final reader = _Reader(bytes);
      if (ascii.decode(reader.take(4)) != 'GGUF') return {};
      final littleVersion = ByteData.sublistView(
        bytes,
        4,
        8,
      ).getUint32(0, Endian.little);
      reader.endian = littleVersion == 2 || littleVersion == 3
          ? Endian.little
          : Endian.big;
      final version = reader.uint(4);
      if (version != 2 && version != 3) return {};
      reader.uint(8); // tensor count
      final count = reader.uint(8);
      if (count > 1000000) return {};
      String? architecture;
      final contexts = <String, int>{};
      for (var i = 0; i < count; i++) {
        final key = reader.string();
        final type = reader.uint(4);
        if (key == 'general.architecture' && type == 8) {
          architecture = reader.string();
        } else if (key.endsWith('.context_length') &&
            [0, 2, 4, 10].contains(type)) {
          contexts[key] = reader.uint({0: 1, 2: 2, 4: 4, 10: 8}[type]!);
        } else {
          reader.skipValue(type);
        }
        final length = contexts['$architecture.context_length'];
        if (architecture != null &&
            length != null &&
            length > 0 &&
            length <= 0x7fffffff) {
          return {'architecture': architecture, 'trainedContextLength': length};
        }
      }
      return architecture == null ? {} : {'architecture': architecture};
    } on FormatException {
      return {};
    } on RangeError {
      return {};
    }
  }
}

class _Reader {
  _Reader(this.bytes);
  final Uint8List bytes;
  var position = 0;
  var endian = Endian.little;
  Uint8List take(int n) {
    if (n < 0 || position + n > bytes.length) {
      throw const FormatException('Incomplete metadata');
    }
    final result = Uint8List.sublistView(bytes, position, position + n);
    position += n;
    return result;
  }

  void skip(int n) {
    if (n < 0 || position + n > bytes.length) {
      throw const FormatException('Incomplete metadata');
    }
    position += n;
  }

  int uint(int size) {
    final data = ByteData.sublistView(take(size));
    return switch (size) {
      1 => data.getUint8(0),
      2 => data.getUint16(0, endian),
      4 => data.getUint32(0, endian),
      8 => data.getUint64(0, endian),
      _ => throw const FormatException('Invalid type'),
    };
  }

  String string() => utf8.decode(take(uint(8)));
  void skipValue(int type, [int depth = 0]) {
    if (depth > 4) throw const FormatException('Nested metadata');
    const sizes = {
      0: 1,
      1: 1,
      2: 2,
      3: 2,
      4: 4,
      5: 4,
      6: 4,
      7: 1,
      10: 8,
      11: 8,
      12: 8,
    };
    if (sizes.containsKey(type)) {
      skip(sizes[type]!);
      return;
    }
    if (type == 8) {
      skip(uint(8));
      return;
    }
    if (type != 9) throw const FormatException('Unknown metadata type');
    final elementType = uint(4);
    final count = uint(8);
    if (count < 0 || count > 10000000) {
      throw const FormatException('Oversize array');
    }
    if (sizes.containsKey(elementType)) {
      skip(count * sizes[elementType]!);
      return;
    }
    for (var i = 0; i < count; i++) {
      skipValue(elementType, depth + 1);
    }
  }
}
