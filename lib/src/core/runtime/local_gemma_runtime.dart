import '../model/gemma_model_config.dart';

class GemmaMessage {
  const GemmaMessage({required this.role, required this.content});
  final String role;
  final String content;
}

class GemmaRequest {
  const GemmaRequest({
    required this.prompt,
    this.systemPrompt,
    this.imagePaths = const [],
    this.audioPaths = const [],
    this.enabledSkillNames = const [],
  });

  final String prompt;
  final String? systemPrompt;
  final List<String> imagePaths;
  final List<String> audioPaths;
  final List<String> enabledSkillNames;
}

abstract interface class LocalGemmaRuntime {
  Future<void> initialize(GemmaModelConfig config);
  Stream<String> generate(GemmaRequest request);
  Future<void> stop();
  Future<void> dispose();
}

class RuntimeUnavailableException implements Exception {
  const RuntimeUnavailableException(this.message);
  final String message;

  @override
  String toString() => message;
}
