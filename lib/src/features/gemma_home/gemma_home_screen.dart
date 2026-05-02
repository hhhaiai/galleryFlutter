import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

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
  final _inputController = TextEditingController();
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
    if (rawInput.isEmpty || _running) return;
    _stopRequested = false;

    final prompt = _enabledModes.contains(_ComposerMode.promptLab)
        ? _template.buildPrompt(rawInput)
        : rawInput;
    final userText = _buildUserMessageText(rawInput);
    _inputController.clear();

    setState(() {
      _messages.add(_ChatMessage(role: _ChatRole.user, text: userText));
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
          imagePaths: _enabledModes.contains(_ComposerMode.image)
              ? const ['pending-image-picker']
              : const [],
          audioPaths: _enabledModes.contains(_ComposerMode.voice)
              ? const ['pending-audio-recorder']
              : const [],
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

  String _buildUserMessageText(String rawInput) {
    final badges = _enabledModes
        .where((mode) => mode != _ComposerMode.text)
        .map((mode) => mode.label)
        .join(' · ');
    if (badges.isEmpty) return rawInput;
    return '$rawInput\n\n[$badges]';
  }

  void _toggleMode(_ComposerMode mode) {
    if (mode == _ComposerMode.text) return;
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
            enabledModes: _enabledModes,
            running: _running,
            onToggleMode: _toggleMode,
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
    required this.enabledModes,
    required this.running,
    required this.onToggleMode,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final Set<_ComposerMode> enabledModes;
  final bool running;
  final ValueChanged<_ComposerMode> onToggleMode;
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
                TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
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

class _ComposerIcon extends StatelessWidget {
  const _ComposerIcon({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final _ComposerMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      isSelected: selected,
      tooltip: mode.label,
      onPressed: onTap,
      icon: Icon(mode.icon),
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
    this.streaming = false,
  });

  final _ChatRole role;
  final String text;
  final bool streaming;

  _ChatMessage copyWith({String? text, bool? streaming}) {
    return _ChatMessage(
      role: role,
      text: text ?? this.text,
      streaming: streaming ?? this.streaming,
    );
  }
}
