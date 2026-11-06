import 'background_execution.dart';

import 'dart:convert';
import 'dart:async';

import 'context_allocation.dart';

import 'package:nobodywho/nobodywho.dart' as nw;
// NobodyWho 6's public Chat wrapper does not expose disposal of its Rust owner.
// Keep the version-specific ownership bridge here, rather than relying on Dart GC
// to account for hundreds of MB of model weights allocated outside the heap.
// ignore: implementation_imports
import 'package:nobodywho/src/rust/lib.dart' as native;

class ManagedNativeTool {
  ManagedNativeTool({
    required Function function,
    required String name,
    required String description,
  }) {
    Map<String, dynamic>? schema;
    handle = native.newToolImpl(
      function: (json) async {
        try {
          final args = jsonDecode(json) as Map<String, dynamic>;
          final result = Function.apply(function, [], {
            for (final entry in args.entries)
              Symbol(entry.key): nw.jsonConversion(
                schema!['properties'][entry.key],
                entry.value,
              ),
          });
          return '${result is Future ? await result : result}';
        } catch (error) {
          return 'Error: $error';
        }
      },
      name: name,
      description: description,
      runtimeType: function.runtimeType.toString(),
      parameterDescriptions: const {},
    );
    schema = jsonDecode(handle.getSchemaJson()) as Map<String, dynamic>;
  }
  late final native.RustTool handle;
  void dispose() {
    if (!handle.isDisposed) handle.dispose();
  }
}

abstract interface class ManagedNativeResource {
  void dispose();
}

/// Holds the same admission slot while an ONNX worker owns native weights.
class NativeOperationToken implements ManagedNativeResource {
  @override
  void dispose() {}
}

class ManagedNativeSpeechRecognizer implements ManagedNativeResource {
  ManagedNativeSpeechRecognizer._(this._handle);
  final native.RustSpeechToText _handle;
  static Future<ManagedNativeSpeechRecognizer> load(
    String path,
    String quantization,
  ) async => ManagedNativeSpeechRecognizer._(
    await native.RustSpeechToText.load(
      source: path,
      language: 'zh',
      quantization: quantization,
    ),
  );
  Future<String> transcribe(String path) async {
    final tokens = _handle.transcribeFile(path: path);
    try {
      return await tokens.completed();
    } finally {
      tokens.dispose();
    }
  }

  @override
  void dispose() {
    if (!_handle.isDisposed) _handle.dispose();
  }
}

class ManagedNativeChat implements ManagedNativeResource {
  ManagedNativeChat._(this._handle, this._tools, this._releaseBackground);
  final Future<void> Function() _releaseBackground;
  final native.RustChat _handle;
  final List<ManagedNativeTool> _tools;

  static Future<ManagedNativeChat> fromPath({
    required String modelPath,
    String? projectionModelPath,
    int contextSize = 4096,
    String? systemPrompt,
    Map<String, bool> templateVariables = const {},
    List<ManagedNativeTool> tools = const [],
    nw.SamplerConfig? sampler,
    bool useGpu = false,
  }) async {
    final releaseBackground = await BackgroundExecution.acquire();
    try {
      await BackgroundExecution.waitUntilAllowed();
      final handle = await ContextAllocation.load(
        useGpu: useGpu,
        create: (gpu) => native.RustChat.fromPath(
          modelPath: modelPath,
          projectionModelPath: projectionModelPath,
          contextSize: contextSize,
          systemPrompt: systemPrompt,
          templateVariables: templateVariables,
          tools: tools.map((tool) => tool.handle).toList(),
          sampler: sampler,
          useGpu: gpu,
        ),
      );
      return ManagedNativeChat._(handle, tools, releaseBackground);
    } catch (_) {
      await releaseBackground();
      for (final tool in tools) {
        tool.dispose();
      }
      rethrow;
    }
  }

  Future<void> resetHistory() => _handle.resetHistory();
  ManagedNativeTokens ask(String text) =>
      ManagedNativeTokens(_handle.ask(text));
  ManagedNativeTokens complete(List<nw.Message> messages) =>
      ManagedNativeTokens(_handle.complete(messages: messages));
  ManagedNativeTokens askWithPrompt(nw.Prompt prompt) => ManagedNativeTokens(
    _handle.askWithPrompt(
      parts: [
        for (final part in prompt.parts)
          switch (part) {
            nw.TextPart(:final text) => native.ContentPart.text(text: text),
            nw.ImagePart(:final path) => native.ContentPart.image(path: path),
            nw.AudioPart(:final path) => native.ContentPart.audio(path: path),
          },
      ],
    ),
  );
  @override
  void dispose() {
    unawaited(_releaseBackground());
    if (_handle.isDisposed) return;
    _handle.dispose();
    for (final tool in _tools) {
      tool.dispose();
    }
  }
}

Object readableCompletionError(Object error) {
  if (error is native.CompletionError) {
    if (!error.isDisposed) error.dispose();
    return StateError(
      '本地模型生成中断，插件未返回详细原因。可能是输入或图片超出模型容量，或模型与视觉投影不匹配。请尝试较小图片，并确认主模型与 mmproj 配套。',
    );
  }
  return error;
}

class ManagedNativeTokens extends Stream<String> {
  ManagedNativeTokens(this._handle);
  final native.RustTokenStream _handle;
  Stream<String> _generate() async* {
    try {
      while (true) {
        await BackgroundExecution.waitUntilAllowed();
        final token = await _handle.nextToken();
        BackgroundExecution.progress();
        if (token == null) break;
        yield token;
      }
    } catch (error) {
      throw readableCompletionError(error);
    } finally {
      if (!_handle.isDisposed) _handle.dispose();
    }
  }

  Future<String> completed() => _generate().join();

  @override
  StreamSubscription<String> listen(
    void Function(String)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _generate().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}
