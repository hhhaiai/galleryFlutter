import 'dart:async';
import 'dart:collection';
import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';

import 'audio_input_service.dart';
import '../../core/model/gemma_model_config.dart';
import '../../core/runtime/local_gemma_runtime.dart';
import '../../core/runtime/platform_gemma_runtime.dart';
import '../models/model_download_service.dart';
import '../models/models_drawer.dart';
import '../prompt_lab/prompt_templates.dart';
import '../skills/skill.dart';
import '../skills/skill_repository.dart';
import '../skills/skills_hub_sheet.dart';

class GemmaHomeScreen extends StatefulWidget {
  const GemmaHomeScreen({super.key});

  @override
  State<GemmaHomeScreen> createState() => _GemmaHomeScreenState();
}

class _GemmaHomeScreenState extends State<GemmaHomeScreen> {
  final _runtime = createLocalGemmaRuntime();
  final _downloadController = ModelDownloadController();
  final _imagePicker = ImagePicker();
  final _audioInput = AudioInputService();
  final _skillRepository = SkillRepository();
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  StreamSubscription<ModelDownloadStatus>? _downloadSubscription;
  StreamSubscription<AudioInputEvent>? _audioEventSubscription;

  ModelDownloadStatus _downloadStatus = const ModelDownloadStatus(
    type: ModelDownloadStatusType.notDownloaded,
  );
  PromptTemplate _template = promptLabTemplates.first;
  List<GemmaSkill> _onlineSkills = const [];
  late final Set<String> _enabledSkillNames = {
    for (final skill in builtInSkills) skill.name,
  };
  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      role: _ChatRole.assistant,
      text:
          '你好，我是 galleryFlutter。本地模型下载完成后，我可以用 Gemma-4-E2B-it 进行对话，并逐步支持图片、语音、Skills 和 Prompt Lab。',
    ),
  ];
  final Set<_ComposerMode> _enabledModes = {_ComposerMode.text};
  final List<XFile> _attachedImages = [];
  final List<AudioAttachment> _attachedAudios = [];
  static const _liveMinSegmentDuration = Duration(milliseconds: 1600);
  static const _liveMaxSegmentDuration = Duration(seconds: 7);
  static const _liveSilenceHold = Duration(milliseconds: 850);
  static const _liveSpeechThreshold = 0.16;
  static const _liveUiTick = Duration(seconds: 1);
  bool _recording = false;
  bool _autoStoppingRecording = false;
  bool _running = false;
  bool _stopRequested = false;
  bool _liveCallActive = false;
  bool _liveCaptureRunning = false;
  bool _liveProcessorRunning = false;
  bool _liveSegmentProcessing = false;
  String _liveStatusText = '';
  String _liveAssistantPreview = '';
  String _liveDraftPreview = '';
  String _liveHeardContext = '';
  Duration _liveElapsed = Duration.zero;
  Completer<void>? _liveStopSignal;
  Completer<void>? _liveSegmentCutSignal;
  Timer? _liveUiTimer;
  final Queue<AudioAttachment> _livePendingSegments = Queue<AudioAttachment>();
  double _liveMicLevel = 0;
  bool _liveSpeechDetectedInSegment = false;
  int _liveLastSpeechElapsedMs = 0;

  @override
  void initState() {
    super.initState();
    _downloadSubscription = _downloadController.statusStream.listen((status) {
      if (mounted) setState(() => _downloadStatus = status);
    });
    _audioEventSubscription = _audioInput.events.listen(_handleAudioInputEvent);
    _downloadController.refreshStatus(gemma4E2bIt).then((status) {
      if (mounted) setState(() => _downloadStatus = status);
    });
    _loadOnlineSkills();
  }

  @override
  void dispose() {
    _liveStopSignal?.complete();
    _liveSegmentCutSignal?.complete();
    _liveUiTimer?.cancel();
    _downloadSubscription?.cancel();
    _audioEventSubscription?.cancel();
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _downloadController.dispose();
    _runtime.dispose();
    super.dispose();
  }

  Future<void> _downloadModel() async {
    await _downloadController.download(gemma4E2bIt);
  }

  Future<void> _loadOnlineSkills() async {
    try {
      final skills = await _skillRepository.loadOnlineSkills();
      if (!mounted) return;
      setState(() {
        _onlineSkills = skills;
        for (final skill in skills) {
          _enabledSkillNames.add(skill.name);
        }
      });
    } catch (error) {
      _showSnackBar('线上 Skills 加载失败：$error');
    }
  }

  List<GemmaSkill> get _allSkills => [...builtInSkills, ..._onlineSkills];

  List<GemmaSkill> get _selectedSkills => _allSkills
      .where((skill) => _enabledSkillNames.contains(skill.name))
      .toList(growable: false);

  Future<void> _send() async {
    if (_liveCallActive) {
      _showSnackBar('Live 语音通话进行中，请先停止后再手动发送。');
      return;
    }
    final rawInput = _inputController.text.trim();
    final imagePaths = _attachedImages.map((image) => image.path).toList();
    final audioAttachments = List<AudioAttachment>.of(_attachedAudios);
    final audioPaths = audioAttachments.map((audio) => audio.path).toList();
    if ((rawInput.isEmpty && imagePaths.isEmpty && audioPaths.isEmpty) ||
        _running) {
      return;
    }
    _stopRequested = false;

    final promptInput = rawInput.isEmpty
        ? _defaultComposerPromptFor(
            hasImages: imagePaths.isNotEmpty,
            hasAudios: audioPaths.isNotEmpty,
          )
        : rawInput;
    final prompt = _enabledModes.contains(_ComposerMode.promptLab)
        ? _template.buildPrompt(promptInput)
        : promptInput;
    final userText = _buildUserMessageText(
      rawInput,
      imagePaths.length,
      audioAttachments.length,
    );
    if (!_downloadStatus.isDownloaded) {
      _showSnackBar('请先从左侧菜单进入「Models」下载 ${gemma4E2bIt.name}。下载完成后再发送。');
      return;
    }
    _inputController.clear();
    setState(() {
      _attachedImages.clear();
      _attachedAudios.clear();
      if (imagePaths.isEmpty) _enabledModes.remove(_ComposerMode.image);
      if (audioPaths.isEmpty) _enabledModes.remove(_ComposerMode.voice);
    });

    await _runRequest(
      prompt: prompt,
      userText: userText,
      imagePaths: imagePaths,
      audioAttachments: audioAttachments,
      systemPrompt: _enabledModes.contains(_ComposerMode.skills)
          ? buildAgentSkillsSystemPrompt(_selectedSkills)
          : null,
      enabledSkillNames: _enabledModes.contains(_ComposerMode.skills)
          ? _selectedSkills.map((skill) => skill.name).toList()
          : const [],
      enabledSkillDetails: _enabledModes.contains(_ComposerMode.skills)
          ? _selectedSkills.map((skill) => skill.toRuntimeMap()).toList()
          : const [],
    );
  }

  Future<void> _runRequest({
    required String prompt,
    required String userText,
    List<String> imagePaths = const [],
    List<AudioAttachment> audioAttachments = const [],
    String? systemPrompt,
    List<String> enabledSkillNames = const [],
    List<Map<String, String>> enabledSkillDetails = const [],
  }) async {
    setState(() {
      _messages.add(
        _ChatMessage(
          role: _ChatRole.user,
          text: userText,
          imagePaths: imagePaths,
          audioAttachments: audioAttachments,
        ),
      );
      _messages.add(
        const _ChatMessage(
          role: _ChatRole.assistant,
          text: '',
          streaming: true,
        ),
      );
      _running = true;
    });
    _scrollToBottom();

    try {
      await _runtime.initialize(gemma4E2bIt);
      await for (final token in _runtime.generate(
        GemmaRequest(
          prompt: prompt,
          systemPrompt: systemPrompt,
          imagePaths: imagePaths,
          audioPaths: audioAttachments.map((audio) => audio.path).toList(),
          enabledSkillNames: enabledSkillNames,
          enabledSkillDetails: enabledSkillDetails,
        ),
      )) {
        if (_stopRequested) break;
        _appendAssistantText(token);
      }
      _finishAssistantMessage(stopped: _stopRequested);
    } on RuntimeUnavailableException catch (error) {
      _appendAssistantText(error.message, done: true);
    } catch (error) {
      _appendAssistantText('生成失败：$error', done: true);
    }
  }

  void _appendAssistantText(String token, {bool done = false}) {
    if (!mounted) return;
    final skillImagePattern = RegExp(r'\[\[skill_image:(.*?)\]\]');
    final skillImagePaths = skillImagePattern
        .allMatches(token)
        .map((match) => match.group(1)?.trim() ?? '')
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    final cleanToken = token.replaceAll(skillImagePattern, '').trimRight();
    setState(() {
      final last = _messages.removeLast();
      _messages.add(
        last.copyWith(
          text: '${last.text}$cleanToken',
          imagePaths: skillImagePaths.isEmpty
              ? last.imagePaths
              : [...last.imagePaths, ...skillImagePaths],
          streaming: !done,
        ),
      );
      if (done) _running = false;
    });
    _scrollToBottom();
  }

  void _stopGeneration() {
    if (_liveCallActive) {
      unawaited(_stopLiveVoiceCall(showToast: true));
    }
    if (!_running || _stopRequested) return;
    _stopCurrentGeneration();
  }

  void _finishAssistantMessage({bool stopped = false}) {
    if (!mounted) return;
    setState(() {
      final last = _messages.removeLast();
      final text = stopped && last.text.trim().isNotEmpty
          ? '${last.text}\n\n_已停止生成。_'
          : last.text;
      _messages.add(last.copyWith(text: text, streaming: false));
      _running = false;
      _stopRequested = false;
    });
    _scrollToBottom();
  }

  void _handleAudioInputEvent(AudioInputEvent event) {
    if (!mounted) return;
    if (event.type == 'recording') {
      if (event.state == 'started') {
        setState(() => _liveMicLevel = 0);
      } else if (event.state == 'stopped' || event.state == 'cancelled') {
        setState(() => _liveMicLevel = 0);
        if (event.state == 'stopped' &&
            event.reason == 'maxDuration' &&
            _recording &&
            !_liveCallActive) {
          unawaited(_completeAutoStoppedRecording());
        }
      } else if (event.state == 'failed') {
        setState(() {
          _liveMicLevel = 0;
          _recording = false;
        });
        _showSnackBar('录音失败，请重试。');
      }
      return;
    }
    if (event.type != 'level' || !_liveCallActive || !_recording) return;
    final amplitude = event.amplitude.clamp(0, 1).toDouble();
    setState(() => _liveMicLevel = amplitude);
    if (amplitude >= _liveSpeechThreshold) {
      _liveSpeechDetectedInSegment = true;
      _liveLastSpeechElapsedMs = event.elapsedMs;
      return;
    }
    if (!_liveSpeechDetectedInSegment) return;
    final elapsed = Duration(milliseconds: event.elapsedMs);
    final silentForMs = event.elapsedMs - _liveLastSpeechElapsedMs;
    if (elapsed >= _liveMinSegmentDuration &&
        silentForMs >= _liveSilenceHold.inMilliseconds) {
      _completeLiveSegmentCut();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _buildUserMessageText(
    String rawInput,
    int imageCount,
    int audioCount,
  ) {
    final text = rawInput.isEmpty
        ? _defaultComposerPromptFor(
            hasImages: imageCount > 0,
            hasAudios: audioCount > 0,
          )
        : rawInput;
    return text;
  }

  Future<void> _showImageSourceSheet() async {
    if (_running) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              subtitle: const Text('调用相机拍摄一张图片'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              subtitle: const Text('加载手机中的图片'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 92,
        maxWidth: 1600,
      );
      if (image == null || !mounted) return;
      setState(() {
        _attachedImages
          ..clear()
          ..add(image);
        _enabledModes.add(_ComposerMode.image);
      });
      _inputFocusNode.requestFocus();
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('图片获取失败：${error.message ?? error.code}')),
      );
    }
  }

  void _removeAttachedImage(XFile image) {
    setState(() {
      _attachedImages.remove(image);
      if (_attachedImages.isEmpty) _enabledModes.remove(_ComposerMode.image);
    });
  }

  void _removeAttachedAudio(AudioAttachment audio) {
    setState(() {
      _attachedAudios.remove(audio);
      if (_attachedAudios.isEmpty) _enabledModes.remove(_ComposerMode.voice);
    });
  }

  Future<void> _completeAutoStoppedRecording() async {
    if (_autoStoppingRecording || !_recording || _liveCallActive) return;
    _autoStoppingRecording = true;
    try {
      final audio = await _audioInput.stopRecording();
      if (!mounted) return;
      setState(() => _recording = false);
      if (audio == null) return;
      setState(() {
        _attachedAudios
          ..clear()
          ..add(audio);
        _enabledModes.add(_ComposerMode.voice);
      });
      _showSnackBar('已达到 30 秒上限，录音已自动附加到输入框。');
    } on PlatformException catch (error) {
      if (mounted) setState(() => _recording = false);
      _showSnackBar('录音自动停止失败：${error.message ?? error.code}');
    } finally {
      _autoStoppingRecording = false;
    }
  }

  Future<void> _showAudioSourceSheet() async {
    if (_running) return;
    final action = await showModalBottomSheet<_AudioAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                _recording ? Icons.stop_circle_outlined : Icons.mic_none,
              ),
              title: Text(_recording ? '停止录音' : '实时录音'),
              subtitle: const Text('像微信一样录一段语音，发送后可点击播放'),
              onTap: () => Navigator.pop(context, _AudioAction.record),
            ),
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: const Text('选择语音文件'),
              subtitle: const Text('从系统文件中选择 wav/m4a/mp3 等音频'),
              onTap: () => Navigator.pop(context, _AudioAction.pickFile),
            ),
            ListTile(
              leading: const Icon(Icons.phone_in_talk_outlined),
              title: Text(_liveCallActive ? '停止 Live 语音通话' : '开启 Live 语音通话'),
              subtitle: Text(
                _liveCallActive
                    ? (_liveStatusText.isEmpty
                          ? '停止当前 Live 录音与回复循环'
                          : _liveStatusText)
                    : '实时连续录音切段 + 本地模型文字回复（Phase 1）',
              ),
              onTap: () => Navigator.pop(context, _AudioAction.liveCallToggle),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    switch (action) {
      case _AudioAction.record:
        await _toggleRecording();
      case _AudioAction.pickFile:
        await _pickAudioFile();
      case _AudioAction.liveCallToggle:
        await _toggleLiveVoiceCall();
    }
  }

  Future<void> _pickAudioFile() async {
    if (Platform.isIOS) {
      _showSnackBar(
        'iOS 语音理解当前为稳定性已暂时关闭；本项目会继续验证 Gemma 原生 audio，不用非 Gemma ASR 方案替代验收。',
      );
      return;
    }
    if (_liveCallActive) {
      _showSnackBar('Live 语音通话进行中，请先停止 Live 再选择语音文件。');
      return;
    }
    try {
      final audio = await _audioInput.pickAudioFile();
      if (audio == null || !mounted) return;
      setState(() {
        _attachedAudios
          ..clear()
          ..add(audio);
        _enabledModes.add(_ComposerMode.voice);
      });
    } on PlatformException catch (error) {
      _showSnackBar('语音文件选择失败：${error.message ?? error.code}');
    }
  }

  Future<void> _toggleRecording() async {
    if (Platform.isIOS) {
      _showSnackBar(
        'iOS 实时录音当前为稳定性已暂时关闭；当前 flutter_gemma + Gemma-4-E2B-it 会触发 code 13。',
      );
      return;
    }
    if (_liveCallActive) {
      _showSnackBar('Live 语音通话进行中，请先停止 Live。');
      return;
    }
    try {
      if (!_recording) {
        await _audioInput.startRecording();
        if (!mounted) return;
        setState(() {
          _recording = true;
          _enabledModes.add(_ComposerMode.voice);
        });
        _showSnackBar('开始录音，再点语音按钮可停止并附加到输入框。');
        return;
      }
      final audio = await _audioInput.stopRecording();
      if (!mounted) return;
      setState(() => _recording = false);
      if (audio == null) return;
      setState(() {
        _attachedAudios
          ..clear()
          ..add(audio);
        _enabledModes.add(_ComposerMode.voice);
      });
    } on PlatformException catch (error) {
      if (mounted) setState(() => _recording = false);
      _showSnackBar('录音失败：${error.message ?? error.code}');
    }
  }

  Future<void> _toggleLiveVoiceCall() async {
    if (Platform.isIOS) {
      _showSnackBar(
        'iOS Live 语音通话当前为稳定性已暂时关闭；当前 flutter_gemma + Gemma-4-E2B-it 音频链路会触发 code 13。',
      );
      return;
    }
    if (_liveCallActive) {
      await _stopLiveVoiceCall(showToast: true);
      return;
    }
    if (_running || _recording) {
      _showSnackBar('当前正在生成或录音，请先结束当前操作后再开启 Live。');
      return;
    }
    if (!_downloadStatus.isDownloaded) {
      _showSnackBar('请先下载 ${gemma4E2bIt.name}，再开启 Live 语音通话。');
      return;
    }
    final supported = await _audioInput.isSupported;
    if (!supported) {
      _showSnackBar('当前平台暂不支持 Live 语音通话。');
      return;
    }
    _liveStopSignal?.complete();
    _liveStopSignal = Completer<void>();
    _liveSegmentCutSignal?.complete();
    _liveSegmentCutSignal = null;
    _liveUiTimer?.cancel();
    setState(() {
      _liveCallActive = true;
      _liveCaptureRunning = false;
      _liveProcessorRunning = false;
      _liveSegmentProcessing = false;
      _liveStatusText = '已接通，正在准备麦克风…';
      _liveAssistantPreview = '';
      _liveDraftPreview = '';
      _liveHeardContext = '';
      _liveElapsed = Duration.zero;
      _enabledModes.add(_ComposerMode.voice);
      _attachedAudios.clear();
    });
    _livePendingSegments.clear();
    _liveUiTimer = Timer.periodic(_liveUiTick, (_) {
      if (!mounted || !_liveCallActive) return;
      setState(() {
        _liveElapsed += _liveUiTick;
      });
    });
    _showSnackBar('Live 语音通话已开启：每 4 秒切一段，先语音理解，再返回文字。');
    unawaited(_runLiveVoiceLoop());
  }

  Future<void> _showSkillsHubSheet() {
    return showSkillsHubSheet(
      context: context,
      repository: _skillRepository,
      onlineSkills: _onlineSkills,
      enabledSkillNames: _enabledSkillNames,
      skillsModeEnabled: _enabledModes.contains(_ComposerMode.skills),
      onSkillsModeChanged: (enabled) {
        if (!mounted) return;
        setState(() {
          if (enabled) {
            _enabledModes.add(_ComposerMode.skills);
          } else {
            _enabledModes.remove(_ComposerMode.skills);
          }
        });
      },
      onOnlineSkillsChanged: (skills) {
        if (!mounted) return;
        setState(() => _onlineSkills = skills);
      },
      onEnabledSkillNamesChanged: (names) {
        if (!mounted) return;
        setState(() {
          _enabledSkillNames
            ..clear()
            ..addAll(names);
        });
      },
      onMessage: _showSnackBar,
    );
  }

  void _resetLiveSegmentationTracking() {
    _liveSpeechDetectedInSegment = false;
    _liveLastSpeechElapsedMs = 0;
    _liveSegmentCutSignal?.complete();
    _liveSegmentCutSignal = Completer<void>();
  }

  void _completeLiveSegmentCut() {
    if (_liveSegmentCutSignal == null || _liveSegmentCutSignal!.isCompleted) {
      return;
    }
    _liveSegmentCutSignal!.complete();
  }

  Future<void> _runLiveVoiceLoop() async {
    if (_liveCaptureRunning) return;
    _liveCaptureRunning = true;
    try {
      while (mounted && _liveCallActive) {
        _resetLiveSegmentationTracking();
        await _audioInput.startRecording();
        if (!mounted) return;
        setState(() {
          _recording = true;
          _liveStatusText = _liveSegmentProcessing
              ? '我在持续听，同时整理回复…'
              : '正在持续聆听…';
        });
        await Future.any([
          Future<void>.delayed(_liveMaxSegmentDuration),
          _liveSegmentCutSignal?.future ?? Future<void>.value(),
          _liveStopSignal?.future ?? Future<void>.value(),
        ]);
        if (!_liveCallActive) {
          await _audioInput.cancelRecording();
          if (mounted) setState(() => _recording = false);
          break;
        }
        final audio = await _audioInput.stopRecording();
        if (!mounted) return;
        setState(() {
          _recording = false;
        });
        if (audio == null) {
          setState(() {
            _liveStatusText = '这次没有收到有效音频，继续聆听…';
          });
          continue;
        }
        if (_isLikelySilent(audio)) {
          setState(() {
            _liveStatusText = '这次主要是环境声，继续聆听…';
          });
          continue;
        }
        _livePendingSegments.add(audio);
        unawaited(_runLiveProcessorLoop());
      }
    } on PlatformException catch (error) {
      _showSnackBar('Live 语音通话失败：${error.message ?? error.code}');
    } catch (error) {
      _showSnackBar('Live 语音通话失败：$error');
    } finally {
      _liveCaptureRunning = false;
      if (mounted) {
        setState(() {
          _liveCallActive = false;
          _liveCaptureRunning = false;
          _liveProcessorRunning = false;
          _liveSegmentProcessing = false;
          _recording = false;
          _liveStatusText = '';
          _liveDraftPreview = '';
          _liveHeardContext = '';
          _liveElapsed = Duration.zero;
        });
      }
      _livePendingSegments.clear();
      _liveUiTimer?.cancel();
      _liveUiTimer = null;
      _liveStopSignal = null;
    }
  }

  Future<void> _runLiveProcessorLoop() async {
    if (_liveProcessorRunning) return;
    _liveProcessorRunning = true;
    try {
      while (mounted && (_liveCallActive || _livePendingSegments.isNotEmpty)) {
        if (_livePendingSegments.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          continue;
        }
        final audio = _livePendingSegments.removeFirst();
        if (mounted) {
          setState(() {
            _liveSegmentProcessing = true;
            _liveStatusText = _recording ? '我在持续听，同时整理回复…' : '正在理解你刚才的话…';
          });
        }
        final delta = await _runLiveSegmentSafely(audio);
        if (!mounted) return;
        if (!_liveCallActive) break;
        setState(() {
          _liveSegmentProcessing = false;
          _liveStatusText = _recording
              ? '正在持续聆听…'
              : (delta.isEmpty ? '我在继续听，你可以接着说…' : '我在继续听，你可以接着说…');
        });
      }
    } finally {
      _liveProcessorRunning = false;
      if (mounted && !_liveCallActive) {
        setState(() {
          _liveSegmentProcessing = false;
          _liveDraftPreview = '';
        });
      }
    }
  }

  Future<void> _stopLiveVoiceCall({bool showToast = false}) async {
    if (!_liveCallActive && !_recording && !_liveSegmentProcessing) return;
    _liveCallActive = false;
    _liveStopSignal?.complete();
    _livePendingSegments.clear();
    if (_recording) {
      try {
        await _audioInput.cancelRecording();
      } catch (_) {}
    }
    if (_running) {
      _stopCurrentGeneration();
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _liveCaptureRunning = false;
        _liveProcessorRunning = false;
        _liveSegmentProcessing = false;
        _liveStatusText = '';
        _liveDraftPreview = '';
        _liveHeardContext = '';
        _liveElapsed = Duration.zero;
      });
    }
    _liveUiTimer?.cancel();
    _liveUiTimer = null;
    if (showToast) {
      _showSnackBar('Live 语音通话已停止。');
    }
  }

  Future<String> _runLiveSegment(AudioAttachment audio) async {
    if (!_downloadStatus.isDownloaded) {
      return '';
    }
    final previousPreview = _liveAssistantPreview;
    final heard = await _collectRuntimeResponse(
      GemmaRequest(
        prompt: _buildLiveUnderstandingPrompt(),
        audioPaths: [audio.path],
      ),
      onToken: (partial) {
        if (!mounted) return;
        setState(() {
          _liveStatusText = '正在听懂你刚才说的话…';
          _liveDraftPreview = partial;
        });
      },
    );
    final cleanedHeard = _sanitizeLiveDelta(heard);
    if (cleanedHeard.isEmpty) {
      if (mounted) {
        setState(() {
          _liveDraftPreview = '';
        });
      }
      return '';
    }

    _liveHeardContext = _appendLiveContext(
      _liveHeardContext,
      cleanedHeard,
      900,
    );
    final reply = await _collectRuntimeResponse(
      GemmaRequest(prompt: _buildLiveReplyPrompt(cleanedHeard)),
      onToken: (partial) {
        if (!mounted) return;
        setState(() {
          _liveStatusText = '我在根据你刚才的话持续回应…';
          _liveDraftPreview = _composeLivePreview(previousPreview, partial);
        });
      },
    );
    final delta = _sanitizeLiveDelta(reply);
    if (mounted) {
      setState(() {
        _liveAssistantPreview = delta.isEmpty
            ? previousPreview
            : _mergeLiveAssistantPreview(previousPreview, delta);
        _liveDraftPreview = '';
      });
    }
    return delta;
  }

  Future<String> _runLiveSegmentSafely(AudioAttachment audio) async {
    try {
      return await _runLiveSegment(audio);
    } on RuntimeUnavailableException catch (error) {
      if (!mounted) return '';
      setState(() {
        _liveSegmentProcessing = false;
        _liveDraftPreview = '';
        _liveStatusText = 'Live 语音理解暂不可用，已停止。';
      });
      _showSnackBar('Live 语音理解失败：${error.message}');
      await _stopLiveVoiceCall();
      return '';
    } on PlatformException catch (error) {
      if (!mounted) return '';
      setState(() {
        _liveSegmentProcessing = false;
        _liveDraftPreview = '';
        _liveStatusText = _recording
            ? '上一段语音处理失败，我还在继续听…'
            : '上一段语音处理失败，请继续说或稍后重试。';
      });
      _showSnackBar('Live 语音片段处理失败：${error.message ?? error.code}');
      return '';
    } catch (error) {
      if (!mounted) return '';
      setState(() {
        _liveSegmentProcessing = false;
        _liveDraftPreview = '';
        _liveStatusText = _recording
            ? '上一段语音处理失败，我还在继续听…'
            : '上一段语音处理失败，请继续说或稍后重试。';
      });
      _showSnackBar('Live 语音片段处理失败：$error');
      return '';
    }
  }

  Future<String> _collectRuntimeResponse(
    GemmaRequest request, {
    void Function(String partial)? onToken,
  }) async {
    _running = true;
    _stopRequested = false;
    final buffer = StringBuffer();
    try {
      await _runtime.initialize(gemma4E2bIt);
      await for (final token in _runtime.generate(request)) {
        if (_stopRequested || !_liveCallActive) break;
        buffer.write(token);
        onToken?.call(buffer.toString());
      }
    } finally {
      _running = false;
      _stopRequested = false;
    }
    return buffer.toString();
  }

  String _buildLiveUnderstandingPrompt() {
    return 'Extract only the useful information from this audio clip.\n'
        'Requirements:\n'
        '1. Recover the user facts, questions, requests, goals, times, places, numbers, and key terms as accurately as possible.\n'
        '2. If part of the audio is unclear, explicitly say which part is uncertain.\n'
        '3. Do not comfort, do not answer, do not give suggestions, and do not say that you are listening. Only perform understanding.\n'
        '4. Output 1 to 3 concise sentences in $_preferredReplyLanguageName.';
  }

  String _buildLiveReplyPrompt(String heard) {
    final custom = _inputController.text.trim();
    final base = custom.isEmpty
        ? 'You are in a continuous live voice conversation with the user. Reply naturally based on what the user just said.'
        : custom;
    final previousReply = _liveAssistantPreview.trim();
    final previousContext = previousReply.isEmpty
        ? '（暂无）'
        : _tailText(previousReply, 220);
    final heardContext = _liveHeardContext.trim().isEmpty
        ? heard
        : _tailText(_liveHeardContext, 400);
    return '$base\n\n'
        'This is a continuous phone-style conversation.\n'
        'Confirmed user context so far: $heardContext\n'
        'Newest understood content: $heard\n'
        'Your previous reply content: $previousContext\n\n'
        'Requirements:\n'
        '1. Respond to the newest understood content, not with generic emotional validation.\n'
        '2. If the user asked a question, answer it directly. If the user described a situation, provide a concrete judgment, summary, or next action.\n'
        '3. If part of the content is unclear, say what you understood, what remains unclear, and ask one concrete clarification question.\n'
        '4. Output only the new reply you want to say now. Do not repeat your previous reply.\n'
        '5. Keep the response short, direct, specific, and in $_preferredReplyLanguageName.\n'
        '6. If there is no new valid content, return an empty string.';
  }

  bool _isLikelySilent(AudioAttachment audio) {
    if (audio.waveform.isEmpty) return false;
    final average =
        audio.waveform.reduce((a, b) => a + b) / audio.waveform.length;
    return average < 0.12;
  }

  void _stopCurrentGeneration() {
    if (!_running || _stopRequested) return;
    _stopRequested = true;
    _runtime.stop();
    if (!_liveCallActive) {
      _finishAssistantMessage(stopped: true);
    }
  }

  String _sanitizeLiveDelta(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed == '""' || trimmed == "''") return '';
    return trimmed;
  }

  String _mergeLiveAssistantPreview(String previous, String delta) {
    if (previous.isEmpty) return delta;
    if (previous.endsWith(delta)) return previous;
    final normalizedPrevious = previous.replaceAll(RegExp(r'\s+'), ' ').trim();
    final normalizedDelta = delta.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalizedPrevious.endsWith(normalizedDelta)) return previous;
    return '$previous\n$delta';
  }

  String _appendLiveContext(String previous, String delta, int maxChars) {
    final merged = previous.trim().isEmpty ? delta.trim() : '$previous\n$delta';
    return _tailText(merged, maxChars);
  }

  String _composeLivePreview(String previous, String currentSegment) {
    final trimmed = currentSegment.trimLeft();
    if (trimmed.isEmpty) return previous;
    if (previous.isEmpty) return trimmed;
    return '$previous\n$trimmed';
  }

  String _tailText(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return text.substring(text.length - maxChars);
  }

  String get _preferredReplyLanguageName {
    final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode
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

  bool get _prefersChineseUi =>
      WidgetsBinding.instance.platformDispatcher.locale.languageCode
          .toLowerCase() ==
      'zh';

  String get _defaultImageComposerPrompt =>
      _prefersChineseUi ? '请描述这张图片。' : 'Describe this image.';

  String get _defaultAudioComposerPrompt => _prefersChineseUi
      ? '请识别并总结这段语音内容。'
      : 'Listen to this audio and summarize it.';

  String get _defaultMediaComposerPrompt => _prefersChineseUi
      ? '请结合图片和语音内容，识别关键信息并回答。'
      : 'Use both the image and audio to identify the key information and answer.';

  String _defaultComposerPromptFor({
    required bool hasImages,
    required bool hasAudios,
  }) {
    if (hasImages && hasAudios) return _defaultMediaComposerPrompt;
    if (hasImages) return _defaultImageComposerPrompt;
    return _defaultAudioComposerPrompt;
  }

  String get _liveElapsedLabel {
    final totalSeconds = _liveElapsed.inSeconds.clamp(0, 60 * 60 - 1);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get _liveCurrentPreview => _liveDraftPreview.trim().isNotEmpty
      ? _liveDraftPreview
      : _liveAssistantPreview;

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleMode(_ComposerMode mode) {
    if (mode == _ComposerMode.text) return;
    if (mode == _ComposerMode.image) {
      _showImageSourceSheet();
      return;
    }
    if (mode == _ComposerMode.voice) {
      _showAudioSourceSheet();
      return;
    }
    if (mode == _ComposerMode.skills) {
      _showSkillsHubSheet();
      return;
    }
    setState(() {
      if (_enabledModes.contains(mode)) {
        _enabledModes.remove(mode);
      } else {
        _enabledModes.add(mode);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const _AppTitle(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _ModelStatusChip(status: _downloadStatus),
          ),
        ],
      ),
      drawer: ModelsDrawer(
        status: _downloadStatus,
        onDownload: _downloadModel,
        onCancel: _downloadController.cancel,
        onDelete: () => _downloadController.delete(gemma4E2bIt),
        onRefresh: () => _downloadController.refreshStatus(gemma4E2bIt),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _CapabilityRail(
                enabledModes: _enabledModes,
                template: _template,
                onToggleMode: _toggleMode,
                onTemplateChanged: (template) =>
                    setState(() => _template = template),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                  child: _ChatTranscript(
                    controller: _scrollController,
                    messages: _messages,
                  ),
                ),
              ),
              _Composer(
                controller: _inputController,
                focusNode: _inputFocusNode,
                enabledModes: _enabledModes,
                attachedImages: _attachedImages,
                attachedAudios: _attachedAudios,
                recording: _recording,
                liveCallActive: _liveCallActive,
                liveElapsedLabel: _liveElapsedLabel,
                liveMicLevel: _liveMicLevel,
                liveStatusText: _liveStatusText,
                liveAssistantPreview: _liveCurrentPreview,
                running: _running || _liveCallActive,
                onToggleMode: _toggleMode,
                onRemoveImage: _removeAttachedImage,
                onRemoveAudio: _removeAttachedAudio,
                onPlayAudio: (audio) => _audioInput.play(audio.path),
                onSend: _send,
                onStop: _stopGeneration,
              ),
            ],
          ),
          if (_liveCallActive)
            Positioned.fill(
              child: _LiveCallOverlay(
                elapsedLabel: _liveElapsedLabel,
                micLevel: _liveMicLevel,
                statusText: _liveStatusText,
                assistantPreview: _liveCurrentPreview,
                processing: _liveSegmentProcessing,
                onStop: _stopGeneration,
              ),
            ),
        ],
      ),
    );
  }
}

