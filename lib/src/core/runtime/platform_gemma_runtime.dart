import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../model/gemma_model_config.dart';
import 'local_gemma_runtime.dart';

LocalGemmaRuntime createLocalGemmaRuntime() {
  if (Platform.isAndroid) {
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
    if (!Platform.isAndroid) return;

    _eventSubscription ??= _eventChannel.receiveBroadcastStream().listen(
      _handleRuntimeEvent,
      onError: (Object error) {
        _tokenController.addError(error);
      },
    );

    final appFilesDir = (await getApplicationSupportDirectory()).path;
    await _methodChannel.invokeMethod<void>('initialize', {
      'modelPath': config.localModelPath(appFilesDir),
      'topK': config.topK,
      'topP': config.topP,
      'temperature': config.temperature,
      'maxTokens': config.maxTokens,
      'supportImage': config.supportImage,
      'supportAudio': config.supportAudio,
      'accelerator': config.accelerators.first.id,
    });
    _initialized = true;
  }

  @override
  Stream<String> generate(GemmaRequest request) async* {
    if (!Platform.isAndroid) {
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
    if (Platform.isAndroid) {
      await _methodChannel.invokeMethod<void>('stop');
    }
  }

  @override
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (Platform.isAndroid) {
      await _methodChannel.invokeMethod<void>('dispose');
    }
    await _tokenController.close();
    _initialized = false;
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
  PlaceholderGemmaRuntime({GemmaModelConfig? config}) : _config = config;

  GemmaModelConfig? _config;

  @override
  Future<void> initialize(GemmaModelConfig config) async {
    _config = config;
  }

  @override
  Stream<String> generate(GemmaRequest request) async* {
    final platform = Platform.operatingSystem;
    final config = _config ?? gemma4E2bIt;
    yield '[本地运行时占位][$platform] 已锁定模型 ${config.name}。';
    yield '\n\n当前只有 Android 正在接入 LiteRT-LM MethodChannel；其它平台后端待实现。';
    yield '\n\n输入: ${request.prompt}';
    if (request.imagePaths.isNotEmpty) {
      yield '\n图片: ${request.imagePaths.length} 个';
    }
    if (request.audioPaths.isNotEmpty) {
      yield '\n音频: ${request.audioPaths.length} 个';
    }
    if (request.enabledSkillNames.isNotEmpty) {
      yield "\nSkills: ${request.enabledSkillNames.join(', ')}";
    }
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
