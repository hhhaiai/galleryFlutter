import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/services.dart';
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

  final _tokenController = StreamController<String>.broadcast();
  StreamSubscription<dynamic>? _eventSubscription;
  GemmaModelConfig? _config;
  bool _initialized = false;

  @override
  Future<void> initialize(GemmaModelConfig config) async {
    _config = config;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    _eventSubscription ??= _eventChannel.receiveBroadcastStream().listen(
      _handleRuntimeEvent,
      onError: (Object error) {
        _tokenController.addError(error);
      },
    );

    final modelPath = await _resolveModelPath(config);
    await _methodChannel.invokeMethod<void>('initialize', {
      'modelPath': modelPath,
      'topK': config.topK,
      'topP': config.topP,
      'temperature': config.temperature,
      'maxTokens': 1024,
      'supportImage': false,
      'supportAudio': false,
      'accelerator': 'cpu',
    });
    _initialized = true;
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

    await _methodChannel.invokeMethod<void>('generate', {
      'prompt': request.prompt,
      'systemPrompt': request.systemPrompt,
      'imagePaths': request.imagePaths,
      'audioPaths': request.audioPaths,
      'enabledSkillNames': request.enabledSkillNames,
    });

    await for (final token in _tokenController.stream) {
      if (token == _doneToken) break;
      yield token;
    }
  }

  @override
  Future<void> stop() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await _methodChannel.invokeMethod<void>('stop');
    }
  }

  @override
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (Platform.isAndroid || Platform.isIOS) {
      await _methodChannel.invokeMethod<void>('dispose');
    }
    await _tokenController.close();
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
        _tokenController.add(event['text']?.toString() ?? '');
      case 'done':
        _tokenController.add(_doneToken);
      case 'error':
        _tokenController.addError(
          RuntimeUnavailableException(
            event['message']?.toString() ?? 'Unknown runtime error',
          ),
        );
    }
  }

  static const _doneToken = '__GEMMA_DONE__';
}

class PlaceholderGemmaRuntime implements LocalGemmaRuntime {
  PlaceholderGemmaRuntime({GemmaModelConfig? config});

  @override
  Future<void> initialize(GemmaModelConfig config) async {}

  @override
  Stream<String> generate(GemmaRequest request) async* {
    if (Platform.isIOS) {
      throw const RuntimeUnavailableException(
        'iOS 模型已下载，但当前安装版本还没有接通 LiteRT-LM iOS 推理引擎。'
        '这不是模型下载失败，也不是 iOS 不支持；下一步需要接入 google-ai-edge/LiteRT-LM 的 iOS runtime 后才能开始本地对话。',
      );
    }
    throw RuntimeUnavailableException(
      '${Platform.operatingSystem} 本地推理引擎尚未接通。请先在 Android 真机完成当前 LiteRT-LM 验证，随后按平台接入本地 runtime。',
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
