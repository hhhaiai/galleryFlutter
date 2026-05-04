import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_local_app/src/features/models/model_download_service.dart';

void main() {
  test('download smoother throttles noisy progress and keeps ETA stable', () {
    final smoother = ModelDownloadProgressSmoother(
      minEmitInterval: const Duration(milliseconds: 800),
      speedSmoothing: 0.25,
    );
    final t0 = DateTime(2026);

    final first = smoother.filter(
      const ModelDownloadStatus(
        type: ModelDownloadStatusType.inProgress,
        receivedBytes: 100,
        totalBytes: 1000,
        bytesPerSecond: 100,
      ),
      now: t0,
    );
    expect(first, isNotNull);
    expect(first!.receivedBytes, 100);

    final noisy = smoother.filter(
      const ModelDownloadStatus(
        type: ModelDownloadStatusType.inProgress,
        receivedBytes: 120,
        totalBytes: 1000,
        bytesPerSecond: 2000,
      ),
      now: t0.add(const Duration(milliseconds: 200)),
    );
    expect(noisy, isNull);

    final visible = smoother.filter(
      const ModelDownloadStatus(
        type: ModelDownloadStatusType.inProgress,
        receivedBytes: 300,
        totalBytes: 1000,
        bytesPerSecond: 900,
      ),
      now: t0.add(const Duration(milliseconds: 900)),
    );
    expect(visible, isNotNull);
    expect(visible!.receivedBytes, 300);
    expect(visible.bytesPerSecond, greaterThan(0));
    expect(visible.estimatedRemaining, isNotNull);
  });

  test('download smoother never moves visible received bytes backwards', () {
    final smoother = ModelDownloadProgressSmoother(
      minEmitInterval: Duration.zero,
    );
    final t0 = DateTime(2026);

    expect(
      smoother
          .filter(
            const ModelDownloadStatus(
              type: ModelDownloadStatusType.inProgress,
              receivedBytes: 500,
              totalBytes: 1000,
              bytesPerSecond: 100,
            ),
            now: t0,
          )!
          .receivedBytes,
      500,
    );

    expect(
      smoother
          .filter(
            const ModelDownloadStatus(
              type: ModelDownloadStatusType.inProgress,
              receivedBytes: 450,
              totalBytes: 1000,
              bytesPerSecond: 100,
            ),
            now: t0.add(const Duration(seconds: 1)),
          )!
          .receivedBytes,
      500,
    );
  });
}
