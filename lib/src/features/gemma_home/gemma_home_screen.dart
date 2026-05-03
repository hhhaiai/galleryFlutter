import 'dart:async';
import 'dart:io' show File;

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
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  StreamSubscription<ModelDownloadStatus>? _downloadSubscription;

  ModelDownloadStatus _downloadStatus = const ModelDownloadStatus(
    type: ModelDownloadStatusType.notDownloaded,
  );
  PromptTemplate _template = promptLabTemplates.first;
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
  bool _recording = false;
  bool _running = false;
  bool _stopRequested = false;

  @override
  void initState() {
    super.initState();
    _downloadSubscription = _downloadController.statusStream.listen((status) {
      if (mounted) setState(() => _downloadStatus = status);
    });
    _downloadController.refreshStatus(gemma4E2bIt).then((status) {
      if (mounted) setState(() => _downloadStatus = status);
    });
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
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

  Future<void> _send() async {
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
        ? (imagePaths.isNotEmpty ? '请描述这张图片。' : '请识别并总结这段语音内容。')
        : rawInput;
    final prompt = _enabledModes.contains(_ComposerMode.promptLab)
        ? _template.buildPrompt(promptInput)
        : promptInput;
    final userText = _buildUserMessageText(
      rawInput,
      imagePaths.length,
      audioAttachments.length,
    );
    _inputController.clear();
    setState(() {
      _attachedImages.clear();
      _attachedAudios.clear();
      if (imagePaths.isEmpty) _enabledModes.remove(_ComposerMode.image);
      if (audioPaths.isEmpty) _enabledModes.remove(_ComposerMode.voice);
    });

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

    if (!_downloadStatus.isDownloaded) {
      _appendAssistantText(
        '请先从左侧菜单进入「Models」下载 ${gemma4E2bIt.name}。下载完成后我会使用本地模型回答。',
        done: true,
      );
      return;
    }

    try {
      await _runtime.initialize(gemma4E2bIt);
      await for (final token in _runtime.generate(
        GemmaRequest(
          prompt: prompt,
          systemPrompt: _enabledModes.contains(_ComposerMode.skills)
              ? agentSkillsSystemPrompt
              : null,
          imagePaths: imagePaths,
          audioPaths: audioPaths,
          enabledSkillNames: _enabledModes.contains(_ComposerMode.skills)
              ? builtInSkills
                    .where((skill) => skill.selected)
                    .map((skill) => skill.name)
                    .toList()
              : const [],
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
    setState(() {
      final last = _messages.removeLast();
      _messages.add(
        last.copyWith(text: '${last.text}$token', streaming: !done),
      );
      if (done) _running = false;
    });
    _scrollToBottom();
  }

  void _stopGeneration() {
    if (!_running || _stopRequested) return;
    _stopRequested = true;
    _runtime.stop();
    _finishAssistantMessage(stopped: true);
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
    final badges = <String>[
      if (imageCount > 0) '图片 × $imageCount',
      if (audioCount > 0) '语音 × $audioCount',
      ..._enabledModes
          .where(
            (mode) =>
                mode != _ComposerMode.text &&
                mode != _ComposerMode.image &&
                mode != _ComposerMode.voice,
          )
          .map((mode) => mode.label),
    ].join(' · ');
    final text = rawInput.isEmpty
        ? (imageCount > 0 ? '请描述这张图片。' : '请识别并总结这段语音内容。')
        : rawInput;
    if (badges.isEmpty) return text;
    return '$text\n\n[$badges]';
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
              title: const Text('Live 语音通话探索'),
              subtitle: const Text('实时连续听写 + 本地模型文字回复，先记录方案后分阶段接入'),
              onTap: () => Navigator.pop(context, _AudioAction.liveCallInfo),
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
      case _AudioAction.liveCallInfo:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Live 语音通话会按“分段实时录音 → 音频理解 → 文字回复”方案继续实现。'),
          ),
        );
    }
  }

  Future<void> _pickAudioFile() async {
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
      body: Column(
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
            running: _running,
            onToggleMode: _toggleMode,
            onRemoveImage: _removeAttachedImage,
            onRemoveAudio: _removeAttachedAudio,
            onPlayAudio: (audio) => _audioInput.play(audio.path),
            onSend: _send,
            onStop: _stopGeneration,
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

enum _AudioAction { record, pickFile, liveCallInfo }

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
