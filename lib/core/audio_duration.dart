import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Read the duration of our WAV recordings without loading audio into a player.
Future<Duration?> readWaveDuration(String path) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    final length = await file.length();
    final header = await file.read(12);
    String tag(List<int> bytes, int start) =>
        String.fromCharCodes(bytes.sublist(start, start + 4));
    if (header.length != 12 ||
        tag(header, 0) != 'RIFF' ||
        tag(header, 8) != 'WAVE') {
      return null;
    }
    int? byteRate, dataLength;
    var offset = 12;
    for (var chunk = 0; chunk < 128 && offset + 8 <= length; chunk++) {
      await file.setPosition(offset);
      final bytes = await file.read(8);
      if (bytes.length != 8) return null;
      final size = ByteData.sublistView(bytes).getUint32(4, Endian.little);
      final name = tag(bytes, 0);
      if (name == 'fmt ' && size >= 16 && offset + 24 <= length) {
        final format = await file.read(16);
        if (format.length != 16) return null;
        byteRate = ByteData.sublistView(format).getUint32(8, Endian.little);
      } else if (name == 'data') {
        dataLength = math.min(size, length - offset - 8);
      }
      if (byteRate != null && byteRate > 0 && dataLength != null) {
        return Duration(
          microseconds: (dataLength * Duration.microsecondsPerSecond / byteRate)
              .round(),
        );
      }
      offset += 8 + size + size % 2;
    }
  } on FileSystemException {
    return null;
  } finally {
    await file?.close();
  }
  return null;
}
