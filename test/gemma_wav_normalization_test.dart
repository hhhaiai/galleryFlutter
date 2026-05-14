import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_local_app/src/core/runtime/platform_gemma_runtime.dart';

void main() {
  test('normalizes padded iOS WAV into clean 16k mono PCM WAV', () {
    final pcm = Uint8List.fromList(List<int>.generate(320, (i) => i & 0xff));
    final padded = _wavWithPaddingChunk(pcm);

    final normalized =
        MethodChannelGemmaRuntime.normalizeGemmaWavBytesForLiteRt(padded);

    expect(String.fromCharCodes(normalized.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(normalized.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(normalized.sublist(12, 16)), 'fmt ');
    expect(String.fromCharCodes(normalized.sublist(36, 40)), 'data');
    expect(_u32(normalized, 4), 36 + pcm.length);
    expect(_u16(normalized, 20), 1); // PCM
    expect(_u16(normalized, 22), 1); // mono
    expect(_u32(normalized, 24), 16000);
    expect(_u16(normalized, 34), 16);
    expect(_u32(normalized, 40), pcm.length);
    expect(normalized.length, 44 + pcm.length);
    expect(normalized.sublist(44), pcm);
  });

  test('builds iOS path-based multimodal JSON without base64 blobs', () {
    final json = MethodChannelGemmaRuntime.buildIosPathMessageJsonForTesting(
      text: 'Transcribe this audio.',
      audioPath: '/tmp/sample.wav',
      imagePath: '/tmp/sample.png',
    );

    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['role'], 'user');
    final content = decoded['content'] as List<dynamic>;
    expect(content, hasLength(3));
    expect(content[0], {'type': 'text', 'text': 'Transcribe this audio.'});
    expect(content[1], {'type': 'image', 'path': '/tmp/sample.png'});
    expect(content[2], {'type': 'audio', 'path': '/tmp/sample.wav'});
    expect(json, isNot(contains('blob')));
  });
}

Uint8List _wavWithPaddingChunk(Uint8List pcm) {
  final padding = Uint8List(12);
  final totalLength = 12 + 24 + 8 + padding.length + 8 + pcm.length;
  final bytes = Uint8List(totalLength);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, totalLength - 8, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'FLLR'.codeUnits);
  data.setUint32(40, padding.length, Endian.little);
  var offset = 44 + padding.length;
  bytes.setRange(offset, offset + 4, 'data'.codeUnits);
  data.setUint32(offset + 4, pcm.length, Endian.little);
  offset += 8;
  bytes.setRange(offset, offset + pcm.length, pcm);
  return bytes;
}

int _u16(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint16(offset, Endian.little);

int _u32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset, Endian.little);
