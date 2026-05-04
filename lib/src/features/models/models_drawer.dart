import 'package:flutter/material.dart';

import '../../core/model/gemma_model_config.dart';
import 'model_download_service.dart';

class ModelEntry {
  const ModelEntry({
    required this.config,
    required this.status,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
    required this.onRefresh,
    this.tag,
  });

  final GemmaModelConfig config;
  final ModelDownloadStatus status;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;
  final String? tag;
}

class ModelsDrawer extends StatelessWidget {
  const ModelsDrawer({super.key, required this.models});

  final List<ModelEntry> models;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('设置', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            Text('Models', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final entry in models)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ModelDownloadCard(entry: entry),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModelDownloadCard extends StatelessWidget {
  const _ModelDownloadCard({required this.entry});

  final ModelEntry entry;

  @override
  Widget build(BuildContext context) {
    final config = entry.config;
    final status = entry.status;
    final progress = status.clampedProgress;
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(1);
    final eta = _formatDuration(status.estimatedRemaining);
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
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (entry.tag != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      entry.tag!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(config.modelFile),
            const SizedBox(height: 8),
            Text('状态: ${_statusLabel(status.type)}'),
            Text('大小: ${_formatBytes(config.sizeInBytes)}'),
            if (status.localPath.isNotEmpty) Text('路径: ${status.localPath}'),
            if (status.type == ModelDownloadStatusType.inProgress ||
                status.type == ModelDownloadStatusType.partiallyDownloaded) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress == 0 ? null : progress),
              const SizedBox(height: 8),
              Text(
                '$percent% · ${_formatBytes(status.receivedBytes)} / ${_formatBytes(status.totalBytes)}'
                '${status.bytesPerSecond > 0 ? ' · ${_formatBytes(status.bytesPerSecond)}/s' : ''}'
                '${eta == null ? '' : ' · 预计剩余 $eta'}',
              ),
            ],
            if (status.type == ModelDownloadStatusType.failed) ...[
              const SizedBox(height: 8),
              Text(
                status.errorMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: status.type == ModelDownloadStatusType.inProgress
                      ? null
                      : entry.onDownload,
                  icon: const Icon(Icons.download),
                  label: Text(
                    status.type == ModelDownloadStatusType.partiallyDownloaded
                        ? '继续下载'
                        : '下载',
                  ),
                ),
                if (status.type == ModelDownloadStatusType.inProgress)
                  OutlinedButton.icon(
                    onPressed: entry.onCancel,
                    icon: const Icon(Icons.stop),
                    label: const Text('暂停'),
                  ),
                OutlinedButton.icon(
                  onPressed: entry.onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新'),
                ),
                if (status.type != ModelDownloadStatusType.notDownloaded)
                  TextButton.icon(
                    onPressed: entry.onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(ModelDownloadStatusType type) => switch (type) {
    ModelDownloadStatusType.notDownloaded => '未下载',
    ModelDownloadStatusType.partiallyDownloaded => '部分下载，可继续',
    ModelDownloadStatusType.inProgress => '下载中',
    ModelDownloadStatusType.succeeded => '已下载',
    ModelDownloadStatusType.failed => '下载失败',
  };

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 2)} ${units[unit]}';
  }

  String? _formatDuration(Duration? duration) {
    if (duration == null) return null;
    final totalMinutes = duration.inMinutes;
    if (totalMinutes < 1) return '<1 分钟';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '$minutes 分钟';
    if (minutes == 0) return '$hours 小时';
    return '$hours 小时 $minutes 分钟';
  }
}
