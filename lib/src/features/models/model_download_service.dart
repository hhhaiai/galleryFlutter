import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/model/gemma_model_config.dart';

const galleryTmpFileExt = 'gallerytmp';

enum ModelDownloadStatusType {
  notDownloaded,
  partiallyDownloaded,
  inProgress,
  succeeded,
  failed,
}

class ModelDownloadStatus {
  const ModelDownloadStatus({
    required this.type,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.bytesPerSecond = 0,
    this.errorMessage = '',
    this.localPath = '',
  });

  final ModelDownloadStatusType type;
  final int receivedBytes;
  final int totalBytes;
  final int bytesPerSecond;
  final String errorMessage;
  final String localPath;

  double get progress => totalBytes <= 0 ? 0 : receivedBytes / totalBytes;

  bool get isDownloaded => type == ModelDownloadStatusType.succeeded;

  ModelDownloadStatus copyWith({
    ModelDownloadStatusType? type,
    int? receivedBytes,
    int? totalBytes,
    int? bytesPerSecond,
    String? errorMessage,
    String? localPath,
  }) {
    return ModelDownloadStatus(
      type: type ?? this.type,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      errorMessage: errorMessage ?? this.errorMessage,
      localPath: localPath ?? this.localPath,
    );
  }
}

class ModelDownloadController {
  ModelDownloadController({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  final _statusController = StreamController<ModelDownloadStatus>.broadcast();
  bool _cancelRequested = false;
  ModelDownloadStatus _status = const ModelDownloadStatus(
    type: ModelDownloadStatusType.notDownloaded,
  );

  Stream<ModelDownloadStatus> get statusStream => _statusController.stream;

  ModelDownloadStatus get status => _status;

  Future<String> get appFilesDir async =>
      (await getApplicationSupportDirectory()).path;

  Future<String> modelPath(GemmaModelConfig config) async =>
      config.localModelPath(await appFilesDir);

  Future<String> tmpModelPath(GemmaModelConfig config) async =>
      '${await modelPath(config)}.$galleryTmpFileExt';

  Future<ModelDownloadStatus> refreshStatus(GemmaModelConfig config) async {
    final path = await modelPath(config);
    final tmpPath = await tmpModelPath(config);
    final file = File(path);
    final tmpFile = File(tmpPath);

    if (await file.exists()) {
      final size = await file.length();
      _emit(
        ModelDownloadStatus(
          type: ModelDownloadStatusType.succeeded,
          receivedBytes: size,
          totalBytes: config.sizeInBytes,
          localPath: path,
        ),
      );
    } else if (await tmpFile.exists()) {
      final size = await tmpFile.length();
      _emit(
        ModelDownloadStatus(
          type: ModelDownloadStatusType.partiallyDownloaded,
          receivedBytes: size,
          totalBytes: config.sizeInBytes,
          localPath: path,
        ),
      );
    } else {
      _emit(
        ModelDownloadStatus(
          type: ModelDownloadStatusType.notDownloaded,
          totalBytes: config.sizeInBytes,
          localPath: path,
        ),
      );
    }
    return _status;
  }

  Future<void> download(GemmaModelConfig config) async {
    _cancelRequested = false;
    final finalPath = await modelPath(config);
    final tmpPath = await tmpModelPath(config);
    final finalFile = File(finalPath);
    final tmpFile = File(tmpPath);
    await finalFile.parent.create(recursive: true);

    if (await finalFile.exists()) {
      await finalFile.delete();
    }

    var downloadedBytes = 0;
    if (await tmpFile.exists()) {
      downloadedBytes = await tmpFile.length();
    }

    final request = http.Request(
      'GET',
      Uri.parse(config.huggingFaceDownloadUrl),
    );
    if (downloadedBytes > 0) {
      request.headers['Range'] = 'bytes=$downloadedBytes-';
      request.headers['Accept-Encoding'] = 'identity';
    }

    final stopwatch = Stopwatch()..start();
    var lastTick = DateTime.now();
    var lastBytes = downloadedBytes;

    _emit(
      ModelDownloadStatus(
        type: ModelDownloadStatusType.inProgress,
        receivedBytes: downloadedBytes,
        totalBytes: config.sizeInBytes,
        localPath: finalPath,
      ),
    );

    try {
      final response = await _client.send(request);
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException('HTTP error code: ${response.statusCode}');
      }

      final sink = tmpFile.openWrite(mode: FileMode.append);
      try {
        await for (final chunk in response.stream) {
          if (_cancelRequested) {
            throw const ModelDownloadCancelledException();
          }
          sink.add(chunk);
          downloadedBytes += chunk.length;

          final now = DateTime.now();
          final elapsedMs = now.difference(lastTick).inMilliseconds;
          if (elapsedMs >= 200) {
            final delta = downloadedBytes - lastBytes;
            final bytesPerSecond = elapsedMs <= 0
                ? 0
                : (delta * 1000 / elapsedMs).round();
            lastTick = now;
            lastBytes = downloadedBytes;
            _emit(
              ModelDownloadStatus(
                type: ModelDownloadStatusType.inProgress,
                receivedBytes: downloadedBytes,
                totalBytes: config.sizeInBytes,
                bytesPerSecond: bytesPerSecond,
                localPath: finalPath,
              ),
            );
          }
        }
      } finally {
        await sink.close();
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tmpFile.rename(finalPath);
      stopwatch.stop();
      _emit(
        ModelDownloadStatus(
          type: ModelDownloadStatusType.succeeded,
          receivedBytes: downloadedBytes,
          totalBytes: config.sizeInBytes,
          bytesPerSecond: stopwatch.elapsedMilliseconds <= 0
              ? 0
              : (downloadedBytes * 1000 / stopwatch.elapsedMilliseconds)
                    .round(),
          localPath: finalPath,
        ),
      );
    } on ModelDownloadCancelledException {
      await refreshStatus(config);
    } catch (error) {
      _emit(
        ModelDownloadStatus(
          type: ModelDownloadStatusType.failed,
          receivedBytes: downloadedBytes,
          totalBytes: config.sizeInBytes,
          errorMessage: error.toString(),
          localPath: finalPath,
        ),
      );
    }
  }

  Future<void> delete(GemmaModelConfig config) async {
    _cancelRequested = true;
    final dir = Directory('${await appFilesDir}/${config.normalizedName}');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await refreshStatus(config);
  }

  void cancel() {
    _cancelRequested = true;
  }

  void dispose() {
    _client.close();
    _statusController.close();
  }

  void _emit(ModelDownloadStatus status) {
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }
}

class ModelDownloadCancelledException implements Exception {
  const ModelDownloadCancelledException();
}
