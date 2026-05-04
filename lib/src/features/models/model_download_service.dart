import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
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

  double get clampedProgress => progress.clamp(0.0, 1.0);

  Duration? get estimatedRemaining {
    if (type != ModelDownloadStatusType.inProgress ||
        totalBytes <= 0 ||
        receivedBytes <= 0 ||
        bytesPerSecond <= 0 ||
        receivedBytes >= totalBytes) {
      return null;
    }
    final seconds = ((totalBytes - receivedBytes) / bytesPerSecond).ceil();
    if (seconds <= 0) return null;
    return Duration(seconds: seconds);
  }

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

class ModelDownloadProgressSmoother {
  ModelDownloadProgressSmoother({
    this.minEmitInterval = const Duration(milliseconds: 800),
    this.speedSmoothing = 0.25,
  }) : assert(speedSmoothing > 0 && speedSmoothing <= 1);

  final Duration minEmitInterval;
  final double speedSmoothing;

  ModelDownloadStatus? _lastVisible;
  DateTime? _lastEmitAt;
  int? _smoothedBytesPerSecond;

  ModelDownloadStatus? filter(ModelDownloadStatus status, {DateTime? now}) {
    now ??= DateTime.now();
    if (status.type != ModelDownloadStatusType.inProgress) {
      _resetProgressWindow();
      _lastVisible = status;
      return status;
    }

    final smoothed = _smooth(status);
    final firstProgress =
        _lastVisible?.type != ModelDownloadStatusType.inProgress;
    final intervalElapsed =
        _lastEmitAt == null ||
        !now.difference(_lastEmitAt!).isNegative &&
            now.difference(_lastEmitAt!) >= minEmitInterval;
    final completedBoundary =
        smoothed.totalBytes > 0 &&
        smoothed.receivedBytes >= smoothed.totalBytes;

    if (firstProgress || intervalElapsed || completedBoundary) {
      _lastEmitAt = now;
      _lastVisible = smoothed;
      return smoothed;
    }
    return null;
  }

  ModelDownloadStatus _smooth(ModelDownloadStatus status) {
    final last = _lastVisible;
    var receivedBytes = status.receivedBytes;
    if (last != null &&
        last.type == ModelDownloadStatusType.inProgress &&
        last.totalBytes == status.totalBytes &&
        receivedBytes < last.receivedBytes) {
      receivedBytes = last.receivedBytes;
    }

    final inputBps = status.bytesPerSecond;
    if (inputBps > 0) {
      final previous = _smoothedBytesPerSecond;
      _smoothedBytesPerSecond = previous == null || previous <= 0
          ? inputBps
          : (previous * (1 - speedSmoothing) + inputBps * speedSmoothing)
                .round();
    }

    return status.copyWith(
      receivedBytes: receivedBytes,
      bytesPerSecond: _smoothedBytesPerSecond ?? inputBps,
    );
  }

  void _resetProgressWindow() {
    _lastEmitAt = null;
    _smoothedBytesPerSecond = null;
  }
}

class ModelDownloadController {
  ModelDownloadController({http.Client? client})
    : _fallback = _DartForegroundModelDownloader(client: client) {
    if (Platform.isAndroid || Platform.isIOS) {
      _nativeSubscription = _nativeEventChannel.receiveBroadcastStream().listen(
        (event) => _emit(_statusFromNativeEvent(event)),
        onError: (Object error) => _emit(
          ModelDownloadStatus(
            type: ModelDownloadStatusType.failed,
            errorMessage: error.toString(),
          ),
        ),
      );
    }
  }

  static const _nativeMethodChannel = MethodChannel(
    'com.example.gemma_local_app/model_download',
  );
  static const _nativeEventChannel = EventChannel(
    'com.example.gemma_local_app/model_download_events',
  );

  final _DartForegroundModelDownloader _fallback;
  final _statusController = StreamController<ModelDownloadStatus>.broadcast();
  final _progressSmoother = ModelDownloadProgressSmoother();
  StreamSubscription<dynamic>? _nativeSubscription;
  ModelDownloadStatus _status = const ModelDownloadStatus(
    type: ModelDownloadStatusType.notDownloaded,
  );

  Stream<ModelDownloadStatus> get statusStream => _statusController.stream;

  ModelDownloadStatus get status => _status;

  Future<String> get appFilesDir => _fallback.appFilesDir;

  Future<String> modelPath(GemmaModelConfig config) =>
      _fallback.modelPath(config);

  Future<String> tmpModelPath(GemmaModelConfig config) =>
      _fallback.tmpModelPath(config);

