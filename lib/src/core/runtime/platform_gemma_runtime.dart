import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

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

    // Keep Android initial runtime text-only. Google Gallery enables image/audio
    // per task/session; enabling multimodal backends globally made Android stay
    // in "思考中" even for normal chat.
    await _initializeAndroidRuntime(
      config,
      supportImage: false,
      supportAudio: false,
    );
    _initialized = true;
  }

  Future<void> _initializeAndroidRuntime(
    GemmaModelConfig config, {
    required bool supportImage,
    required bool supportAudio,
  }) async {
    final modelPath = await _resolveModelPath(config);
    await _methodChannel.invokeMethod<void>('initialize', {
      'modelPath': modelPath,
      'topK': config.topK,
      'topP': config.topP,
      'temperature': config.temperature,
      'maxTokens': 1024,
      'supportImage': supportImage,
      'supportAudio': supportAudio,
      'accelerator': supportImage ? 'gpu' : 'cpu',
    });
  }

  Future<void> _initializeFlutterGemma(
    GemmaModelConfig config,
    String modelPath, {
    bool forceReload = false,
    bool supportImage = true,
    bool supportAudio = false,
  }) async {
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
      if (forceReload) {
        await _flutterGemmaChat?.session.close();
        _flutterGemmaChat = null;
        await _flutterGemmaModel?.close();
        _flutterGemmaModel = null;
      }
      await fg.FlutterGemma.installModel(
        modelType: fg.ModelType.gemma4,
        fileType: fg.ModelFileType.litertlm,
      ).fromFile(modelPath).install();

      _flutterGemmaModel ??= await fg.FlutterGemma.getActiveModel(
        maxTokens: 1024,
        preferredBackend: fg.PreferredBackend.gpu,
        supportImage: supportImage && config.supportImage,
        supportAudio: supportAudio && config.supportAudio,
        maxNumImages: supportImage && config.supportImage ? 1 : null,
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

    final config = _config ?? gemma4E2bIt;
    final needsImageRuntime = request.imagePaths.isNotEmpty;
    final needsAudioRuntime = request.audioPaths.isNotEmpty;
    try {
      await _initializeAndroidRuntime(
        config,
        supportImage: needsImageRuntime,
        supportAudio: needsAudioRuntime,
      );
    } on PlatformException catch (error) {
      if (!needsImageRuntime && !needsAudioRuntime) rethrow;
      await _initializeAndroidRuntime(
        config,
        supportImage: false,
        supportAudio: false,
      );
      throw RuntimeUnavailableException(
        needsAudioRuntime
            ? '当前设备 audio backend 初始化失败，已回退到文字模式。音频理解需要 LiteRT-LM CPU audio backend。原始错误：${error.message ?? error.code}'
            : '当前设备 GPU/vision 初始化失败，已回退到文字模式。图片理解需要支持 LiteRT-LM GPU vision 的设备。原始错误：${error.message ?? error.code}',
      );
    }

    final generationController = StreamController<String>();
    await _activeGenerationController?.close();
    _activeGenerationController = generationController;
    try {
      try {
        await _methodChannel.invokeMethod<void>('generate', {
          'prompt': request.prompt,
          'systemPrompt': request.systemPrompt,
          'imagePaths': request.imagePaths,
          'audioPaths': request.audioPaths,
          'enabledSkillNames': request.enabledSkillNames,
        });
      } on PlatformException catch (error) {
        if (!generationController.isClosed) {
          generationController.addError(
            RuntimeUnavailableException(error.message ?? error.code),
          );
          await generationController.close();
        }
      }

      await for (final token in generationController.stream.timeout(
        const Duration(seconds: 90),
        onTimeout: (sink) {
          sink.addError(
            const RuntimeUnavailableException(
              '模型 90 秒内没有返回内容，已自动停止。请重试，或切换为纯文字/较短输入。',
            ),
          );
          sink.close();
        },
      )) {
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
    var prompt = request.prompt;
    if (request.systemPrompt != null &&
        request.systemPrompt!.trim().isNotEmpty) {
      prompt = '[System: ${request.systemPrompt}]\n\n$prompt';
    }
    if (request.enabledSkillNames.isNotEmpty) {
      prompt =
          'Enabled skills: ${request.enabledSkillNames.join(', ')}\n\n$prompt';
    }

    // iOS .litertlm FFI multimodal sessions are not reliably reusable. Rebuild
    // per image/audio request so text/image/audio modalities stay isolated.
    final isAudioRequest = request.audioPaths.isNotEmpty;
    final isImageRequest = request.imagePaths.isNotEmpty;
    if (isImageRequest || isAudioRequest) {
      final config = _config ?? gemma4E2bIt;
      final modelPath = await _resolveModelPath(config);
      await _initializeFlutterGemma(
        config,
        modelPath,
        forceReload: true,
        supportImage: isImageRequest,
        supportAudio: isAudioRequest,
      );
    } else {
      await _flutterGemmaChat?.session.close();
      _flutterGemmaChat = null;
    }
    final currentModel = _flutterGemmaModel;
    if (currentModel == null) {
      throw const RuntimeUnavailableException(
        'iOS flutter_gemma model 重新初始化失败。',
      );
    }
    final chat = await currentModel.createChat(
      temperature: _config?.temperature ?? gemma4E2bIt.temperature,
      topK: _config?.topK ?? gemma4E2bIt.topK,
      topP: _config?.topP ?? gemma4E2bIt.topP,
      supportImage: _config?.supportImage ?? gemma4E2bIt.supportImage,
      supportAudio:
          isAudioRequest && (_config?.supportAudio ?? gemma4E2bIt.supportAudio),
      modelType: fg.ModelType.gemma4,
      isThinking: false,
    );
    _flutterGemmaChat = chat;

    try {
      if (request.audioPaths.isNotEmpty) {
        final firstAudio = File(request.audioPaths.first);
        if (!await firstAudio.exists()) {
          throw RuntimeUnavailableException(
            '音频文件不存在：${request.audioPaths.first}',
          );
        }
        await chat.addQueryChunk(
          fg.Message.withAudio(
            text: _audioPrompt(prompt),
            audioBytes: _extractMono16BitPcm(await firstAudio.readAsBytes()),
            isUser: true,
          ),
        );
      } else if (request.imagePaths.isNotEmpty) {
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
      throw RuntimeUnavailableException('iOS 多模态/文本输入失败，已重置会话，请重试：$error');
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

  String _audioPrompt(String prompt) {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty || trimmed == '请听这段声音并说明内容。') {
      return '请直接听这段音频，说明你听到的主要内容、声音类型、语言或环境线索。不要回答无关内容。';
    }
    return '请根据音频内容回答：$trimmed';
  }

  Uint8List _extractMono16BitPcm(Uint8List wavBytes) {
    if (wavBytes.length < 44 ||
        String.fromCharCodes(wavBytes.sublist(0, 4)) != 'RIFF') {
      throw const RuntimeUnavailableException(
        'Gemma 音频理解需要 16k mono PCM WAV；请使用应用内录音或选择 WAV 文件。',
      );
    }
    final data = ByteData.sublistView(wavBytes);
    if (String.fromCharCodes(wavBytes.sublist(8, 12)) != 'WAVE') {
      throw const RuntimeUnavailableException('无效 WAV 文件。');
    }
    var offset = 12;
    var channels = 1;
    var sampleRate = 16000;
    var bitsPerSample = 16;
    var dataOffset = -1;
    var dataSize = 0;
    while (offset + 8 <= wavBytes.length) {
      final chunkId = String.fromCharCodes(
        wavBytes.sublist(offset, offset + 4),
      );
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final chunkDataOffset = offset + 8;
      if (chunkDataOffset + chunkSize > wavBytes.length) break;
      if (chunkId == 'fmt ') {
        final audioFormat = data.getUint16(chunkDataOffset, Endian.little);
        if (audioFormat != 1) {
          throw const RuntimeUnavailableException('Gemma 音频只支持 PCM WAV。');
        }
        channels = data.getUint16(chunkDataOffset + 2, Endian.little);
        sampleRate = data.getUint32(chunkDataOffset + 4, Endian.little);
        bitsPerSample = data.getUint16(chunkDataOffset + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = chunkDataOffset;
        dataSize = chunkSize;
        break;
      }
      offset = chunkDataOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    if (dataOffset < 0 || dataSize <= 0) {
      throw const RuntimeUnavailableException('WAV data chunk 不存在。');
    }
    final samples = <int>[];
    if (bitsPerSample == 16) {
      for (var i = dataOffset; i + 1 < dataOffset + dataSize; i += 2) {
        samples.add(data.getInt16(i, Endian.little));
      }
    } else if (bitsPerSample == 8) {
      for (var i = dataOffset; i < dataOffset + dataSize; i += 1) {
        samples.add(((wavBytes[i] & 0xFF) - 128) * 256);
      }
    } else {
      throw const RuntimeUnavailableException('Gemma 音频只支持 8/16-bit PCM WAV。');
    }
    final mono = <int>[];
    if (channels <= 1) {
      mono.addAll(samples);
    } else {
      for (var i = 0; i + channels <= samples.length; i += channels) {
        var sum = 0;
        for (var c = 0; c < channels; c += 1) {
          sum += samples[i + c];
        }
        mono.add((sum / channels).round());
      }
    }
    final normalized = sampleRate == 16000
        ? mono
        : _resampleMono(mono, sampleRate, 16000);
    final maxSamples = 16000 * 30;
    final trimmed = normalized.length > maxSamples
        ? normalized.sublist(0, maxSamples)
        : normalized;
    final out = ByteData(trimmed.length * 2);
    for (var i = 0; i < trimmed.length; i += 1) {
      out.setInt16(i * 2, trimmed[i].clamp(-32768, 32767), Endian.little);
    }
    return out.buffer.asUint8List();
  }

  List<int> _resampleMono(List<int> input, int originalRate, int targetRate) {
    if (originalRate <= 0 || originalRate == targetRate || input.isEmpty) {
      return input;
    }
    final ratio = targetRate / originalRate;
    final outputLength = (input.length * ratio).round().clamp(1, 1 << 31);
    return List<int>.generate(outputLength, (index) {
      final pos = index / ratio;
      final left = pos.floor().clamp(0, input.length - 1);
      final right = (left + 1).clamp(0, input.length - 1);
      final fraction = pos - left;
      return (input[left] * (1 - fraction) + input[right] * fraction).round();
    });
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
