import 'package:flutter/material.dart';

import '../../core/model/gemma_model_config.dart';
import 'model_download_service.dart';

class ModelsDrawer extends StatelessWidget {
  const ModelsDrawer({
    super.key,
    required this.status,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
    required this.onRefresh,
  });

  final ModelDownloadStatus status;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;

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
            _ModelDownloadCard(
              status: status,
              onDownload: onDownload,
              onCancel: onCancel,
              onDelete: onDelete,
              onRefresh: onRefresh,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelDownloadCard extends StatelessWidget {
  const _ModelDownloadCard({
    required this.status,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
    required this.onRefresh,
  });

  final ModelDownloadStatus status;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final config = gemma4E2bIt;
    final progress = status.progress.clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(config.name, style: Theme.of(context).textTheme.titleMedium),
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
                '${_formatBytes(status.receivedBytes)} / ${_formatBytes(status.totalBytes)}'
                '${status.bytesPerSecond > 0 ? ' · ${_formatBytes(status.bytesPerSecond)}/s' : ''}',
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
                      : onDownload,
                  icon: const Icon(Icons.download),
                  label: Text(
                    status.type == ModelDownloadStatusType.partiallyDownloaded
                        ? '继续下载'
                        : '下载',
                  ),
                ),
                if (status.type == ModelDownloadStatusType.inProgress)
                  OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.stop),
                    label: const Text('暂停'),
                  ),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新'),
                ),
                if (status.type != ModelDownloadStatusType.notDownloaded)
                  TextButton.icon(
                    onPressed: onDelete,
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
}
