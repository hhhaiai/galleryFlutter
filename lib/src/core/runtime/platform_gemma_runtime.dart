import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as fg;
import 'package:path_provider/path_provider.dart';

import '../model/gemma_model_config.dart';
import 'local_gemma_runtime.dart';

LocalGemmaRuntime createLocalGemmaRuntime() {
  if (Platform.isAndroid || Platform.isIOS) {
    return MethodChannelGemmaRuntime();
  }
  return PlaceholderGemmaRuntime();
}

class MethodChannelGemmaRuntime implements LocalGemmaRuntime {
  static const _methodChannel = MethodChannel(
    'com.example.gemma_local_app/runtime',
  );
  static const _eventChannel = EventChannel(
    'com.example.gemma_local_app/runtime_events',
  );

  StreamController<String>? _activeGenerationController;
  StreamSubscription<dynamic>? _eventSubscription;
  GemmaModelConfig? _config;
  bool _initialized = false;
  fg.InferenceModel? _flutterGemmaModel;
  fg.InferenceChat? _flutterGemmaChat;

  @override
  Future<void> initialize(GemmaModelConfig config) async {
    _config = config;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final modelPath = await _resolveModelPath(config);
    if (Platform.isIOS) {
      await _initializeFlutterGemma(config, modelPath);
      _initialized = true;
      return;
    }

    _eventSubscription ??= _eventChannel.receiveBroadcastStream().listen(
      _handleRuntimeEvent,
      onError: (Object error) => _activeGenerationController?.addError(error),
    );

    await _methodChannel.invokeMethod<void>('initialize', {
      'modelPath': modelPath,
      'topK': config.topK,
      'topP': config.topP,
      'temperature': config.temperature,
      'maxTokens': 1024,
      'supportImage': config.supportImage,
      'supportAudio': false,
      // Google AI Edge Gallery defaults Gemma multimodal chat to GPU.
      // CPU text-only is stable, but image prefill can fail on Android with
      // LiteRT-LM Status Code 13 / Failed to invoke the compiled model.
      'accelerator': config.supportImage ? 'gpu' : 'cpu',
    });
    _initialized = true;
  }

  Future<void> _initializeFlutterGemma(
    GemmaModelConfig config,
    String modelPath,
  ) async {
    final file = File(modelPath);
    if (!await file.exists()) {
      throw RuntimeUnavailableException(
        'iOS 模型文件不存在：$modelPath。请先在 Models 中完成下载。',
      );
    }
    final bytes = await file.length();
    if (bytes < config.sizeInBytes) {
      throw RuntimeUnavailableException(
        'iOS 模型文件不完整：$bytes / ${config.sizeInBytes} bytes。请删除后重新下载。',
      );
    }

    try {
      await fg.FlutterGemma.initialize(maxDownloadRetries: 8);
      await fg.FlutterGemma.installModel(
        modelType: fg.ModelType.gemma4,
        fileType: fg.ModelFileType.litertlm,
      ).fromFile(modelPath).install();

      _flutterGemmaModel = await fg.FlutterGemma.getActiveModel(
        maxTokens: 1024,
        preferredBackend: fg.PreferredBackend.gpu,
        supportImage: config.supportImage,
        supportAudio: false,
        maxNumImages: config.supportImage ? 1 : null,
      );
      _flutterGemmaChat = null;
    } catch (error) {
      _flutterGemmaChat = null;
      await _flutterGemmaModel?.close();
      _flutterGemmaModel = null;
      throw RuntimeUnavailableException(
        'iOS LiteRT-LM/flutter_gemma 初始化失败：$error',
      );
    }
  }

  @override
  Stream<String> generate(GemmaRequest request) async* {
    if (!Platform.isAndroid && !Platform.isIOS) {
      yield* PlaceholderGemmaRuntime(config: _config).generate(request);
      return;
    }
    if (!_initialized) {
      final config = _config ?? gemma4E2bIt;
      await initialize(config);
    }
    if (Platform.isIOS) {
      yield* _generateWithFlutterGemma(request);
      return;
    }

    final generationController = StreamController<String>();
    await _activeGenerationController?.close();
    _activeGenerationController = generationController;
    try {
      await _methodChannel.invokeMethod<void>('generate', {
        'prompt': request.prompt,
        'systemPrompt': request.systemPrompt,
        'imagePaths': request.imagePaths,
        'audioPaths': request.audioPaths,
        'enabledSkillNames': request.enabledSkillNames,
      });

      await for (final token in generationController.stream) {
        yield token;
      }
    } finally {
      if (identical(_activeGenerationController, generationController)) {
        _activeGenerationController = null;
      }
      if (!generationController.isClosed) {
        await generationController.close();
      }
    }
  }

