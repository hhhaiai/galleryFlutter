import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'skill.dart';
import 'skill_repository.dart';

Future<void> showSkillsHubSheet({
  required BuildContext context,
  required SkillRepository repository,
  required List<GemmaSkill> onlineSkills,
  required Set<String> enabledSkillNames,
  required bool skillsModeEnabled,
  required ValueChanged<bool> onSkillsModeChanged,
  required ValueChanged<List<GemmaSkill>> onOnlineSkillsChanged,
  required ValueChanged<Set<String>> onEnabledSkillNamesChanged,
  required ValueChanged<String> onMessage,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _SkillsHubSheet(
      repository: repository,
      onlineSkills: onlineSkills,
      enabledSkillNames: enabledSkillNames,
      skillsModeEnabled: skillsModeEnabled,
      onSkillsModeChanged: onSkillsModeChanged,
      onOnlineSkillsChanged: onOnlineSkillsChanged,
      onEnabledSkillNamesChanged: onEnabledSkillNamesChanged,
      onMessage: onMessage,
    ),
  );
}

class _SkillsHubSheet extends StatefulWidget {
  const _SkillsHubSheet({
    required this.repository,
    required this.onlineSkills,
    required this.enabledSkillNames,
    required this.skillsModeEnabled,
    required this.onSkillsModeChanged,
    required this.onOnlineSkillsChanged,
    required this.onEnabledSkillNamesChanged,
    required this.onMessage,
  });

  final SkillRepository repository;
  final List<GemmaSkill> onlineSkills;
  final Set<String> enabledSkillNames;
  final bool skillsModeEnabled;
  final ValueChanged<bool> onSkillsModeChanged;
  final ValueChanged<List<GemmaSkill>> onOnlineSkillsChanged;
  final ValueChanged<Set<String>> onEnabledSkillNamesChanged;
  final ValueChanged<String> onMessage;

  @override
  State<_SkillsHubSheet> createState() => _SkillsHubSheetState();
}

class _SkillsHubSheetState extends State<_SkillsHubSheet> {
  final _importController = TextEditingController();
  final _hubSearchController = TextEditingController();
  late List<GemmaSkill> _onlineSkills;
  late Set<String> _enabledSkillNames;
  late bool _skillsModeEnabled;
  bool _importing = false;
  bool _hubSearching = false;
  SkillHubSearchResult? _hubSearchResult;
  String? _hubSearchError;
  final Set<String> _importingHubSlugs = <String>{};

  List<GemmaSkill> get _allSkills => [...builtInSkills, ..._onlineSkills];

  @override
  void initState() {
    super.initState();
    _onlineSkills = List<GemmaSkill>.of(widget.onlineSkills);
    _enabledSkillNames = Set<String>.of(widget.enabledSkillNames);
    _skillsModeEnabled = widget.skillsModeEnabled;
    unawaited(_searchSkillHub());
  }

  @override
  void dispose() {
    _importController.dispose();
    _hubSearchController.dispose();
    super.dispose();
  }

  void _saveAndEnableSkill(GemmaSkill skill, List<GemmaSkill> saved) {
    setState(() {
      _onlineSkills = List<GemmaSkill>.of(saved);
      _enabledSkillNames.add(skill.name);
      _skillsModeEnabled = true;
      _importController.clear();
    });
    widget.onOnlineSkillsChanged(saved);
    widget.onEnabledSkillNamesChanged(Set<String>.of(_enabledSkillNames));
    widget.onSkillsModeChanged(true);
  }

