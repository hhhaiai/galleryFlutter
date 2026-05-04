import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:ui' show PlatformDispatcher;

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
  bool _androidSupportImage = false;
  bool _androidSupportAudio = false;
  bool _androidSupportSkills = false;
  String _androidAccelerator = GemmaAccelerator.cpu.id;
  List<String> _androidEnabledSkillNames = const [];
  fg.InferenceModel? _flutterGemmaModel;
  fg.InferenceChat? _flutterGemmaChat;

  @override
  Future<void> initialize(GemmaModelConfig config) async {
    final previousConfig = _config;
    _config = config;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    if (Platform.isIOS) {
      final modelPath = await _resolveModelPath(config);
      await _initializeFlutterGemma(config, modelPath);
      _initialized = true;
      return;
    }

    _eventSubscription ??= _eventChannel.receiveBroadcastStream().listen(
      _handleRuntimeEvent,
      onError: (Object error) => _activeGenerationController?.addError(error),
    );

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
    final modelPath = await _resolveModelPath(config);
    await _methodChannel.invokeMethod<void>('initialize', {
      'modelPath': modelPath,
      'topK': config.topK,
      'topP': config.topP,
      'temperature': config.temperature,
      'maxTokens': 1024,
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

  Stream<String> _generateWithFlutterGemma(GemmaRequest request) async* {
    if (request.audioPaths.isNotEmpty) {
      throw const RuntimeUnavailableException(
        'iOS 当前的 flutter_gemma + Gemma-4-E2B-it 音频理解链路会触发 Failed to start streaming (code: 13)。为保证稳定性，iOS 端暂时关闭语音输入 / Live 语音通话；本项目不会用非 Gemma ASR 方案替代 Gemma 原生 audio 能力验收。',
      );
    }
    final model = _flutterGemmaModel;
    if (model == null) {
      throw const RuntimeUnavailableException('iOS flutter_gemma model 尚未初始化。');
    }
    final prompt = _contextualPrompt(request);

    // iOS .litertlm FFI multimodal sessions are not reliably reusable. Rebuild
    // per image request so text/image modalities stay isolated. Audio is
    // currently disabled on iOS for stability with Gemma-4-E2B-it.
    final isImageRequest = request.imagePaths.isNotEmpty;
    if (isImageRequest) {
      final config = _config ?? gemma4E2bIt;
      final modelPath = await _resolveModelPath(config);
      await _initializeFlutterGemma(
        config,
        modelPath,
        forceReload: true,
        supportImage: isImageRequest,
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
    final tools = _iosSkillToolsFor(request);
    final chat = await currentModel.createChat(
      temperature: _config?.temperature ?? gemma4E2bIt.temperature,
      topK: _config?.topK ?? gemma4E2bIt.topK,
      topP: _config?.topP ?? gemma4E2bIt.topP,
      supportImage: _config?.supportImage ?? gemma4E2bIt.supportImage,
      supportAudio: false,
      modelType: fg.ModelType.gemma4,
      isThinking: false,
      tools: tools,
      supportsFunctionCalls: tools.isNotEmpty,
      toolChoice: tools.isEmpty ? fg.ToolChoice.none : fg.ToolChoice.auto,
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
      return 'Look at the image and describe the main objects, scene, visible text, and important details. Respond in $_preferredReplyLanguageName.';
    }
    return 'Use the image as primary evidence and answer the user request. Respond in $_preferredReplyLanguageName. User request: $trimmed';
  }

  String _audioPrompt(String prompt) {
    final trimmed = prompt.trim();
    if (_isDefaultAudioPrompt(trimmed)) {
      return 'Listen to the attached audio clip and accurately identify the useful speech, sounds, requests, numbers, names, and key details. Then summarize or answer in $_preferredReplyLanguageName.';
    }
    return 'Use the attached audio clip as primary evidence and answer the user request. If the audio is unclear, say exactly what is uncertain. Respond in $_preferredReplyLanguageName. User request: $trimmed';
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
        prompt == 'Listen to this audio and summarize it.';
  }

  String get _preferredReplyLanguageName {
    final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
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
