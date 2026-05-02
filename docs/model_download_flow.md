# 模型下载与使用流程

目标：和 Google AI Edge Gallery 一样，不把模型打包进 App，而是在侧边设置的 `Models` 中下载，下载完成后本地运行时使用该文件。

## 来源工程逻辑

来源路径：

- 下载入口：`Android/src/app/src/main/java/com/google/ai/edge/gallery/ui/modelmanager/ModelManager.kt`
- 状态管理：`Android/src/app/src/main/java/com/google/ai/edge/gallery/ui/modelmanager/ModelManagerViewModel.kt`
- 下载仓库：`Android/src/app/src/main/java/com/google/ai/edge/gallery/data/DownloadRepository.kt`
- 后台下载 Worker：`Android/src/app/src/main/java/com/google/ai/edge/gallery/worker/DownloadWorker.kt`

原工程关键规则：

1. 进入侧边/Models 管理页。
2. 点击模型下载。
3. 下载前删除该模型旧目录。
4. 下载保存为临时文件：`{modelFile}.gallerytmp`。
5. 如果临时文件存在，使用 HTTP `Range` 断点续传。
6. 下载成功后把临时文件 rename 为正式模型文件。
7. 模型状态分为：未下载、部分下载、下载中、解压中、成功、失败。
8. 模型文件路径：

```text
{externalFilesDir}/{normalizedName}/{version}/{downloadFileName}
```

## 新 Flutter 工程实现

实现路径：

- 下载服务：`lib/src/features/models/model_download_service.dart`
- Android 下载仓库：`android/app/src/main/kotlin/com/example/gemma_local_app/download/ModelDownloadRepository.kt`
- Android 后台下载 Worker：`android/app/src/main/kotlin/com/example/gemma_local_app/download/ModelDownloadWorker.kt`
- 侧边 Models UI：`lib/src/features/models/models_drawer.dart`
- 主页面接入：`lib/src/features/gemma_home/gemma_home_screen.dart`

当前行为：

1. App 左上角打开侧边栏。
2. 进入 `设置 > Models`。
3. 只显示 `Gemma-4-E2B-it` 一个模型。
4. 点击下载。
5. Android 走 WorkManager + ForegroundInfo 系统后台下载；iOS 走原生 Swift `URLSessionConfiguration.background` 后台下载；桌面平台走 Dart 前台下载兜底。
6. Android 先用 HEAD / Range probe 判断远端是否支持 bytes range。
7. 如果远端支持 Range 且文件足够大，Android Worker 使用最多 4 个并发 range 分片下载。
8. 每个分片保存为：`{modelFile}.gallerytmp.part{index}`。
9. 断点续传：下次启动下载时，已存在的 part 文件按长度继续请求 `Range: bytes={partStart + existingBytes}-{partEnd}`。
10. 所有 part 完成后合并成 `{modelFile}.gallerytmp`，再 rename 为正式 `.litertlm` 文件。
11. 如果远端不支持 Range 或文件较小，回落到单流 `.gallerytmp` 下载，也支持 HTTP Range 续传。
12. 主对话入口要求模型已下载，否则提示先去 Models 下载。

## Android 多进程/并发下载策略

本轮改造重点是“多进程下载”的工程效果：在 Android WorkManager 的单个前台 Worker 内启动多个 IO coroutine，每个 coroutine 下载一个 HTTP byte range。这样能利用多个连接并发拉取大模型，同时仍由 WorkManager 统一负责后台生命周期、通知和任务恢复。

关键参数：

```text
MAX_PARALLEL_DOWNLOADS = 4
TARGET_PART_SIZE_BYTES = 512 MiB
MIN_PARALLEL_DOWNLOAD_BYTES = 64 MiB
```

对 `Gemma-4-E2B-it` 约 2.58GB 文件，通常会拆成 4 个分片。分片文件可独立续传。用户取消、网络失败或进程被系统杀死后，下一次点击下载会复用这些 `.partN` 文件继续下载，不会从 0 开始。

进度计算：

- `receivedBytes` = 各 part 文件长度之和，或单流 `.gallerytmp` 长度。
- `totalBytes` = HEAD/配置得到的模型总大小。
- `bytesPerSecond` = 最近一次进度间隔内的总增量。