  Future<void> _importSkill() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final skill = await widget.repository.importOnlineSkill(
        _importController.text,
      );
      final saved = await widget.repository.saveOnlineSkill(skill);
      if (!mounted) return;
      _saveAndEnableSkill(skill, saved);
      widget.onMessage('已导入线上 Skill：${skill.name}');
    } on SkillImportException catch (error) {
      widget.onMessage(error.message);
    } catch (error) {
      widget.onMessage('导入线上 Skill 失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _searchSkillHub() async {
    if (_hubSearching) return;
    setState(() {
      _hubSearching = true;
      _hubSearchError = null;
    });
    try {
      final result = await widget.repository.searchSkillHub(
        keyword: _hubSearchController.text,
      );
      if (!mounted) return;
      setState(() => _hubSearchResult = result);
    } on SkillImportException catch (error) {
      if (!mounted) return;
      setState(() => _hubSearchError = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _hubSearchError = 'SkillHub 搜索失败：$error');
    } finally {
      if (mounted) setState(() => _hubSearching = false);
    }
  }

  Future<void> _importSkillHubSkill(SkillHubSkillSummary summary) async {
    if (_importingHubSlugs.contains(summary.slug)) return;
    setState(() => _importingHubSlugs.add(summary.slug));
    try {
      final skill = await widget.repository.importSkillHubSkill(summary.slug);
      final saved = await widget.repository.saveOnlineSkill(skill);
      if (!mounted) return;
      _saveAndEnableSkill(skill, saved);
      widget.onMessage('已从 SkillHub 导入：${skill.name}');
    } on SkillImportException catch (error) {
      widget.onMessage(error.message);
    } catch (error) {
      widget.onMessage('导入 SkillHub skill 失败：$error');
    } finally {
      if (mounted) {
        setState(() => _importingHubSlugs.remove(summary.slug));
      }
    }
  }

  Future<void> _deleteOnlineSkill(GemmaSkill skill) async {
    final saved = await widget.repository.deleteOnlineSkill(skill.name);
    if (!mounted) return;
    setState(() {
      _onlineSkills = List<GemmaSkill>.of(saved);
      _enabledSkillNames.remove(skill.name);
    });
    widget.onOnlineSkillsChanged(saved);
    widget.onEnabledSkillNamesChanged(Set<String>.of(_enabledSkillNames));
  }

  void _setSkillsMode(bool value) {
    setState(() => _skillsModeEnabled = value);
    widget.onSkillsModeChanged(value);
  }

  void _setSkillEnabled(GemmaSkill skill, bool enabled) {
    setState(() {
      if (enabled) {
        _enabledSkillNames.add(skill.name);
        _skillsModeEnabled = true;
      } else {
        _enabledSkillNames.remove(skill.name);
      }
    });
    if (enabled) widget.onSkillsModeChanged(true);
    widget.onEnabledSkillNamesChanged(Set<String>.of(_enabledSkillNames));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.86,
          minChildSize: 0.52,
          maxChildSize: 0.95,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            children: [
              Row(
                children: [
                  const Icon(Icons.extension_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Skills Hub',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Switch(value: _skillsModeEnabled, onChanged: _setSkillsMode),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '支持从线上 SKILL.md / GitHub raw / 指向 SKILL.md 的页面导入。'
                '当前 Gemma 仍是核心执行基础；JS/WebView 工具桥接尚未完成时会明确返回待桥接，不伪装执行。',
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.public_outlined),
                title: const Text('SkillHub.cn 线上社区'),
                subtitle: const Text(SkillRepository.skillHubHomeUrl),
                trailing: TextButton(
                  onPressed: () {
                    Clipboard.setData(
                      const ClipboardData(
                        text: SkillRepository.skillHubHomeUrl,
                      ),
                    );
                    widget.onMessage('已复制 SkillHub.cn 链接。');
                  },
                  child: const Text('复制链接'),
                ),
              ),
              ..._buildSkillHubDirectory(context),
              const SizedBox(height: 8),
              TextField(
                controller: _importController,
                decoration: InputDecoration(
                  labelText: '导入线上 Skill URL',
                  hintText: 'https://.../SKILL.md 或 GitHub blob/raw 链接',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _importing ? null : _importSkill,
                icon: _importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined),
                label: Text(_importing ? '导入中…' : '导入线上 Skill'),
              ),
              const SizedBox(height: 18),
              Text(
                '已启用 ${_enabledSkillNames.length} / ${_allSkills.length}',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final skill in _allSkills)
                CheckboxListTile(
                  value: _enabledSkillNames.contains(skill.name),
                  onChanged: (value) => _setSkillEnabled(skill, value == true),
                  title: Text(skill.name),
                  subtitle: Text(
                    [
                      skill.description,
                      if (skill.online && skill.sourceUrl != null)
                        '来源：${skill.sourceUrl}',
                    ].join('\n'),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  secondary: skill.online
                      ? IconButton(
                          tooltip: '删除线上 Skill',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => unawaited(_deleteOnlineSkill(skill)),
                        )
                      : const Icon(Icons.inventory_2_outlined),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSkillHubDirectory(BuildContext context) {
    final result = _hubSearchResult;
    final textTheme = Theme.of(context).textTheme;
    return [
      Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.travel_explore_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '浏览 SkillHub 公开目录',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '只导入远端 SKILL.md 到本地 Gemma 上下文；不会下载或执行远端 scripts/assets。'
                '需要 API key 的 skill 会保留提示，当前不自动索取或保存密钥。',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hubSearchController,
                      decoration: InputDecoration(
                        labelText: '搜索 SkillHub',
                        hintText: 'github / 文档 / 图片 / 数据分析…',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => unawaited(_searchSkillHub()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _hubSearching
                        ? null
                        : () => unawaited(_searchSkillHub()),
                    child: Text(_hubSearching ? '搜索中' : '搜索'),
                  ),
                ],
              ),
              if (_hubSearching) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
              if (_hubSearchError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _hubSearchError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (result != null) ...[
                const SizedBox(height: 12),
                Text(
                  result.keyword.isEmpty
                      ? '热门目录：${result.total} 个公开 skills'
                      : '“${result.keyword}” 搜索结果：${result.total} 个',
                  style: textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                for (final summary in result.skills.take(8))
                  _SkillHubSummaryTile(
                    summary: summary,
                    importing: _importingHubSlugs.contains(summary.slug),
                    alreadyImported: _onlineSkills.any(
                      (skill) =>
                          skill.name == summary.slug ||
                          (skill.sourceUrl?.contains('/${summary.slug}/file') ??
                              false),
                    ),
                    onImport: () => unawaited(_importSkillHubSkill(summary)),
                  ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }
}

class _SkillHubSummaryTile extends StatelessWidget {
  const _SkillHubSummaryTile({
    required this.summary,
    required this.importing,
    required this.alreadyImported,
    required this.onImport,
  });

  final SkillHubSkillSummary summary;
  final bool importing;
  final bool alreadyImported;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final metadata = [
      if (summary.ownerName.isNotEmpty) '@${summary.ownerName}',
      if (summary.category.isNotEmpty) summary.category,
      if (summary.version.isNotEmpty) 'v${summary.version}',
      '${_compactCount(summary.downloads)} downloads',
      '${_compactCount(summary.stars)} stars',
      if (summary.requiresApiKey) '需要 API key',
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.extension_outlined),
      title: Text(summary.name),
      subtitle: Text(
        [
          if (summary.description.isNotEmpty) summary.description,
          metadata,
          'slug: ${summary.slug}',
        ].join('\n'),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: TextButton(
        onPressed: importing || alreadyImported ? null : onImport,
        child: Text(
          importing
              ? '导入中'
              : alreadyImported
              ? '已导入'
              : '导入',
        ),
      ),
    );
  }
}

String _compactCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}