class _AppTitle extends StatelessWidget {
  const _AppTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('galleryFlutter', style: Theme.of(context).textTheme.titleMedium),
        Text(
          'Gemma-4-E2B-it · Local AI',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _CapabilityRail extends StatelessWidget {
  const _CapabilityRail({
    required this.enabledModes,
    required this.template,
    required this.onToggleMode,
    required this.onTemplateChanged,
  });

  final Set<_ComposerMode> enabledModes;
  final PromptTemplate template;
  final ValueChanged<_ComposerMode> onToggleMode;
  final ValueChanged<PromptTemplate> onTemplateChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            for (final mode in _ComposerMode.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  avatar: Icon(mode.icon, size: 18),
                  label: Text(mode.label),
                  selected: enabledModes.contains(mode),
                  onSelected: mode == _ComposerMode.text
                      ? null
                      : (_) => onToggleMode(mode),
                ),
              ),
            if (enabledModes.contains(_ComposerMode.promptLab))
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: DropdownButton<PromptTemplate>(
                  value: template,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final item in promptLabTemplates)
                      DropdownMenuItem(value: item, child: Text(item.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) onTemplateChanged(value);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatTranscript extends StatelessWidget {
  const _ChatTranscript({required this.controller, required this.messages});

  final ScrollController controller;
  final List<_ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: messages.length,
      itemBuilder: (context, index) => _MessageBubble(message: messages[index]),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == _ChatRole.user;
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Card(
          elevation: 0,
          color: isUser
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.imagePaths.isNotEmpty) ...[
                  _SentImagePreviewGrid(imagePaths: message.imagePaths),
                  if (message.audioAttachments.isNotEmpty ||
                      message.text.trim().isNotEmpty)
                    const SizedBox(height: 10),
                ],
                if (message.audioAttachments.isNotEmpty) ...[
                  _VoiceMessageGrid(audios: message.audioAttachments),
                  if (message.text.trim().isNotEmpty)
                    const SizedBox(height: 10),
                ],
                if (message.text.trim().isNotEmpty || message.streaming)
                  _MarkdownMessageText(
                    text: message.text.isEmpty && message.streaming
                        ? '思考中…'
                        : message.text,
                    isUser: isUser,
                  ),
                if (message.streaming) ...[
                  const SizedBox(height: 8),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceMessageGrid extends StatelessWidget {
  const _VoiceMessageGrid({required this.audios});

  final List<AudioAttachment> audios;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final audio in audios) _VoiceMessageCard(audio: audio)],
    );
  }
}

class _VoiceMessageCard extends StatelessWidget {
  const _VoiceMessageCard({required this.audio, this.onPlay});

