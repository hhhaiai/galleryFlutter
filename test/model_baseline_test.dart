import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_local_app/src/core/model/gemma_model_config.dart';
import 'package:gemma_local_app/src/core/runtime/platform_gemma_runtime.dart';

void main() {
  test('mobile product baseline exposes only Gemma-4-E2B-it', () {
    expect(availableModels, hasLength(1));
    expect(availableModels.single, same(gemma4E2bIt));
    expect(gemma4E2bIt.name, 'Gemma-4-E2B-it');
    expect(gemma4E2bIt.sizeInBytes, 2538766336);
    expect(gemma4E2bIt.supportImage, isTrue);
    expect(gemma4E2bIt.supportAudio, isTrue);
    expect(gemma4E2bIt.taskIds, contains(GemmaTaskId.chat));
    expect(gemma4E2bIt.taskIds, contains(GemmaTaskId.askImage));
    expect(gemma4E2bIt.taskIds, contains(GemmaTaskId.askAudio));
  });

  test(
    'runtime session windows honor the official 4000-token model budget',
    () {
      expect(
        MethodChannelGemmaRuntime.runtimeSessionTokenLimitForTesting(
          gemma4E2bIt,
        ),
        4000,
      );
      expect(
        MethodChannelGemmaRuntime.runtimeSessionTokenLimitForTesting(
          gemma4E2bIt,
          supportImage: true,
        ),
        4000,
      );
      expect(
        MethodChannelGemmaRuntime.runtimeSessionTokenLimitForTesting(
          gemma4E2bIt,
          supportAudio: true,
        ),
        4000,
      );
      expect(
        MethodChannelGemmaRuntime.runtimeSessionTokenLimitForTesting(
          gemma4E2bIt,
          supportImage: true,
          isAppleMobile: true,
          totalMemoryBytes: 4 * 1024 * 1024 * 1024,
        ),
        2048,
      );
      expect(
        MethodChannelGemmaRuntime.runtimeSessionTokenLimitForTesting(
          gemma4E2bIt,
          supportAudio: true,
          isAppleMobile: true,
          totalMemoryBytes: 6 * 1024 * 1024 * 1024,
        ),
        3072,
      );
    },
  );

  test('runtime profile scales image input by device memory', () {
    final iphone13 = DeviceRuntimeProfile.forMemoryBytes(
      4 * 1024 * 1024 * 1024,
      isAppleMobile: true,
    );
    expect(iphone13.label, 'ios-low');
    expect(iphone13.textTokenWindow, 12288);
    expect(iphone13.multimodalTokenWindow, 2048);
    expect(iphone13.imageMaxDimension, 640);
    expect(iphone13.preferCpuForImage, isTrue);

    final pixel8ClassAndroid = DeviceRuntimeProfile.forMemoryBytes(
      8 * 1024 * 1024 * 1024,
    );
    expect(pixel8ClassAndroid.label, 'android-medium');
    expect(pixel8ClassAndroid.textTokenWindow, 24576);
    expect(pixel8ClassAndroid.multimodalTokenWindow, 4096);
    expect(pixel8ClassAndroid.imageMaxDimension, 768);

    final highMemoryAndroid = DeviceRuntimeProfile.forMemoryBytes(
      12 * 1024 * 1024 * 1024,
    );
    expect(highMemoryAndroid.label, 'android-high');
    expect(highMemoryAndroid.multimodalTokenWindow, 8192);
    expect(highMemoryAndroid.imageMaxDimension, 1024);
  });

  test('runtime profiles cannot exceed the model token budget', () {
    expect(
      MethodChannelGemmaRuntime.runtimeSessionTokenLimitForTesting(
        gemma4E2bIt,
        isAppleMobile: true,
        totalMemoryBytes: 4 * 1024 * 1024 * 1024,
      ),
      4000,
    );
    expect(
      MethodChannelGemmaRuntime.runtimeSessionTokenLimitForTesting(
        gemma4E2bIt,
        supportImage: true,
        isAppleMobile: true,
        totalMemoryBytes: 4 * 1024 * 1024 * 1024,
      ),
      2048,
    );
    expect(
      MethodChannelGemmaRuntime.runtimeSessionTokenLimitForTesting(
        gemma4E2bIt,
        isAppleMobile: true,
        totalMemoryBytes: 6 * 1024 * 1024 * 1024,
      ),
      4000,
    );
    expect(
      MethodChannelGemmaRuntime.runtimeSessionTokenLimitForTesting(
        gemma4E2bIt,
        totalMemoryBytes: 8 * 1024 * 1024 * 1024,
      ),
      4000,
    );
    expect(
      MethodChannelGemmaRuntime.runtimeSessionTokenLimitForTesting(
        gemma4E2bIt,
        totalMemoryBytes: 12 * 1024 * 1024 * 1024,
      ),
      4000,
    );
  });
}
