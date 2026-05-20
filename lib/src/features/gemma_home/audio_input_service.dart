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

class AudioInputEvent {
  const AudioInputEvent({
    required this.type,
    this.state,
    this.reason,
    this.amplitude = 0,
    this.elapsedMs = 0,
  });

  final String type;
  final String? state;
  final String? reason;
  final double amplitude;
  final int elapsedMs;

  static AudioInputEvent fromMap(Map<dynamic, dynamic> map) {
    return AudioInputEvent(
      type: map['type']?.toString() ?? '',
      state: map['state']?.toString(),
      reason: map['reason']?.toString(),
      amplitude: map['amplitude'] is num
          ? (map['amplitude'] as num).toDouble()
          : 0,
      elapsedMs: map['elapsedMs'] is num
          ? (map['elapsedMs'] as num).toInt()
          : 0,
    );
  }
}

class AudioInputService {
  static const _channel = MethodChannel(
    'com.example.gemma_local_app/audio_input',
  );
  static const _eventChannel = EventChannel(
    'com.example.gemma_local_app/audio_input_events',
  );

  Future<bool> get isSupported async => Platform.isAndroid || Platform.isIOS;

  Stream<AudioInputEvent> get events {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const Stream<AudioInputEvent>.empty();
    }
    return _eventChannel
        .receiveBroadcastStream()
        .map((event) {
          if (event is Map<dynamic, dynamic>) {
            return AudioInputEvent.fromMap(event);
          }
          return const AudioInputEvent(type: '');
        })
        .where((event) => event.type.isNotEmpty);
  }

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