  final AudioAttachment audio;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final waveform = audio.waveform.isEmpty
        ? List<double>.generate(18, (index) => 0.22 + (index % 5) * 0.13)
        : audio.waveform.take(24).toList(growable: false);
    return Semantics(
      button: true,
      label: '播放语音 ${audio.durationLabel}',
      child: InkWell(
        onTap: onPlay ?? () => AudioInputService().play(audio.path),
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded, color: colorScheme.primary),
                const SizedBox(width: 6),
                SizedBox(
                  width: 118,
                  height: 30,
                  child: _WaveformBars(values: waveform),
                ),
                const SizedBox(width: 8),
                Text(
                  audio.durationLabel,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveformBars extends StatelessWidget {
  const _WaveformBars({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final value in values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.4),
              child: FractionallySizedBox(
                heightFactor: value.clamp(0.08, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SentImagePreviewGrid extends StatelessWidget {
  const _SentImagePreviewGrid({required this.imagePaths});

  final List<String> imagePaths;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var index = 0; index < imagePaths.length; index += 1)
          _SentImageThumbnail(
            imagePath: imagePaths[index],
            label: imagePaths.length == 1 ? '图片' : '图片 ${index + 1}',
            onTap: () => _showImagePreviewDialog(
              context,
              imagePaths: imagePaths,
              initialIndex: index,
            ),
            borderColor: colorScheme.outlineVariant,
          ),
      ],
    );
  }
}

class _SentImageThumbnail extends StatelessWidget {
  const _SentImageThumbnail({
    required this.imagePath,
    required this.label,
    required this.onTap,
    required this.borderColor,
  });

  final String imagePath;
  final String label;
  final VoidCallback onTap;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '打开$label预览',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 168,
          constraints: const BoxConstraints(maxWidth: 168),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 36),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.image_outlined,
                          color: Colors.white,
                          size: 15,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Positioned(
                right: 8,
                top: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(
                      Icons.fullscreen_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showImagePreviewDialog(
  BuildContext context, {
  required List<String> imagePaths,
  required int initialIndex,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (context) =>
        _ImagePreviewDialog(imagePaths: imagePaths, initialIndex: initialIndex),
  );
}

class _ImagePreviewDialog extends StatefulWidget {
  const _ImagePreviewDialog({
    required this.imagePaths,
    required this.initialIndex,
  });

  final List<String> imagePaths;
  final int initialIndex;

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.imagePaths.length;
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: count,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) => InteractiveViewer(
                minScale: 0.7,
                maxScale: 5,
                child: Center(
                  child: Image.file(
                    File(widget.imagePaths[index]),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                      size: 56,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.46),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    count == 1 ? '图片' : '图片 ${_index + 1} / $count',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 4,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: '关闭图片预览',
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkdownMessageText extends StatelessWidget {
  const _MarkdownMessageText({required this.text, required this.isUser});

  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = textTheme.bodyMedium ?? const TextStyle();
    final textColor = isUser
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final codeBackground = isUser
        ? colorScheme.primary.withValues(alpha: 0.12)
        : colorScheme.surface;

    return MarkdownBody(
      data: text,
      selectable: true,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: baseStyle.copyWith(color: textColor, height: 1.35),
        strong: baseStyle.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
        em: baseStyle.copyWith(color: textColor, fontStyle: FontStyle.italic),
        h1: textTheme.titleLarge?.copyWith(color: textColor),
        h2: textTheme.titleMedium?.copyWith(color: textColor),
        h3: textTheme.titleSmall?.copyWith(color: textColor),
        listBullet: baseStyle.copyWith(color: textColor, height: 1.35),
        blockquote: baseStyle.copyWith(
          color: textColor.withValues(alpha: 0.82),
        ),
        code: textTheme.bodyMedium?.copyWith(
          color: textColor,
          fontFamily: 'monospace',
          backgroundColor: codeBackground,
        ),
        codeblockDecoration: BoxDecoration(
          color: codeBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        codeblockPadding: const EdgeInsets.all(12),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.enabledModes,
    required this.attachedImages,
    required this.attachedAudios,
    required this.recording,
    required this.liveCallActive,
    required this.liveElapsedLabel,
    required this.liveMicLevel,
    required this.liveStatusText,
    required this.liveAssistantPreview,
    required this.running,
    required this.onToggleMode,
    required this.onRemoveImage,
    required this.onRemoveAudio,
    required this.onPlayAudio,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Set<_ComposerMode> enabledModes;
  final List<XFile> attachedImages;
  final List<AudioAttachment> attachedAudios;
  final bool recording;
  final bool liveCallActive;
  final String liveElapsedLabel;
  final double liveMicLevel;
  final String liveStatusText;
  final String liveAssistantPreview;
  final bool running;
  final ValueChanged<_ComposerMode> onToggleMode;
  final ValueChanged<XFile> onRemoveImage;
  final ValueChanged<AudioAttachment> onRemoveAudio;
  final ValueChanged<AudioAttachment> onPlayAudio;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (attachedImages.isNotEmpty) ...[
                  _AttachedImageStrip(
                    images: attachedImages,
                    onRemoveImage: onRemoveImage,
                  ),
                  const SizedBox(height: 8),
                ],
                if (attachedAudios.isNotEmpty) ...[
                  _AttachedAudioStrip(
                    audios: attachedAudios,
                    onRemoveAudio: onRemoveAudio,
                    onPlayAudio: onPlayAudio,
                  ),
                  const SizedBox(height: 8),
                ],
                if (liveCallActive) ...[
                  _LiveVoiceBanner(
                    elapsedLabel: liveElapsedLabel,
                    micLevel: liveMicLevel,
                    statusText: liveStatusText,
                    assistantPreview: liveAssistantPreview,
                  ),
                  const SizedBox(height: 8),
                ],
                if (recording) ...[
                  const _RecordingBanner(),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  enableSuggestions: true,
                  autocorrect: true,
                  onTap: () {
                    focusNode.requestFocus();
                    SystemChannels.textInput.invokeMethod<void>(
                      'TextInput.show',
                    );
                  },
                  decoration: const InputDecoration(
                    hintText: '发送消息，或添加图片/语音/Skills/Prompt Lab…',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                Row(
                  children: [
                    _ComposerIcon(
                      mode: _ComposerMode.image,
                      selected: enabledModes.contains(_ComposerMode.image),
                      onTap: () => onToggleMode(_ComposerMode.image),
                    ),
                    _ComposerIcon(
                      mode: _ComposerMode.voice,
                      selected: enabledModes.contains(_ComposerMode.voice),
                      recording: recording,
                      onTap: () => onToggleMode(_ComposerMode.voice),
                    ),
                    _ComposerIcon(
                      mode: _ComposerMode.skills,
                      selected: enabledModes.contains(_ComposerMode.skills),
                      onTap: () => onToggleMode(_ComposerMode.skills),
                    ),
                    _ComposerIcon(
                      mode: _ComposerMode.promptLab,
                      selected: enabledModes.contains(_ComposerMode.promptLab),
                      onTap: () => onToggleMode(_ComposerMode.promptLab),
                    ),
                    const Spacer(),
                    IconButton.filled(
                      onPressed: running ? onStop : onSend,
                      tooltip: running ? '停止生成' : '发送',
                      icon: Icon(
                        running ? Icons.stop_rounded : Icons.arrow_upward,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachedImageStrip extends StatelessWidget {
  const _AttachedImageStrip({
    required this.images,
    required this.onRemoveImage,
  });

  final List<XFile> images;
  final ValueChanged<XFile> onRemoveImage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final image = images[index];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  File(image.path),
                  width: 86,
                  height: 86,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: InkWell(
                  onTap: () => onRemoveImage(image),
                  borderRadius: BorderRadius.circular(14),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.scrim.withValues(alpha: 0.62),
                      shape: BoxShape.circle,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AttachedAudioStrip extends StatelessWidget {
  const _AttachedAudioStrip({
    required this.audios,
    required this.onRemoveAudio,
    required this.onPlayAudio,
  });

  final List<AudioAttachment> audios;
  final ValueChanged<AudioAttachment> onRemoveAudio;
  final ValueChanged<AudioAttachment> onPlayAudio;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: audios.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final audio = audios[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              _VoiceMessageCard(audio: audio, onPlay: () => onPlayAudio(audio)),
              Positioned(
                top: -5,
                right: -5,
                child: InkWell(
                  onTap: () => onRemoveAudio(audio),
                  borderRadius: BorderRadius.circular(14),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.scrim.withValues(alpha: 0.62),
                      shape: BoxShape.circle,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecordingBanner extends StatelessWidget {
  const _RecordingBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.fiber_manual_record, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '正在录音… 再点语音按钮停止',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveVoiceBanner extends StatelessWidget {
  const _LiveVoiceBanner({
    required this.elapsedLabel,
    required this.micLevel,
    required this.statusText,
    required this.assistantPreview,
  });

  final String elapsedLabel;
  final double micLevel;
  final String statusText;
  final String assistantPreview;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_in_talk_outlined, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText.isEmpty ? 'Live 语音通话进行中…' : statusText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                elapsedLabel,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (assistantPreview.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              assistantPreview,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.9),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: micLevel.clamp(0, 1),
              minHeight: 5,
              backgroundColor: colorScheme.onPrimaryContainer.withValues(
                alpha: 0.12,
              ),
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveCallOverlay extends StatelessWidget {
  const _LiveCallOverlay({
    required this.elapsedLabel,
    required this.micLevel,
    required this.statusText,
    required this.assistantPreview,
    required this.processing,
    required this.onStop,
  });

  final String elapsedLabel;
  final double micLevel;
  final String statusText;
  final String assistantPreview;
  final bool processing;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.headlineSmall;
    final bodyStyle = Theme.of(context).textTheme.bodyLarge;
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onStop,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('结束通话'),
                  ),
                  const Spacer(),
                  Text(
                    elapsedLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: processing
                      ? colorScheme.tertiaryContainer
                      : colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  processing
                      ? Icons.graphic_eq_rounded
                      : Icons.mic_none_rounded,
                  size: 54,
                  color: processing
                      ? colorScheme.onTertiaryContainer
                      : colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  width: 220,
                  child: LinearProgressIndicator(
                    value: micLevel.clamp(0, 1),
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      processing ? colorScheme.tertiary : colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '正在与 Gemma 持续语音对话',
                style: titleStyle?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                statusText.isEmpty ? '我在持续听你说话…' : statusText,
                style: bodyStyle?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      assistantPreview.trim().isEmpty
                          ? 'AI 的连续回复会显示在这里。你可以正常持续说话，不需要感知后台切段。'
                          : assistantPreview,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.call_end_rounded),
                label: const Text('挂断'),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                  minimumSize: const Size(double.infinity, 56),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerIcon extends StatelessWidget {
  const _ComposerIcon({
    required this.mode,
    required this.selected,
    required this.onTap,
    this.recording = false,
  });

  final _ComposerMode mode;
  final bool selected;
  final bool recording;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      isSelected: selected || recording,
      tooltip: recording ? '停止录音' : mode.label,
      onPressed: onTap,
      icon: Icon(recording ? Icons.stop_circle_outlined : mode.icon),
    );
  }
}

class _ModelStatusChip extends StatelessWidget {
  const _ModelStatusChip({required this.status});
  final ModelDownloadStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status.type) {
      ModelDownloadStatusType.succeeded => ('已下载', Colors.green),
      ModelDownloadStatusType.inProgress => ('下载中', Colors.blue),
      ModelDownloadStatusType.partiallyDownloaded => ('部分下载', Colors.orange),
      ModelDownloadStatusType.failed => (
        '失败',
        Theme.of(context).colorScheme.error,
      ),
      ModelDownloadStatusType.notDownloaded => ('未下载', Colors.grey),
    };
    return Chip(
      label: Text(label),
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}

enum _AudioAction { record, pickFile, liveCallToggle }

enum _ComposerMode {
  text('文字', Icons.chat_bubble_outline),
  image('图片', Icons.image_outlined),
  voice('语音', Icons.mic_none),
  skills('Skills', Icons.extension_outlined),
  promptLab('Prompt Lab', Icons.science_outlined);

  const _ComposerMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _ChatRole { user, assistant }

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.text,
    this.imagePaths = const [],
    this.audioAttachments = const [],
    this.streaming = false,
  });

  final _ChatRole role;
  final String text;
  final List<String> imagePaths;
  final List<AudioAttachment> audioAttachments;
  final bool streaming;

  _ChatMessage copyWith({
    String? text,
    List<String>? imagePaths,
    List<AudioAttachment>? audioAttachments,
    bool? streaming,
  }) {
    return _ChatMessage(
      role: role,
      text: text ?? this.text,
      imagePaths: imagePaths ?? this.imagePaths,
      audioAttachments: audioAttachments ?? this.audioAttachments,
      streaming: streaming ?? this.streaming,
    );
  }
}
