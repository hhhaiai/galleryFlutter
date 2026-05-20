import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math' as math;
import 'dart:typed_data' show ByteData, Endian, Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_gemma/core/ffi/litert_lm_client.dart' as fg_ffi;
import 'package:flutter_gemma/flutter_gemma.dart' as fg;
import 'package:path_provider/path_provider.dart';

import '../model/gemma_model_config.dart';
import 'local_gemma_runtime.dart';

const _macosImportedGemma4E2bBytes = 2538766336;
const _gib = 1024 * 1024 * 1024;

@visibleForTesting
class DeviceRuntimeProfile {
  const DeviceRuntimeProfile({
    required this.label,
    required this.textTokenWindow,
    required this.multimodalTokenWindow,
    required this.imageMaxDimension,
    required this.preferCpuForImage,
    this.totalMemoryBytes,
  });

  final String label;
  final int textTokenWindow;
  final int multimodalTokenWindow;
  final int imageMaxDimension;
  final bool preferCpuForImage;
  final int? totalMemoryBytes;

  static DeviceRuntimeProfile forMemoryBytes(
    int? totalMemoryBytes, {
    bool isAppleMobile = false,
  }) {
    final memoryBytes = totalMemoryBytes ?? 0;
    if (isAppleMobile) {
      if (totalMemoryBytes == null) {
        return const DeviceRuntimeProfile(
          label: 'ios-low-fallback',
          textTokenWindow: 8192,
          multimodalTokenWindow: 2048,
          imageMaxDimension: 640,
          preferCpuForImage: true,
        );
      }
      if (memoryBytes <= 5 * _gib) {
        return DeviceRuntimeProfile(
          label: 'ios-low',
          totalMemoryBytes: totalMemoryBytes,
          textTokenWindow: 12288,
          multimodalTokenWindow: 2048,
          imageMaxDimension: 640,
          preferCpuForImage: true,
        );
      }
      if (memoryBytes <= 7 * _gib) {
        return DeviceRuntimeProfile(
          label: 'ios-medium',
          totalMemoryBytes: totalMemoryBytes,
          textTokenWindow: 16384,
          multimodalTokenWindow: 3072,
          imageMaxDimension: 768,
          preferCpuForImage: false,
        );
      }
      return DeviceRuntimeProfile(
        label: 'ios-high',
        totalMemoryBytes: totalMemoryBytes,
        textTokenWindow: 24576,
        multimodalTokenWindow: 4096,
        imageMaxDimension: 896,
        preferCpuForImage: false,
      );
    }

    if (totalMemoryBytes == null) {
      return const DeviceRuntimeProfile(
        label: 'android-medium-fallback',
        textTokenWindow: 16384,
        multimodalTokenWindow: 8192,
        imageMaxDimension: 1024,
        preferCpuForImage: false,
      );
    }
    if (memoryBytes <= 6 * _gib) {
      return DeviceRuntimeProfile(
        label: 'android-low',
        totalMemoryBytes: totalMemoryBytes,
        textTokenWindow: 12288,
        multimodalTokenWindow: 3072,
        imageMaxDimension: 640,
        preferCpuForImage: false,
      );
    }
    if (memoryBytes <= 10 * _gib) {
      return DeviceRuntimeProfile(
        label: 'android-medium',
        totalMemoryBytes: totalMemoryBytes,
        textTokenWindow: 24576,
        multimodalTokenWindow: 8192,
        imageMaxDimension: 1024,
        preferCpuForImage: false,
      );
    }
    return DeviceRuntimeProfile(
      label: 'android-high',
      totalMemoryBytes: totalMemoryBytes,
      textTokenWindow: 32000,
      multimodalTokenWindow: 8192,
      imageMaxDimension: 1024,
      preferCpuForImage: false,
    );
  }
}