  Future<ModelDownloadStatus> refreshStatus(GemmaModelConfig config) async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final result = await _nativeMethodChannel
            .invokeMapMethod<String, Object?>(
              'refreshStatus',
              _nativeArgs(config),
            );
        final status = _statusFromNativeMap(result ?? const {});
        _emit(status);
        return status;
      } catch (error) {
        final fallbackStatus = await _fallback.refreshStatus(config);
        final status = fallbackStatus.copyWith(
          type: ModelDownloadStatusType.failed,
          errorMessage: '原生后台下载状态读取失败：$error',
        );
        _emit(status);
        return status;
      }
    }
    final status = await _fallback.refreshStatus(config);
    _emit(status);
    return status;
  }

  Future<void> download(GemmaModelConfig config) async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await _nativeMethodChannel.invokeMethod<void>(
          'download',
          _nativeArgs(config),
        );
      } catch (error) {
        _emit(
          ModelDownloadStatus(
            type: ModelDownloadStatusType.failed,
            totalBytes: config.sizeInBytes,
            errorMessage: '原生后台下载启动失败：$error',
          ),
        );
      }
      return;
    }
    await _fallback.download(config, _emit);
  }

  Future<void> delete(GemmaModelConfig config) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final result = await _nativeMethodChannel
          .invokeMapMethod<String, Object?>('delete', _nativeArgs(config));
      _emit(_statusFromNativeMap(result ?? const {}));
      return;
    }
    await _fallback.delete(config);
    _emit(_fallback.status);
  }

  void cancel() {
    if (Platform.isAndroid || Platform.isIOS) {
      _nativeMethodChannel.invokeMethod<void>(
        'cancel',
        _nativeArgs(gemma4E2bIt),
      );
      return;
    }
    _fallback.cancel();
  }

  void dispose() {
    _nativeSubscription?.cancel();
    _fallback.dispose();
    _statusController.close();
  }

  Map<String, Object?> _nativeArgs(GemmaModelConfig config) {
    return {
      'name': config.name,
      'url': config.huggingFaceDownloadUrl,
      'normalizedName': config.normalizedName,
      'version': config.commitHash,
      'fileName': config.modelFile,
      'totalBytes': config.sizeInBytes,
    };
  }

  ModelDownloadStatus _statusFromNativeEvent(dynamic event) {
    if (event is Map) return _statusFromNativeMap(event);
    return ModelDownloadStatus(
      type: ModelDownloadStatusType.failed,
      errorMessage: 'Invalid native download event: $event',
    );
  }

  ModelDownloadStatus _statusFromNativeMap(Map<dynamic, dynamic> map) {
    return ModelDownloadStatus(
      type: _statusTypeFromString(map['status']?.toString()),
      receivedBytes: _intFromNative(map['receivedBytes']),
      totalBytes: _intFromNative(map['totalBytes']),
      bytesPerSecond: _intFromNative(map['bytesPerSecond']),
      errorMessage: map['errorMessage']?.toString() ?? '',
      localPath: map['localPath']?.toString() ?? '',
    );
  }

  ModelDownloadStatusType _statusTypeFromString(String? value) =>
      switch (value) {
        'partiallyDownloaded' => ModelDownloadStatusType.partiallyDownloaded,
        'inProgress' => ModelDownloadStatusType.inProgress,
        'succeeded' => ModelDownloadStatusType.succeeded,
        'failed' => ModelDownloadStatusType.failed,
        _ => ModelDownloadStatusType.notDownloaded,
      };

  int _intFromNative(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _emit(ModelDownloadStatus status) {
    final visibleStatus = _progressSmoother.filter(status);
    if (visibleStatus == null) return;
    _status = visibleStatus;
    if (!_statusController.isClosed) {
      _statusController.add(visibleStatus);
    }
  }
}

class _DartForegroundModelDownloader {
  _DartForegroundModelDownloader({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  bool _cancelRequested = false;
  ModelDownloadStatus status = const ModelDownloadStatus(
    type: ModelDownloadStatusType.notDownloaded,
  );

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
      status = ModelDownloadStatus(
        type: ModelDownloadStatusType.succeeded,
        receivedBytes: size,
        totalBytes: config.sizeInBytes,
        localPath: path,
      );
    } else if (await tmpFile.exists()) {
      final size = await tmpFile.length();
      status = ModelDownloadStatus(
        type: ModelDownloadStatusType.partiallyDownloaded,
        receivedBytes: size,
        totalBytes: config.sizeInBytes,
        localPath: path,
      );
    } else {
      status = ModelDownloadStatus(
        type: ModelDownloadStatusType.notDownloaded,
        totalBytes: config.sizeInBytes,
        localPath: path,
      );
    }
    return status;
  }

  Future<void> download(
    GemmaModelConfig config,
    void Function(ModelDownloadStatus status) onStatus,
  ) async {
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

    void emit(ModelDownloadStatus next) {
      status = next;
      onStatus(next);
    }

    emit(
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
      if (downloadedBytes > 0 && response.statusCode == HttpStatus.ok) {
        await tmpFile.delete();
        downloadedBytes = 0;
        lastBytes = 0;
      }

      final writeMode = response.statusCode == HttpStatus.partialContent
          ? FileMode.append
          : FileMode.write;
      final sink = tmpFile.openWrite(mode: writeMode);
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
            emit(
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
      emit(
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
      emit(await refreshStatus(config));
    } catch (error) {
      emit(
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
    status = await refreshStatus(config);
  }

  void cancel() {
    _cancelRequested = true;
  }

  void dispose() {
    _client.close();
  }
}

class ModelDownloadCancelledException implements Exception {
  const ModelDownloadCancelledException();
}
