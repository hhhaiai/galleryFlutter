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
- 侧边 Models UI：`lib/src/features/models/models_drawer.dart`
- 主页面接入：`lib/src/features/gemma_home/gemma_home_screen.dart`

当前行为：

1. App 左上角打开侧边栏。
2. 进入 `设置 > Models`。
3. 只显示 `Gemma-4-E2B-it` 一个模型。
4. 点击下载。
5. 文件先保存为 `.gallerytmp`。
6. 如果暂停/失败，下次点击继续下载会使用 HTTP Range 继续。
7. 下载完成后 rename 为正式 `.litertlm` 文件。
8. 主对话入口要求模型已下载，否则提示先去 Models 下载。

## 新工程存储路径

Flutter 使用 `path_provider.getApplicationSupportDirectory()` 作为跨平台 app files dir。

最终路径：

```text
{applicationSupportDirectory}/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm
```

临时路径：

```text
{applicationSupportDirectory}/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm.gallerytmp
```

## 与原工程差异

- 原 Android 工程用 WorkManager 做后台下载和系统通知。
- 当前 Flutter 工程先用 Dart `http.Client` 在前台下载，保留同样的 `.gallerytmp` 和 Range 续传规则。
- 后续 Android 真机版可再升级为 WorkManager 后台下载，或者继续使用 Dart 前台下载。

## 后续接入本地推理

下载完成后，`LocalGemmaRuntime.initialize(gemma4E2bIt)` 应读取同一路径：

```dart
final modelPath = gemma4E2bIt.localModelPath(appFilesDir);
```

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
