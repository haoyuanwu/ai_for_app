import 'dart:convert';

import 'package:nobodywho/nobodywho.dart' as nw;

/// Qwen3.5's non-thinking text and vision profiles differ. Other families keep
/// their runtime defaults; extraction uses a separate low-randomness sampler.
class InferenceParameters {
  const InferenceParameters({
    required this.temperature,
    required this.topP,
    required this.topK,
    this.presencePenalty = 0,
  });
  final double temperature, topP, presencePenalty;
  final int topK;

  static InferenceParameters? chat(
    Map<String, dynamic> model, {
    bool vision = false,
  }) {
    final identity = [
      'name',
      'catalogId',
      'path',
    ].map((key) => model[key] ?? '').join(' ');
    if (!RegExp(
      r'qwen[\s_-]*3[._-]?5',
      caseSensitive: false,
    ).hasMatch(identity)) {
      return null;
    }
    return vision
        ? const InferenceParameters(
            temperature: .7,
            topP: .8,
            topK: 20,
            presencePenalty: 1.5,
          )
        : const InferenceParameters(
            temperature: 1,
            topP: 1,
            topK: 20,
            presencePenalty: 2,
          );
  }

  static const extraction = InferenceParameters(
    temperature: .2,
    topP: .8,
    topK: 20,
  );

  nw.SamplerConfig sampler({Map<String, dynamic>? schema}) {
    var builder = nw.SamplerBuilder();
    if (schema != null) {
      builder = builder.constrainWithJsonSchema(schema: jsonEncode(schema));
    }
    if (presencePenalty != 0) {
      builder = builder.penalties(
        penaltyLastN: 64,
        penaltyRepeat: 1,
        penaltyFreq: 0,
        penaltyPresent: presencePenalty,
      );
    }
    builder = builder
        .topK(topK: topK)
        .topP(topP: topP, minKeep: 1)
        .temperature(temperature: temperature);
    return builder.dist();
  }
}