LocalGemmaRuntime createLocalGemmaRuntime() {
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
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
  bool _androidSupportImage = false;
  bool _androidSupportAudio = false;
  bool _androidSupportSkills = false;
  String _androidAccelerator = GemmaAccelerator.cpu.id;
  List<String> _androidEnabledSkillNames = const [];
  fg.InferenceModel? _flutterGemmaModel;
  fg.InferenceChat? _flutterGemmaChat;
  fg_ffi.LiteRtLmFfiClient? _iosRawFfiClient;
  DeviceRuntimeProfile? _deviceRuntimeProfile;

  @override
  Future<void> initialize(GemmaModelConfig config) async {
    final previousConfig = _config;
    _config = config;
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) return;

    if (Platform.isAndroid || Platform.isIOS) {
      await _ensureDeviceRuntimeProfile();
      _eventSubscription ??= _eventChannel.receiveBroadcastStream().listen(
        _handleRuntimeEvent,
        onError: (Object error) => _activeGenerationController?.addError(error),
      );
    }

    if (Platform.isIOS) {
      if (previousConfig != null &&
          (previousConfig.modelId != config.modelId ||
              previousConfig.commitHash != config.commitHash)) {
        await _flutterGemmaChat?.session.close();
        _flutterGemmaChat = null;
        await _flutterGemmaModel?.close();
        _flutterGemmaModel = null;
      }
      final modelPath = await _resolveModelPath(config);
      await _validateModelFile(config, modelPath);
      await _methodChannel.invokeMethod<void>('initialize', {
        'modelPath': modelPath,
        'topK': config.topK,
        'topP': config.topP,
        'temperature': config.temperature,
        'maxTokens': _runtimeSessionTokenLimit(config),
      });
      _initialized = true;
      return;
    }

    if (Platform.isMacOS) {
      _initialized = true;
      return;
    }

    if (_initialized &&
        previousConfig?.modelId == config.modelId &&
        previousConfig?.commitHash == config.commitHash) {
      return;
    }

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
    bool supportSkills = false,
    String? systemPrompt,
    List<String> enabledSkillNames = const [],
    List<Map<String, String>> enabledSkillDetails = const [],
    String? acceleratorOverride,
  }) async {
    await _ensureDeviceRuntimeProfile();
    final modelPath = await _resolveModelPath(config);
    await _methodChannel.invokeMethod<void>('initialize', {
      'modelPath': modelPath,
      'topK': config.topK,
      'topP': config.topP,
      'temperature': config.temperature,
      'maxTokens': _runtimeSessionTokenLimit(
        config,
        supportImage: supportImage,
        supportAudio: supportAudio,
      ),
      'supportImage': supportImage,
      'supportAudio': supportAudio,
      'supportSkills': supportSkills,
      'systemPrompt': systemPrompt,
      'enabledSkillNames': enabledSkillNames,
      'enabledSkills': enabledSkillDetails,
      'accelerator':
          acceleratorOverride ??
          _selectAndroidAccelerator(
            config,
            supportImage: supportImage,
            supportAudio: supportAudio,
          ),
    });
    _androidSupportImage = supportImage;
    _androidSupportAudio = supportAudio;
    _androidSupportSkills = supportSkills;
    _androidEnabledSkillNames = List<String>.of(enabledSkillNames);
    _androidAccelerator =
        acceleratorOverride ??
        _selectAndroidAccelerator(
          config,
          supportImage: supportImage,
          supportAudio: supportAudio,
        );
  }

  Future<void> _initializeFlutterGemma(
    GemmaModelConfig config,
    String modelPath, {
    bool forceReload = false,
    bool supportImage = false,
    bool supportAudio = false,
  }) async {
    await _ensureDeviceRuntimeProfile();
    await _validateModelFile(config, modelPath);

    try {
      if (forceReload) {
        await _flutterGemmaChat?.session.close();
        _flutterGemmaChat = null;
        await _flutterGemmaModel?.close();
        _flutterGemmaModel = null;
      }

      _flutterGemmaModel ??= await fg.FlutterGemma.getActiveModel(
        maxTokens: _runtimeSessionTokenLimit(
          config,
          supportImage: supportImage,
          supportAudio: supportAudio,
        ),
        preferredBackend: supportAudio && !supportImage
            ? fg.PreferredBackend.cpu
            : fg.PreferredBackend.gpu,
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
        '$_appleRuntimeLabel LiteRT-LM/flutter_gemma 初始化失败：$error',
      );
    }
  }

  fg.ModelType _flutterGemmaModelType(GemmaModelConfig config) {
    switch (config.modelTypeName) {
      case 'gemmaIt':
        return fg.ModelType.gemmaIt;
      case 'gemma4':
      default:
        return fg.ModelType.gemma4;
    }
  }

  String get _appleRuntimeLabel => Platform.isMacOS ? 'macOS' : 'iOS';

  DeviceRuntimeProfile get _currentDeviceRuntimeProfile {
    return _deviceRuntimeProfile ??
        DeviceRuntimeProfile.forMemoryBytes(
          null,
          isAppleMobile: Platform.isIOS,
        );
  }

  Future<DeviceRuntimeProfile> _ensureDeviceRuntimeProfile() async {
    final existing = _deviceRuntimeProfile;
    if (existing != null) return existing;
    if (!Platform.isAndroid && !Platform.isIOS) {
      final profile = DeviceRuntimeProfile.forMemoryBytes(null);
      _deviceRuntimeProfile = profile;
      return profile;
    }
    try {
      final info = await _methodChannel.invokeMapMethod<String, Object?>(
        'getDeviceMemoryInfo',
      );
      final totalMemoryBytes = _intFromPlatform(info?['totalMemoryBytes']);
      final profile = DeviceRuntimeProfile.forMemoryBytes(
        totalMemoryBytes,
        isAppleMobile: Platform.isIOS,
      );
      _deviceRuntimeProfile = profile;
      debugPrint(
        '[GemmaRuntime] device memory profile=${profile.label} '
        'totalMemoryBytes=${totalMemoryBytes ?? 'unknown'} '
        'textTokens=${profile.textTokenWindow} '
        'multimodalTokens=${profile.multimodalTokenWindow} '
        'imageMaxDimension=${profile.imageMaxDimension} '
        'preferCpuForImage=${profile.preferCpuForImage}',
      );
      return profile;
    } catch (error) {
      final profile = DeviceRuntimeProfile.forMemoryBytes(
        null,
        isAppleMobile: Platform.isIOS,
      );
      _deviceRuntimeProfile = profile;
      debugPrint(
        '[GemmaRuntime] device memory profile fallback=${profile.label}: $error',
      );
      return profile;
    }
  }

  static int? _intFromPlatform(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  int _runtimeSessionTokenLimit(
    GemmaModelConfig config, {
    bool supportImage = false,
    bool supportAudio = false,
  }) {
    return runtimeSessionTokenLimitForTesting(
      config,
      supportImage: supportImage,
      supportAudio: supportAudio,
      profile: _currentDeviceRuntimeProfile,
    );
  }

  @visibleForTesting
  static int runtimeSessionTokenLimitForTesting(
    GemmaModelConfig config, {
    bool supportImage = false,
    bool supportAudio = false,
    int? totalMemoryBytes,
    bool isAppleMobile = false,
    DeviceRuntimeProfile? profile,
  }) {
    profile ??= DeviceRuntimeProfile.forMemoryBytes(
      totalMemoryBytes,
      isAppleMobile: isAppleMobile,
    );
    // Keep the stable lane split:
    // - Text-only sessions scale up on higher-memory devices.
    // - Image/audio sessions carry extra encoder memory, so low-memory phones
    //   use smaller KV + image windows to avoid iOS jetsam/native termination.
    final isMultimodal = supportImage || supportAudio;
    final requested = isMultimodal
        ? profile.multimodalTokenWindow
        : profile.textTokenWindow;
    return math.min(config.maxContextLength, requested);
  }

  Future<void> _validateModelFile(
    GemmaModelConfig config,
    String modelPath,
  ) async {
    final file = File(modelPath);
    if (!await file.exists()) {
      throw RuntimeUnavailableException(
        '${Platform.operatingSystem} 模型文件不存在：$modelPath。请先准备模型文件。',
      );
    }
    final bytes = await file.length();
    if (bytes < config.sizeInBytes) {
      if (Platform.isMacOS &&
          config.normalizedName == gemma4E2bIt.normalizedName &&
          bytes == _macosImportedGemma4E2bBytes) {
        return;
      }
      throw RuntimeUnavailableException(
        '${Platform.operatingSystem} 模型文件不完整：$bytes / ${config.sizeInBytes} bytes。请重新准备完整模型文件。',
      );
    }
  }

  Future<void> _prepareFlutterGemmaModel(
    GemmaModelConfig config,
    String modelPath,
  ) async {
    await _validateModelFile(config, modelPath);

    try {
      await fg.FlutterGemma.initialize(maxDownloadRetries: 8);
      await fg.FlutterGemma.installModel(
        modelType: _flutterGemmaModelType(config),
        fileType: fg.ModelFileType.litertlm,
      ).fromFile(modelPath).install();
    } catch (error) {
      throw RuntimeUnavailableException(
        '$_appleRuntimeLabel Gemma 模型准备失败：$error',
      );
    }
  }

  @override
  Stream<String> generate(GemmaRequest request) async* {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      yield* PlaceholderGemmaRuntime(config: _config).generate(request);
      return;
    }
    if (!_initialized) {
      final config = _config ?? gemma4E2bIt;
      await initialize(config);
    }
    if (Platform.isIOS || Platform.isMacOS) {
      yield* _generateWithFlutterGemma(request);
      return;
    }

    yield* _generateWithAndroidRuntime(request);
  }

  Stream<String> _generateWithAndroidRuntime(GemmaRequest request) async* {
    final config = _config ?? gemma4E2bIt;
    final needsImageRuntime = request.imagePaths.isNotEmpty;
    final needsAudioRuntime = request.audioPaths.isNotEmpty;
    final needsSkillsRuntime =
        request.systemPrompt?.trim().isNotEmpty == true ||
        request.enabledSkillNames.isNotEmpty;
    final accelerators = _candidateAndroidAccelerators(
      config,
      supportImage: needsImageRuntime,
      supportAudio: needsAudioRuntime,
    );
    RuntimeUnavailableException? lastRuntimeError;

    for (var index = 0; index < accelerators.length; index += 1) {
      final accelerator = accelerators[index];
      final isLastAttempt = index == accelerators.length - 1;
      try {
        final shouldReuseExistingRuntime =
            !needsImageRuntime &&
            !needsAudioRuntime &&
            !needsSkillsRuntime &&
            _androidRuntimeMatches(
              supportImage: false,
              supportAudio: false,
              supportSkills: false,
              enabledSkillNames: const [],
              accelerator: accelerator,
            );
        if (!shouldReuseExistingRuntime) {
          await _initializeAndroidRuntime(
            config,
            supportImage: needsImageRuntime,
            supportAudio: needsAudioRuntime,
            supportSkills: needsSkillsRuntime,
            systemPrompt: needsSkillsRuntime ? request.systemPrompt : null,
            enabledSkillNames: needsSkillsRuntime
                ? request.enabledSkillNames
                : const [],
            enabledSkillDetails: needsSkillsRuntime
                ? request.enabledSkillDetails
                : const [],
            acceleratorOverride: accelerator,
          );
        }
      } on PlatformException catch (error) {
        if (!needsImageRuntime && !needsAudioRuntime) rethrow;
        if (!isLastAttempt) continue;
        await _restoreAndroidTextRuntime(config);
        throw RuntimeUnavailableException(
          needsAudioRuntime
              ? '当前设备 audio runtime 初始化失败。已尝试 ${accelerators.join(' / ')} backend，仍无法启用音频理解；已回退到文字模式。原始错误：${error.message ?? error.code}'
              : '当前设备 GPU/vision 初始化失败，已回退到文字模式。图片理解需要支持 LiteRT-LM GPU vision 的设备。原始错误：${error.message ?? error.code}',
        );
      }

      try {
        yield* _invokeAndroidGenerate(
          request,
          includeSystemContext: !needsSkillsRuntime,
        );
        return;
      } on RuntimeUnavailableException catch (error) {
        lastRuntimeError = error;
        final shouldRetryAudio =
            needsAudioRuntime &&
            !needsImageRuntime &&
            !isLastAttempt &&
            _isCompiledModelInvocationError(error.message);
        if (!shouldRetryAudio) {
          await _restoreAndroidTextRuntime(config);
          rethrow;
        }
        continue;
      }
    }

    await _restoreAndroidTextRuntime(config);
    throw lastRuntimeError ??
        const RuntimeUnavailableException('Android 音频/多模态推理失败。');
  }

  Stream<String> _invokeAndroidGenerate(
    GemmaRequest request, {
    required bool includeSystemContext,
  }) async* {
    final generationController = StreamController<String>();
    final prompt = _androidPromptForRequest(
      request,
      includeSystemContext: includeSystemContext,
    );
    await _activeGenerationController?.close();
    _activeGenerationController = generationController;
    try {
      try {
        await _methodChannel.invokeMethod<void>('generate', {
          'prompt': prompt,
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

  Stream<String> _invokeIosNativeGenerate(
    GemmaRequest request, {
    required String prompt,
  }) async* {
    final generationController = StreamController<String>();
    await _activeGenerationController?.close();
    _activeGenerationController = generationController;
    try {
      try {
        await _methodChannel.invokeMethod<void>('generate', {
          'prompt': prompt,
          'imagePaths': request.imagePaths,
          'audioPaths': request.audioPaths,
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
        const Duration(seconds: 180),
        onTimeout: (sink) {
          sink.addError(
            const RuntimeUnavailableException(
              'iOS native LiteRT-LM 180 秒内没有返回内容，已自动停止。',
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
    final prompt = _contextualPrompt(request);

    // iOS .litertlm FFI multimodal sessions are not reliably reusable. Rebuild
    // per media request so text/image/audio modalities stay isolated.
    final isImageRequest = request.imagePaths.isNotEmpty;
    final isAudioRequest = request.audioPaths.isNotEmpty;
    final config = _config ?? gemma4E2bIt;
    var modelPath = await _resolveModelPath(config);

    final tools = _iosSkillToolsFor(request);
    const useDartFfiDefine = String.fromEnvironment('GEMMA_IOS_USE_DART_FFI');
    const allowPluginPathDefine = String.fromEnvironment(
      'GEMMA_IOS_ALLOW_PLUGIN_PATH',
    );
    final useDartFfi =
        useDartFfiDefine == '1' ||
        useDartFfiDefine.toLowerCase() == 'true' ||
        Platform.environment['GEMMA_IOS_USE_DART_FFI'] == '1';
    final allowPluginPath =
        allowPluginPathDefine == '1' ||
        allowPluginPathDefine.toLowerCase() == 'true' ||
        Platform.environment['GEMMA_IOS_ALLOW_PLUGIN_PATH'] == '1';
    const useNativeDirectDefine = String.fromEnvironment(
      'GEMMA_IOS_USE_NATIVE_DIRECT',
    );
    final useNativeDirect =
        useNativeDirectDefine == '1' ||
        useNativeDirectDefine.toLowerCase() == 'true' ||
        Platform.environment['GEMMA_IOS_USE_NATIVE_DIRECT'] == '1';
    if (tools.isEmpty && isAudioRequest && useNativeDirect && !useDartFfi) {
      yield* _invokeIosNativeGenerate(
        request,
        prompt: isImageRequest
            ? _imageAndAudioPrompt(prompt)
            : _audioPrompt(prompt),
      );
      return;
    }
    if (tools.isEmpty) {
      yield* _generateIosMediaWithRawLiteRtLm(
        request: request,
        prompt: prompt,
        config: config,
        modelPath: modelPath,
      );
      return;
    }
    if (!allowPluginPath) {
      throw const RuntimeUnavailableException(
        'iOS Skills/function calling 当前已暂时关闭：为避开 flutter_gemma iOS 插件注册崩溃，iOS 现在统一使用 LiteRT-LM raw FFI 路径。请先用文字/图片/语音验证本地模型。',
      );
    }
    // 这里处理的是：纯文字、图片、或图片+Skills 的 flutter_gemma 高级 API 路径。
    final effectiveConfig = config;
    if (isImageRequest || isAudioRequest) {
      await _initializeFlutterGemma(
        effectiveConfig,
        modelPath,
        forceReload: true,
        supportImage: isImageRequest,
        supportAudio: isAudioRequest,
      );
    } else if (_flutterGemmaModel == null) {
      await _initializeFlutterGemma(
        effectiveConfig,
        modelPath,
        supportImage: false,
        supportAudio: false,
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
      // Vision answers should be factual and stable. Keep text/skills creative
      // defaults, but reduce sampling for image grounding so counts and visible
      // entities are less likely to drift.
      temperature: isImageRequest
          ? 0.2
          : (_config?.temperature ?? gemma4E2bIt.temperature),
      topK: isImageRequest ? 1 : (_config?.topK ?? gemma4E2bIt.topK),
      topP: _config?.topP ?? gemma4E2bIt.topP,
      supportImage: isImageRequest,
      supportAudio: isAudioRequest,
      modelType: _flutterGemmaModelType(effectiveConfig),
      isThinking: false,
      tools: tools,
      supportsFunctionCalls: tools.isNotEmpty,
      toolChoice: tools.isEmpty ? fg.ToolChoice.none : fg.ToolChoice.auto,
    );
    _flutterGemmaChat = chat;

    try {
      if (isImageRequest || isAudioRequest) {
        Uint8List? imageBytes;
        Uint8List? audioBytes;
        if (isImageRequest) {
          final firstImage = File(request.imagePaths.first);
          if (!await firstImage.exists()) {
            throw RuntimeUnavailableException(
              '图片文件不存在：${request.imagePaths.first}',
            );
          }
          imageBytes = await _readGalleryStyleVisionImageBytes(firstImage);
        }
        if (isAudioRequest) {
          audioBytes = await _readGemmaWavBytes(request.audioPaths.first);
        }
        final mediaPrompt = isImageRequest && isAudioRequest
            ? _imageAndAudioPrompt(prompt)
            : isImageRequest
            ? _visionPrompt(prompt)
            : _audioPrompt(prompt);
        await chat.addQueryChunk(
          fg.Message(
            text: mediaPrompt,
            imageBytes: imageBytes,
            audioBytes: audioBytes,
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

    var toolRounds = 0;
    var shouldContinueAfterTool = false;
    do {
      shouldContinueAfterTool = false;
      await for (final response in chat.generateChatResponseAsync()) {
        if (response is fg.TextResponse) {
          yield response.token;
        } else if (response is fg.ThinkingResponse) {
          yield response.content;
        } else if (response is fg.FunctionCallResponse) {
          final toolResult = _executeDartSkillTool(response, request);
          yield '\n[tool:${response.name}] ${toolResult['status'] ?? 'done'}\n';
          await chat.addQueryChunk(
            fg.Message.toolResponse(
              toolName: response.name,
              response: toolResult,
            ),
          );
          shouldContinueAfterTool = true;
        } else if (response is fg.ParallelFunctionCallResponse) {
          for (final call in response.calls) {
            final toolResult = _executeDartSkillTool(call, request);
            yield '\n[tool:${call.name}] ${toolResult['status'] ?? 'done'}\n';
            await chat.addQueryChunk(
              fg.Message.toolResponse(
                toolName: call.name,
                response: toolResult,
              ),
            );
          }
          shouldContinueAfterTool = response.calls.isNotEmpty;
        }
      }
      toolRounds += 1;
    } while (shouldContinueAfterTool && toolRounds < 3);
  }

  Stream<String> _generateIosMediaWithRawLiteRtLm({
    required GemmaRequest request,
    required String prompt,
    required GemmaModelConfig config,
    required String modelPath,
  }) async* {
    // flutter_gemma 0.14.1 manually wraps .litertlm messages with Gemma turn
    // markers on iOS before sending them into the LiteRT-LM JSON conversation
    // API. Android and non-iOS .litertlm paths send raw text and let LiteRT-LM
    // own the chat template. For iOS vision and audio this nested-template
    // difference causes quality issues (vision) and code 13 errors (audio).
    // All media requests use the raw JSON path with an unwrapped prompt.
    // Keep the textual instruction before media items. LiteRT-LM's Gemma3n
    // data-processor tests cover text->audio order, and real-device iOS
    // testing showed audio->text can make the model answer as if no audio was
    // provided even though the audio file was decoded and prefilled.
    await _prepareFlutterGemmaModel(config, modelPath);
    await _flutterGemmaChat?.session.close();
    _flutterGemmaChat = null;
    await _flutterGemmaModel?.close();
    _flutterGemmaModel = null;

    final isImageRequest = request.imagePaths.isNotEmpty;
    final isAudioRequest = request.audioPaths.isNotEmpty;

    Uint8List? imageBytes;
    if (isImageRequest) {
      final firstImage = File(request.imagePaths.first);
      if (!await firstImage.exists()) {
        throw RuntimeUnavailableException(
          '图片文件不存在：${request.imagePaths.first}',
        );
      }
      imageBytes = await _readGalleryStyleVisionImageBytes(firstImage);
    }

    Uint8List? audioBytes;
    if (isAudioRequest) {
      audioBytes = await _readGemmaWavBytes(request.audioPaths.first);
    }

    final mediaPrompt = isImageRequest && isAudioRequest
        ? _imageAndAudioPrompt(prompt)
        : isImageRequest
        ? _visionPrompt(prompt)
        : isAudioRequest
        ? _audioPrompt(prompt)
        : prompt;

    final tempMediaPaths = <String>[];
    try {
      String? audioPathForJson;
      String? imagePathForJson;
      if (isAudioRequest && audioBytes != null) {
        audioPathForJson = await _writeIosTempMediaFile(
          prefix: 'gemma_audio',
          extension: 'wav',
          bytes: audioBytes,
        );
        tempMediaPaths.add(audioPathForJson);
      }
      if (isAudioRequest && isImageRequest && imageBytes != null) {
        imagePathForJson = await _writeIosTempMediaFile(
          prefix: 'gemma_image',
          extension: 'png',
          bytes: imageBytes,
        );
        tempMediaPaths.add(imagePathForJson);
      }

      final cacheDir = (await getApplicationSupportDirectory()).path;
      final backends = _iosRawMediaBackends(
        isImageRequest: isImageRequest,
        isAudioRequest: isAudioRequest,
      );
      Object? lastError;
      for (final backend in backends) {
        final client = fg_ffi.LiteRtLmFfiClient();
        _iosRawFfiClient = client;
        try {
          debugPrint(
            '[GemmaIOS] raw media inference backend=$backend '
            'imageBytes=${imageBytes?.length ?? 0} '
            'audioBytes=${audioBytes?.length ?? 0} '
            'audioPath=${audioPathForJson != null} '
            'imagePath=${imagePathForJson != null}',
          );
          await client.initialize(
            modelPath: modelPath,
            backend: backend,
            maxTokens: _runtimeSessionTokenLimit(
              config,
              supportImage: isImageRequest,
              supportAudio: isAudioRequest,
            ),
            cacheDir: cacheDir,
            enableVision: isImageRequest && config.supportImage,
            maxNumImages: isImageRequest && config.supportImage ? 1 : 0,
            enableAudio: isAudioRequest && config.supportAudio,
          );
          client.createConversation(
            temperature: 0.1,
            topK: 1,
            topP: 0.95,
            seed: 1,
          );

          if (isAudioRequest) {
            final messageJson = buildIosPathMessageJsonForTesting(
              text: mediaPrompt,
              audioPath: audioPathForJson,
              imagePath: imagePathForJson,
            );
            if (!isImageRequest) {
              // PhoneClaw's working iOS Gemma 4 route uses file-path JSON and
              // non-streaming Conversation API for audio-only. This avoids the
              // iOS streaming startup path that repeatedly returned code 13.
              final rawResponse = await client.sendMessage(messageJson);
              yield _extractIosRawResponseText(rawResponse);
              return;
            }
            try {
              await for (final rawChunk in client.sendMessageStreamRaw(
                messageJson,
              )) {
                yield fg_ffi.LiteRtLmFfiClient.extractTextFromResponse(
                  rawChunk,
                );
              }
              return;
            } catch (streamError) {
              if (!_isIosStreamingStartFailure(streamError)) rethrow;
              debugPrint(
                '[GemmaIOS] path-json streaming failed on $backend; '
                'trying sync sendMessage: $streamError',
              );
              final rawResponse = await client.sendMessage(messageJson);
              yield _extractIosRawResponseText(rawResponse);
              return;
            }
          }

          try {
            await for (final rawChunk in client.chatRaw(
              mediaPrompt,
              imageBytes: imageBytes,
              enableThinking: false,
            )) {
              yield fg_ffi.LiteRtLmFfiClient.extractTextFromResponse(rawChunk);
            }
            return;
          } catch (streamError) {
            if (!_isIosStreamingStartFailure(streamError)) rethrow;
            debugPrint(
              '[GemmaIOS] streaming failed on $backend; trying sync sendMessage: '
              '$streamError',
            );
            final messageJson = fg_ffi.LiteRtLmFfiClient.buildMessageJson(
              mediaPrompt,
              imageBytes: imageBytes,
            );
            final rawResponse = await client.sendMessage(messageJson);
            yield _extractIosRawResponseText(rawResponse);
            return;
          }
        } catch (error) {
          lastError = error;
          debugPrint(
            '[GemmaIOS] raw media inference failed on $backend: $error',
          );
        } finally {
          if (identical(_iosRawFfiClient, client)) {
            _iosRawFfiClient = null;
          }
          client.shutdown();
        }
      }
      throw RuntimeUnavailableException(
        '$_appleRuntimeLabel 多模态推理失败，已重置会话，请重试：$lastError。'
        '已尝试 backend=${backends.join(' / ')}。',
      );
    } finally {
      for (final path in tempMediaPaths) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Best-effort temp cleanup only.
        }
      }
    }
  }

  List<String> _iosRawMediaBackends({
    required bool isImageRequest,
    required bool isAudioRequest,
  }) {
    final profile = _currentDeviceRuntimeProfile;
    if (isAudioRequest && !isImageRequest) {
      // Audio encoder is CPU-only in LiteRT-LM. Using CPU as the primary
      // backend avoids iOS code 13 failures seen when the main decoder starts
      // on GPU and the audio executor is CPU.
      return const ['cpu', 'gpu'];
    }
    if (isImageRequest && profile.preferCpuForImage) {
      return const ['cpu', 'gpu'];
    }
    if (!isImageRequest && !isAudioRequest) {
      return const ['gpu', 'cpu'];
    }
    return const ['gpu'];
  }

  bool _isIosStreamingStartFailure(Object error) {
    return error.toString().contains('Failed to start streaming (code: 13)');
  }

  Future<String> _writeIosTempMediaFile({
    required String prefix,
    required String extension,
    required Uint8List bytes,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final safeExt = extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final path =
        '${tempDir.path}/'
        '${prefix}_${DateTime.now().microsecondsSinceEpoch}.$safeExt';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @visibleForTesting
  static String buildIosPathMessageJsonForTesting({
    required String text,
    String? audioPath,
    String? imagePath,
  }) {
    final content = <Map<String, dynamic>>[];
    content.add({'type': 'text', 'text': text});
    if (imagePath != null) {
      content.add({'type': 'image', 'path': imagePath});
    }
    if (audioPath != null) {
      content.add({'type': 'audio', 'path': audioPath});
    }
    return jsonEncode({'role': 'user', 'content': content});
  }

  String _extractIosRawResponseText(String rawResponse) {
    final text = fg_ffi.LiteRtLmFfiClient.extractTextFromResponse(rawResponse);
    if (text.trim().isEmpty && rawResponse.trim().isNotEmpty) {
      return _extractTextFallbackFromSdkJson(rawResponse);
    }
    return text;
  }

  String _extractTextFallbackFromSdkJson(String rawResponse) {
    try {
      final decoded = jsonDecode(rawResponse);
      if (decoded is Map<String, dynamic>) {
        final content = decoded['content'];
        if (content is List) {
          return content
              .whereType<Map<String, dynamic>>()
              .where((item) => item['type'] == 'text')
              .map((item) => item['text']?.toString() ?? '')
              .join();
        }
      }
    } catch (_) {
      // Keep the raw response below; this is only a last-resort display path.
    }
    return rawResponse;
  }

  Future<Uint8List> _readGemmaWavBytes(String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      throw RuntimeUnavailableException('音频文件不存在：$audioPath');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length < 44 ||
        _ascii(bytes, 0, 4) != 'RIFF' ||
        _ascii(bytes, 8, 4) != 'WAVE') {
      throw RuntimeUnavailableException(
        'iOS audio probe 需要 16k mono PCM WAV：$audioPath',
      );
    }
    return normalizeGemmaWavBytesForLiteRt(bytes, audioPath: audioPath);
  }

  @visibleForTesting
  static Uint8List normalizeGemmaWavBytesForLiteRt(
    Uint8List bytes, {
    String audioPath = 'audio.wav',
  }) {
    if (bytes.length < 44 ||
        _asciiBytes(bytes, 0, 4) != 'RIFF' ||
        _asciiBytes(bytes, 8, 4) != 'WAVE') {
      throw RuntimeUnavailableException(
        'iOS audio probe 需要 16k mono PCM WAV：$audioPath',
      );
    }
    final view = ByteData.sublistView(bytes);
    var offset = 12;
    var channels = 0;
    var sampleRate = 0;
    var bitsPerSample = 0;
    var audioFormat = 0;
    var dataOffset = -1;
    var dataSize = 0;
    while (offset + 8 <= bytes.length) {
      final chunkId = _asciiBytes(bytes, offset, 4);
      final chunkSize = view.getUint32(offset + 4, Endian.little);
      final chunkDataOffset = offset + 8;
      if (chunkDataOffset + chunkSize > bytes.length) break;
      if (chunkId == 'fmt ') {
        if (chunkSize < 16) {
          throw RuntimeUnavailableException(
            'iOS audio probe WAV fmt chunk 无效：$audioPath',
          );
        }
        audioFormat = view.getUint16(chunkDataOffset, Endian.little);
        channels = view.getUint16(chunkDataOffset + 2, Endian.little);
        sampleRate = view.getUint32(chunkDataOffset + 4, Endian.little);
        bitsPerSample = view.getUint16(chunkDataOffset + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = chunkDataOffset;
        dataSize = chunkSize;
        break;
      }
      offset = chunkDataOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    final maxBytes = 16000 * 30 * 2;
    final isPcm = audioFormat == 1 || audioFormat == 0xFFFE;
    if (!isPcm ||
        channels != 1 ||
        sampleRate != 16000 ||
        bitsPerSample != 16 ||
        dataOffset < 0 ||
        dataSize <= 0 ||
        dataSize > maxBytes) {
      throw RuntimeUnavailableException(
        'iOS audio probe 只接受 30 秒内 16kHz / mono / 16-bit PCM WAV。'
        ' 当前 format=$audioFormat channels=$channels sampleRate=$sampleRate bits=$bitsPerSample dataSize=$dataSize。',
      );
    }
    // Keep a full WAV container, but rebuild it into the minimal 44-byte
    // RIFF/fmt/data shape before passing it to LiteRT-LM. iOS/macOS encoders
    // often add padding chunks such as FLLR; those are legal WAV, but the
    // LiteRT-LM iOS audio JSON path has been observed to fail streaming with
    // code 13 on such containers. Android already sends this same clean shape.
    return _buildPcm16MonoWav(bytes.sublist(dataOffset, dataOffset + dataSize));
  }

  static Uint8List _buildPcm16MonoWav(Uint8List pcmData) {
    final output = Uint8List(44 + pcmData.length);
    final header = ByteData.sublistView(output);
    output.setRange(0, 4, 'RIFF'.codeUnits);
    header.setUint32(4, 36 + pcmData.length, Endian.little);
    output.setRange(8, 12, 'WAVE'.codeUnits);
    output.setRange(12, 16, 'fmt '.codeUnits);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 16000, Endian.little);
    header.setUint32(28, 16000 * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    output.setRange(36, 40, 'data'.codeUnits);
    header.setUint32(40, pcmData.length, Endian.little);
    output.setRange(44, output.length, pcmData);
    return output;
  }

  Future<Uint8List> _readGalleryStyleVisionImageBytes(File imageFile) async {
    // Android already normalizes in MainActivity before sending
    // Content.ImageBytes. The iOS flutter_gemma FFI path receives raw bytes
    // directly, so normalize here to match Gallery's vision input shape:
    // orientation-applied, bounded dimensions, and PNG bytes. This prevents the
    // vision encoder from seeing an oversized / orientation-tagged camera asset
    // that differs from the preview shown to the user.
    if (Platform.isIOS) {
      final profile = await _ensureDeviceRuntimeProfile();
      try {
        final bytes = await _methodChannel.invokeMethod<Uint8List>(
          'prepareVisionImage',
          {
            'imagePath': imageFile.path,
            'maxDimension': profile.imageMaxDimension,
          },
        );
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } on MissingPluginException {
        // Unit-test / non-Runner harnesses may not have the iOS channel.
      } on PlatformException catch (error) {
        throw RuntimeUnavailableException(
          'iOS 图片预处理失败：${error.message ?? error.code}',
        );
      }
    }

    final originalBytes = await imageFile.readAsBytes();
    return _normalizeVisionImageWithFlutterCodec(originalBytes);
  }

  Future<Uint8List> _normalizeVisionImageWithFlutterCodec(
    Uint8List originalBytes, {
    int maxDimension = 1024,
  }) async {
    ui.Codec? codec;
    ui.Image? decoded;
    ui.Picture? picture;
    ui.Image? normalized;
    try {
      codec = await ui.instantiateImageCodec(originalBytes);
      final frame = await codec.getNextFrame();
      decoded = frame.image;
      final longestSide = math.max(decoded.width, decoded.height);
      final scale = longestSide > maxDimension
          ? maxDimension / longestSide
          : 1.0;
      final targetWidth = math.max(1, (decoded.width * scale).round());
      final targetHeight = math.max(1, (decoded.height * scale).round());

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
      canvas.drawImageRect(
        decoded,
        ui.Rect.fromLTWH(
          0,
          0,
          decoded.width.toDouble(),
          decoded.height.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
        paint,
      );
      picture = recorder.endRecording();
      normalized = await picture.toImage(targetWidth, targetHeight);
      final pngBytes = await normalized.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (pngBytes == null || pngBytes.lengthInBytes == 0) {
        throw const RuntimeUnavailableException('图片 PNG 编码失败，请换一张图片重试。');
      }
      return Uint8List.sublistView(pngBytes);
    } catch (error) {
      if (error is RuntimeUnavailableException) rethrow;
      throw RuntimeUnavailableException('图片预处理失败，请换一张图片重试：$error');
    } finally {
      normalized?.dispose();
      picture?.dispose();
      decoded?.dispose();
    }
  }

  String _ascii(Uint8List bytes, int offset, int count) {
    return _asciiBytes(bytes, offset, count);
  }

  static String _asciiBytes(Uint8List bytes, int offset, int count) {
    if (offset + count > bytes.length) return '';
    return String.fromCharCodes(bytes.sublist(offset, offset + count));
  }

  List<fg.Tool> _iosSkillToolsFor(GemmaRequest request) {
    if (request.enabledSkillNames.isEmpty &&
        request.enabledSkillDetails.isEmpty) {
      return const [];
    }
    return const [
      fg.Tool(
        name: 'loadSkill',
        description:
            'Loads an enabled skill by name and returns its full instructions.',
        parameters: {
          'skillName': {
            'type': 'string',
            'description': 'The name of the enabled skill to load.',
          },
        },
      ),
      fg.Tool(
        name: 'runJs',
        description:
            'Attempts to run a JS skill. iOS/Dart execution is not connected yet and returns an honest pending result.',
        parameters: {
          'skillName': {'type': 'string'},
          'scriptName': {'type': 'string'},
          'data': {'type': 'string'},
        },
      ),
      fg.Tool(
        name: 'runIntent',
        description:
            'Attempts to run a platform intent. iOS/Dart execution is not connected yet and returns an honest pending result.',
        parameters: {
          'intent': {'type': 'string'},
          'parameters': {'type': 'string'},
        },
      ),
    ];
  }

  Map<String, dynamic> _executeDartSkillTool(
    fg.FunctionCallResponse call,
    GemmaRequest request,
  ) {
    final normalizedName = call.name.replaceAll('_', '').toLowerCase();
    switch (normalizedName) {
      case 'loadskill':
        final requestedName =
            (call.args['skillName'] ?? call.args['skill_name'] ?? '')
                .toString()
                .trim();
        final skill = request.enabledSkillDetails.firstWhere(
          (skill) => skill['name'] == requestedName,
          orElse: () => const {},
        );
        if (skill.isEmpty) {
          return {
            'status': 'failed',
            'skill_name': requestedName,
            'error': 'Skill not found or not enabled.',
          };
        }
        return {
          'status': 'succeeded',
          'skill_name': skill['name'] ?? requestedName,
          'skill_instructions':
              '---\nname: ${skill['name'] ?? requestedName}\ndescription: ${skill['description'] ?? ''}\n---\n\n${skill['instructions'] ?? ''}',
        };
      case 'runjs':
        return {
          'status': 'pending_bridge',
          'skill_name':
              (call.args['skillName'] ?? call.args['skill_name'] ?? '')
                  .toString(),
          'script_name':
              (call.args['scriptName'] ??
                      call.args['script_name'] ??
                      'index.html')
                  .toString(),
          'data': (call.args['data'] ?? '{}').toString(),
          'result':
              'iOS/Dart JS execution bridge is not implemented yet. Do not claim this JS skill has executed.',
        };
      case 'runintent':
        return {
          'status': 'pending_bridge',
          'intent': (call.args['intent'] ?? '').toString(),
          'parameters': (call.args['parameters'] ?? '{}').toString(),
          'result':
              'iOS/Dart intent execution bridge is not implemented yet. Do not claim this platform action has executed.',
        };
      default:
        return {'status': 'failed', 'error': 'Unsupported tool: ${call.name}'};
    }
  }

  String _visionPrompt(String prompt) {
    final trimmed = prompt.trim();
    if (_isDefaultVisionPrompt(trimmed)) {
      return 'Look at the image carefully and describe what is visible. Start with the main foreground subject and people, then mention background context separately. When counting people, report the main/foreground people first and keep tiny distant background figures or reflections separate as uncertain background details; do not merge them into one confident main count. Respond in $_preferredReplyLanguageName.';
    }
    return 'Use the image as primary evidence and answer the user request. Distinguish main foreground subjects from tiny distant background figures or reflections, especially for people counts; if a visual detail is uncertain, say it is uncertain instead of giving one blended count. Respond in $_preferredReplyLanguageName. User request: $trimmed';
  }

  String _audioPrompt(String prompt) {
    final trimmed = prompt.trim();
    if (_isDefaultAudioPrompt(trimmed)) {
      return 'This is a speech recognition task. Listen to the attached audio clip carefully and transcribe the speech verbatim as accurately as possible. Preserve names, numbers, dates, and short phrases. Do not add unrelated content. Respond in $_preferredReplyLanguageName. If any word is unclear, mark only that word as uncertain.';
    }
    return 'Use the attached audio clip as primary evidence. First transcribe or identify the relevant speech/sounds accurately, then answer the user request. Do not invent unheard words. If the audio is unclear, state exactly what is uncertain. Respond in $_preferredReplyLanguageName. User request: $trimmed';
  }

  String _imageAndAudioPrompt(String prompt) {
    final trimmed = prompt.trim();
    final request = trimmed.isEmpty
        ? 'Describe and summarize the attached media.'
        : trimmed;
    return 'Use the attached image and audio clip as primary evidence. First understand the visual and audio content, then answer the user request. If any part is unclear, say what is uncertain. Respond in $_preferredReplyLanguageName. User request: $request';
  }

  String _androidPromptForRequest(
    GemmaRequest request, {
    required bool includeSystemContext,
  }) {
    final prompt = includeSystemContext
        ? _contextualPrompt(request)
        : request.prompt.trim();
    final hasImage = request.imagePaths.isNotEmpty;
    final hasAudio = request.audioPaths.isNotEmpty;
    if (hasImage && hasAudio) return _imageAndAudioPrompt(prompt);
    if (hasImage) return _visionPrompt(prompt);
    if (hasAudio) return _audioPrompt(prompt);
    return prompt;
  }

  String _contextualPrompt(GemmaRequest request) {
    final prompt = request.prompt.trim();
    final prefix = StringBuffer();
    final systemPrompt = request.systemPrompt?.trim();
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      prefix.writeln('System instructions:');
      prefix.writeln(systemPrompt);
      prefix.writeln();
    }
    if (request.enabledSkillNames.isNotEmpty) {
      prefix.writeln('Enabled skills: ${request.enabledSkillNames.join(', ')}');
      prefix.writeln();
    }
    final context = prefix.toString().trim();
    if (context.isEmpty) return prompt;
    if (prompt.isEmpty) return context;
    return '$context\n\nUser request:\n$prompt';
  }

  bool _isDefaultVisionPrompt(String prompt) {
    return prompt.isEmpty ||
        prompt == '请描述这张图片。' ||
        prompt == 'Describe this image.';
  }

  bool _isDefaultAudioPrompt(String prompt) {
    return prompt.isEmpty ||
        prompt == '请识别并总结这段语音内容。' ||
        prompt == '请逐字转写这段语音。' ||
        prompt == 'Listen to this audio and summarize it.' ||
        prompt == 'Transcribe this audio verbatim.';
  }

  String get _preferredReplyLanguageName {
    final code = ui.PlatformDispatcher.instance.locale.languageCode
        .toLowerCase();
    switch (code) {
      case 'zh':
        return 'Simplified Chinese';
      case 'ja':
        return 'Japanese';
      case 'ko':
        return 'Korean';
      case 'fr':
        return 'French';
      case 'de':
        return 'German';
      case 'es':
        return 'Spanish';
      case 'pt':
        return 'Portuguese';
      case 'ru':
        return 'Russian';
      case 'ar':
        return 'Arabic';
      case 'hi':
        return 'Hindi';
      default:
        return 'English';
    }
  }

  Future<void> _restoreAndroidTextRuntime(GemmaModelConfig config) async {
    try {
      if (!_androidRuntimeMatches(
        supportImage: false,
        supportAudio: false,
        supportSkills: false,
        enabledSkillNames: const [],
        accelerator: GemmaAccelerator.cpu.id,
      )) {
        await _initializeAndroidRuntime(
          config,
          supportImage: false,
          supportAudio: false,
          supportSkills: false,
        );
      }
    } catch (_) {}
  }

  bool _androidRuntimeMatches({
    required bool supportImage,
    required bool supportAudio,
    required bool supportSkills,
    required List<String> enabledSkillNames,
    required String accelerator,
  }) {
    return _initialized &&
        _androidSupportImage == supportImage &&
        _androidSupportAudio == supportAudio &&
        _androidSupportSkills == supportSkills &&
        _sameStringList(_androidEnabledSkillNames, enabledSkillNames) &&
        _androidAccelerator == accelerator;
  }

  bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  List<String> _candidateAndroidAccelerators(
    GemmaModelConfig config, {
    required bool supportImage,
    required bool supportAudio,
  }) {
    final primary = _selectAndroidAccelerator(
      config,
      supportImage: supportImage,
      supportAudio: supportAudio,
    );
    if (supportAudio && !supportImage && primary != 'cpu') {
      return [primary, 'cpu'];
    }
    return [primary];
  }

  String _selectAndroidAccelerator(
    GemmaModelConfig config, {
    required bool supportImage,
    required bool supportAudio,
  }) {
    final wantsMultimodal = supportImage || supportAudio;
    if (!wantsMultimodal) return 'cpu';
    final supportsGpu = config.accelerators.contains(GemmaAccelerator.gpu);
    if (supportsGpu) return GemmaAccelerator.gpu.id;
    return config.accelerators.isNotEmpty
        ? config.accelerators.first.id
        : GemmaAccelerator.cpu.id;
  }

  bool _isCompiledModelInvocationError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('failed to invoke the compiled model') ||
        normalized.contains('status code: 13') ||
        normalized.contains('status code: 12');
  }

  @override
  Future<void> stop() async {
    if (Platform.isIOS) {
      _iosRawFfiClient?.cancelGeneration();
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
      _iosRawFfiClient?.shutdown();
      _iosRawFfiClient = null;
      await _flutterGemmaChat?.session.close();
      _flutterGemmaChat = null;
      await _flutterGemmaModel?.close();
      _flutterGemmaModel = null;
    } else if (Platform.isAndroid) {
      await _methodChannel.invokeMethod<void>('dispose');
      _androidSupportImage = false;
      _androidSupportAudio = false;
      _androidSupportSkills = false;
      _androidEnabledSkillNames = const [];
      _androidAccelerator = GemmaAccelerator.cpu.id;
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

  String _formatToolResultEvent(Map<dynamic, dynamic> event) {
    final skillName = event['skill_name']?.toString() ?? 'skill';
    final status = event['status']?.toString() ?? 'done';
    final result = event['result']?.toString().trim() ?? '';
    final imagePath = event['image_path']?.toString().trim() ?? '';
    final webviewUrl = event['webview_url']?.toString().trim() ?? '';
    final buffer = StringBuffer('\n\n**Skill result: $skillName** ($status)');
    if (result.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(result);
    }
    if (webviewUrl.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Webview output: `$webviewUrl`');
    }
    if (imagePath.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('[[skill_image:$imagePath]]');
    }
    buffer.writeln();
    return buffer.toString();
  }

  void _handleRuntimeEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type']?.toString();
    switch (type) {
      case 'token':
        _activeGenerationController?.add(event['text']?.toString() ?? '');
      case 'done':
        _activeGenerationController?.close();
      case 'tool_result':
        _activeGenerationController?.add(_formatToolResultEvent(event));
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
