import 'dart:async';

import 'package:flutter/material.dart';

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
  final _controller = TextEditingController();
  StreamSubscription<ModelDownloadStatus>? _downloadSubscription;
  GemmaTaskId _task = GemmaTaskId.chat;
  PromptTemplate _template = promptLabTemplates.first;
  ModelDownloadStatus _downloadStatus = const ModelDownloadStatus(
    type: ModelDownloadStatusType.notDownloaded,
  );
  String _output = '';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _downloadSubscription = _downloadController.statusStream.listen((status) {
      if (mounted) setState(() => _downloadStatus = status);
    });
    _downloadController.refreshStatus(gemma4E2bIt).then((status) async {
      if (mounted) setState(() => _downloadStatus = status);
      if (status.isDownloaded) {
        await _runtime.initialize(gemma4E2bIt);
      }
    });
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _controller.dispose();
    _downloadController.dispose();
    _runtime.dispose();
    super.dispose();
  }

  Future<void> _downloadModel() async {
    await _downloadController.download(gemma4E2bIt);
    if (_downloadController.status.isDownloaded) {
      await _runtime.initialize(gemma4E2bIt);
    }
  }

  Future<void> _send() async {
    final rawInput = _controller.text.trim();
    if (rawInput.isEmpty || _running) return;
    if (!_downloadStatus.isDownloaded) {
      setState(() {
        _output = '请先从左侧设置 > Models 下载 ${gemma4E2bIt.name}。';
      });
      return;
    }
    final prompt = _task == GemmaTaskId.promptLab
        ? _template.buildPrompt(rawInput)
        : rawInput;
    setState(() {
      _running = true;
      _output = '';
    });
    await for (final token in _runtime.generate(
      GemmaRequest(
        prompt: prompt,
        systemPrompt: _task == GemmaTaskId.agentSkills
            ? agentSkillsSystemPrompt
            : null,
        enabledSkillNames: _task == GemmaTaskId.agentSkills
            ? builtInSkills
                  .where((skill) => skill.selected)
                  .map((skill) => skill.name)
                  .toList()
            : const [],
      ),
    )) {
      if (!mounted) return;
      setState(() => _output += token);
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Gemma Local')),
      drawer: ModelsDrawer(
        status: _downloadStatus,
        onDownload: _downloadModel,
        onCancel: _downloadController.cancel,
        onDelete: () => _downloadController.delete(gemma4E2bIt),
        onRefresh: () => _downloadController.refreshStatus(gemma4E2bIt),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ModelCard(config: gemma4E2bIt, status: _downloadStatus),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final task in gemma4E2bIt.taskIds)
                  ChoiceChip(
                    label: Text(task.label),
                    selected: _task == task,
                    onSelected: (_) => setState(() => _task = task),
                  ),
              ],
            ),
            if (_task == GemmaTaskId.promptLab) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<PromptTemplate>(
                initialValue: _template,
                decoration: const InputDecoration(labelText: 'Prompt Lab 模板'),
                items: [
                  for (final template in promptLabTemplates)
                    DropdownMenuItem(
                      value: template,
                      child: Text(template.label),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _template = value ?? _template),
              ),
            ],
            if (_task == GemmaTaskId.agentSkills) ...[
              const SizedBox(height: 12),
              Text('内置 Skills', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final skill in builtInSkills)
                    Chip(label: Text(skill.name)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: _inputLabel,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _running ? null : _send,
              icon: _running
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_running ? '运行中' : '发送到本地 Gemma'),
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(_output.isEmpty ? '输出会显示在这里。' : _output),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _inputLabel => switch (_task) {
    GemmaTaskId.chat => '输入对话内容',
    GemmaTaskId.promptLab => '输入 Prompt Lab 内容',
    GemmaTaskId.agentSkills => '输入需要 Skills 完成的任务',
    GemmaTaskId.askImage => '输入图片问题（原生接入后附加图片）',
    GemmaTaskId.askAudio => '输入声音问题（原生接入后附加音频）',
  };
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.config, required this.status});
  final GemmaModelConfig config;
  final ModelDownloadStatus status;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    config.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 8),
            Text(config.description),
            const SizedBox(height: 8),
            Text('文件: ${config.modelFile}'),
            Text(
              '大小: ${(config.sizeInBytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB',
            ),
            Text('内存要求: ${config.minDeviceMemoryInGb} GB+'),
            Text(
              '上下文: ${config.maxContextLength}, 输出: ${config.maxTokens} tokens',
            ),
            if (!status.isDownloaded) ...[
              const SizedBox(height: 8),
              const Text('请从左侧设置 > Models 下载模型后再使用。'),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
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
    );
  }
}