## 新工程存储路径

Android WorkManager 使用 `context.getExternalFilesDir(null)`，和 Google AI Edge Gallery 规则保持一致：

```text
{externalFilesDir}/gemma-4-e2b-it.litertlm
```

Android 真机实际路径：

```text
/storage/emulated/0/Android/data/com.example.gemma_local_app/files/gemma-4-e2b-it.litertlm
```

临时/分片路径：

```text
{externalFilesDir}/gemma-4-e2b-it.litertlm.gallerytmp
{externalFilesDir}/gemma-4-e2b-it.litertlm.gallerytmp.part0
{externalFilesDir}/gemma-4-e2b-it.litertlm.gallerytmp.part1
...
```

兼容迁移：旧路径 `{externalFilesDir}/Gemma_4_E2B_it/{commitHash}/gemma-4-E2B-it.litertlm` 如果已经下载完成，`refreshStatus` 会迁移到新扁平路径。

iOS 原生后台下载保存到 Application Support 下的 Gallery 风格目录：

```text
{ApplicationSupportDirectory}/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm
{ApplicationSupportDirectory}/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm.gallerytmp
```

iOS 采用 `URLSessionConfiguration.background` 由系统托管后台生命周期；如果 `.gallerytmp` 已存在，启动请求时带 `Range: bytes={downloadedBytes}-`。续传完成时只有 HTTP 206 才追加到旧 `.gallerytmp`；若服务器返回 200，说明 Range 被忽略，会丢弃旧临时文件并从完整响应覆盖写，避免把完整文件追加到 partial 后生成坏模型。进度展示会把已有 offset 和本次 task 写入量相加。

桌面平台暂时使用 `path_provider.getApplicationSupportDirectory()` + Dart `http.Client` 前台下载兜底，已修复 Range 被服务器忽略返回 200 时错误 append 导致的坏文件风险。

## 与原工程差异

- 原 Android 工程用 WorkManager 做后台下载和系统通知。
- 当前 Flutter 工程 Android 已迁移为 WorkManager 后台下载，并增加并发 range 分片下载。
- 非 Android 平台仍保留 Dart `http.Client` 前台下载兜底，使用 `.gallerytmp` 和 Range 续传规则。

## 后续接入本地推理

下载完成后，`LocalGemmaRuntime.initialize(gemma4E2bIt)` 必须读取 Android `getExternalFilesDir(null)` 下的模型路径，而不是 Flutter `path_provider.getApplicationSupportDirectory()` 返回的内部 app support 路径。Android WorkManager 下载保存位置是外部 app files：

```text
/storage/emulated/0/Android/data/com.example.gemma_local_app/files/gemma-4-e2b-it.litertlm
```

如果 Runtime 仍按 app support 路径或旧嵌套路径初始化，会出现 `PlatformException ... Model file not found`，即下载成功但 LiteRT-LM 找不到文件。

Android MethodChannel 接 LiteRT-LM 时，把这个路径传给原生层：

```kotlin
EngineConfig(
  modelPath = modelPath,
  backend = Backend.GPU(),
  visionBackend = Backend.GPU(),
  audioBackend = Backend.CPU(),
  maxNumTokens = 4000,
)
```

## Android Runtime ANR 注意

发送第一条消息时不要在 Android 主线程初始化 LiteRT-LM。真机日志显示主线程初始化会触发：

```text
Input dispatching timed out ... MainActivity is not responding. Waited 5003ms for FocusEvent
RssHwmKb: 5283020
```

当前修复：

- 原生 `GemmaLiteRtRuntime` 使用单线程 executor 执行 `Engine.initialize()`、`createConversation()` 和 `sendMessageAsync()` 启动逻辑。
- MethodChannel result 和 EventChannel sink 回调切回主线程发送。
- 首轮文本验证暂用 CPU、`maxTokens=1024`，并关闭 vision/audio backend，降低内存峰值和首轮加载压力。

## 待补强

- sha256 或 size 强校验。
- 更细粒度的失败重试策略：单个 part 可有限重试，避免整体失败。
- Android 真机长时间下载验证：取消/杀进程/断网/恢复网络后确认 `.partN` 能继续续传。
