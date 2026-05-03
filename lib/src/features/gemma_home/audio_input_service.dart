import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class AudioAttachment {
  const AudioAttachment({
    required this.path,
    required this.durationMs,
    this.waveform = const [],
  });

  final String path;
  final int durationMs;
  final List<double> waveform;

  String get durationLabel {
    final totalSeconds = (durationMs / 1000).round().clamp(1, 60 * 60);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes <= 0) return '$seconds"';
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static AudioAttachment fromMap(Map<dynamic, dynamic> map) {
    return AudioAttachment(
      path: map['path']?.toString() ?? '',
      durationMs: _intValue(map['durationMs']),
      waveform: _waveformValue(map['waveform']),
    );
  }

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static List<double> _waveformValue(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<num>()
        .map((item) => item.toDouble().clamp(0.04, 1.0))
        .toList(growable: false);
  }
}

class AudioInputService {
  static const _channel = MethodChannel(
    'com.example.gemma_local_app/audio_input',
  );

  Future<bool> get isSupported async => Platform.isAndroid || Platform.isIOS;

  Future<AudioAttachment?> pickAudioFile() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickAudioFile',
    );
    if (result == null) return null;
    return AudioAttachment.fromMap(result);
  }

  Future<void> startRecording() async {
    await _channel.invokeMethod<void>('startRecording');
  }

  Future<AudioAttachment?> stopRecording() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'stopRecording',
    );
    if (result == null) return null;
    return AudioAttachment.fromMap(result);
  }

  Future<void> cancelRecording() async {
    await _channel.invokeMethod<void>('cancelRecording');
  }

  Future<void> play(String path) async {
    await _channel.invokeMethod<void>('playAudio', {'path': path});
  }

  Future<void> stopPlayback() async {
    await _channel.invokeMethod<void>('stopPlayback');
  }
}