  Stream<String> _generateWithFlutterGemma(GemmaRequest request) async* {
    final model = _flutterGemmaModel;
    if (model == null) {
      throw const RuntimeUnavailableException('iOS flutter_gemma model 尚未初始化。');
    }
    if (request.audioPaths.isNotEmpty) {
      throw const RuntimeUnavailableException(
        '当前先验证 Gemma-4 文字/图片对话；音频会在文字和图片稳定后接入。',
      );
    }
    var prompt = request.prompt;
    if (request.systemPrompt != null &&
        request.systemPrompt!.trim().isNotEmpty) {
      prompt = '[System: ${request.systemPrompt}]\n\n$prompt';
    }
    if (request.enabledSkillNames.isNotEmpty) {
      prompt =
          'Enabled skills: ${request.enabledSkillNames.join(', ')}\n\n$prompt';
    }

    // iOS flutter_gemma sessions can become invalid after a prior image failure or
    // stop. Recreate a fresh chat per request, matching Gallery-style stateless
    // image asking and preventing stale multimodal state from breaking later sends.
    await _flutterGemmaChat?.session.close();
    final chat = await model.createChat(
      temperature: _config?.temperature ?? gemma4E2bIt.temperature,
      topK: _config?.topK ?? gemma4E2bIt.topK,
      topP: _config?.topP ?? gemma4E2bIt.topP,
      supportImage: _config?.supportImage ?? gemma4E2bIt.supportImage,
      supportAudio: false,
      modelType: fg.ModelType.gemma4,
      isThinking: false,
    );
    _flutterGemmaChat = chat;

    try {
      if (request.imagePaths.isNotEmpty) {
        final firstImage = File(request.imagePaths.first);
        if (!await firstImage.exists()) {
          throw RuntimeUnavailableException(
            '图片文件不存在：${request.imagePaths.first}',
          );
        }
        await chat.addQueryChunk(
          fg.Message.withImage(
            text: _visionPrompt(prompt),
            imageBytes: await firstImage.readAsBytes(),
            isUser: true,
          ),
        );
      } else {
        await chat.addQueryChunk(fg.Message.text(text: prompt, isUser: true));
      }
    } catch (error) {
      await chat.session.close();
      if (identical(_flutterGemmaChat, chat)) _flutterGemmaChat = null;
      throw RuntimeUnavailableException('iOS 图片/文本输入失败，已重置会话，请重试：$error');
    }

    await for (final response in chat.generateChatResponseAsync()) {
      if (response is fg.TextResponse) {
        yield response.token;
      } else if (response is fg.ThinkingResponse) {
        yield response.content;
      } else if (response is fg.FunctionCallResponse) {
        yield '\n[function_call] ${response.name}: ${response.args}\n';
      }
    }
  }

  String _visionPrompt(String prompt) {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty || trimmed == '请描述这张图片。') {
      return '请直接观察并描述这张图片中的主要对象、场景、文字和可见细节。不要回答无关内容。';
    }
    return '请根据图片内容回答：$trimmed';
  }

  @override
  Future<void> stop() async {
    if (Platform.isIOS) {
      await _flutterGemmaChat?.session.stopGeneration();
      return;
    }
    if (Platform.isAndroid) {
      await _methodChannel.invokeMethod<void>('stop');
    }
  }

  @override
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _activeGenerationController?.close();
    _activeGenerationController = null;
    if (Platform.isIOS) {
      await _flutterGemmaChat?.session.close();
      _flutterGemmaChat = null;
      await _flutterGemmaModel?.close();
      _flutterGemmaModel = null;
    } else if (Platform.isAndroid) {
      await _methodChannel.invokeMethod<void>('dispose');
    }
    _initialized = false;
  }

  Future<String> _resolveModelPath(GemmaModelConfig config) async {
    final appFilesDir = (await getApplicationSupportDirectory()).path;
    final supportPath = config.localModelPath(appFilesDir);
    if (await File(supportPath).exists()) return supportPath;

    if (Platform.isAndroid) {
      final externalFilesDir = await _methodChannel.invokeMethod<String>(
        'getExternalFilesDir',
      );
      if (externalFilesDir != null && externalFilesDir.isNotEmpty) {
        final flatPath = config.androidFlatModelPath(externalFilesDir);
        if (await File(flatPath).exists()) return flatPath;
        final legacyPath = config.localModelPath(externalFilesDir);
        if (await File(legacyPath).exists()) return legacyPath;
        return flatPath;
      }
    }

    return supportPath;
  }

  void _handleRuntimeEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type']?.toString();
    switch (type) {
      case 'token':
        _activeGenerationController?.add(event['text']?.toString() ?? '');
      case 'done':
        _activeGenerationController?.close();
      case 'error':
        _activeGenerationController?.addError(
          RuntimeUnavailableException(
            event['message']?.toString() ?? 'Unknown runtime error',
          ),
        );
    }
  }
}

class PlaceholderGemmaRuntime implements LocalGemmaRuntime {
  PlaceholderGemmaRuntime({GemmaModelConfig? config});

  @override
  Future<void> initialize(GemmaModelConfig config) async {}

  @override
  Stream<String> generate(GemmaRequest request) async* {
    throw RuntimeUnavailableException(
      '${Platform.operatingSystem} 本地推理引擎尚未接通。Android 与 iOS 应走原生 MethodChannel runtime；如果在移动端看到这条消息，说明当前安装包不是最新构建或原生 channel 注册失败。',
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
