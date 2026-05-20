# CLAUDE.md

本文件是 `gemma_local_app` 工程的完整会话记录、项目规划、架构说明、实现方式和后续开发指南。后续任何 AI/Claude/Agent 接手本项目时，优先阅读并维护本文件。

## 1. 项目定位

项目路径：

```text
/Users/sanbo/Desktop/gallery/gemma_local_app
```

来源工程路径：

```text
/Users/sanbo/Desktop/gallery
```

来源工程是 Google AI Edge Gallery Android 工程。本项目目标是从该 Android 工程中抽取 Gemma 本地能力，新建一个 Flutter 跨平台本地化程序，只使用 `Gemma-4-E2B-it` 模型，并逐步支持：

- iOS
- Android
- macOS
- Windows
- Linux

根本原则 / 项目边界：

- 本项目的根因和核心价值是：**把 Gemma 作为本地大模型，作为文字对话、图片识别、语音理解、Prompt Lab、Agent Skills 等所有能力的基础。**
- 所有能力优先验证“Gemma 本地模型是否能直接承担该能力”。如果某项能力最终必须改用其它模型、云端模型或完全独立的非 Gemma 方案作为主要能力来源，那么该方案不属于本项目的核心验证目标。
- 对于 audio 等当前不稳定能力，可以做输入格式归一化、固定样本 harness、runtime 接口验证、或临时 UI 降级；但不能把“换成其它方案”当作本项目的最终成功路径。若确认必须依赖其它方案，应该停止在本项目内继续深测该方向，另开项目或作为外部集成方案评估。
- 可接受的临时降级仅限于保护文字/图片稳定体验、辅助定位 Gemma runtime 问题，不能替代最终“Gemma 本地模型承载能力”的目标。

应用显示名称：

```text
galleryFlutter
```

核心产品能力目标：

- ChatGPT 等主流聊天应用风格布局：顶部模型状态、中间消息气泡、底部 composer
- 本地对话
- 图片理解入口
- 语音理解入口
- Prompt Lab 入口和模板选择
- Agent Skills 入口
- 侧边设置 Models 中下载模型
- 下载完成后使用本地模型文件进行推理

当前阶段性质：

- 架构设计已完成，可以进入工程实现阶段。
- 已完成 Flutter 跨平台工程骨架。
- 已完成单模型配置抽取。
- 已完成侧边 Models 下载模型流程。
- 已完成 Prompt Lab / Skills / Runtime 抽象骨架。
- 已开始 Android LiteRT-LM MethodChannel 真推理桥接：已添加 LiteRT-LM Android 依赖、MainActivity MethodChannel/EventChannel 桥接骨架、Dart MethodChannelGemmaRuntime 调用逻辑。
- Android LiteRT-LM 桥接仍需通过 Gradle 构建和真机模型推理验证。

## 2. 会话背景与用户要求

用户最初要求：

> 这是谷歌的一个 gemma 本地的软件，帮我抽取下，我希望只使用 gemma-4-e2b-it 模型，然后新建一个工程，把这部分抽取并梳理成支持 ios/android/mac/win/linux 的本地化程序，我手机安装了编译后的版本，看上去支持图片/声音/对话/skills/prompt lab

随后用户补充：

> 好，模型也使用和这套工程一样的方式，下载然后使用。现在工程是侧边设置 models 中下载这个模型

最后用户要求：

> 所有的进展项目规划，全部整理到一个文件中 /Users/sanbo/Desktop/gallery/gemma_local_app/CLAUDE.md 中，要求会话，项目架构，实现方式等完整，完善

重要偏好：

- 所有项目进展、架构、逻辑、规划都要同步到文档。
- 当前汇总文件是本文件：`CLAUDE.md`。
- 后续若继续开发，必须更新本文件中的进展、决策、待办和验证记录。

## 3. 来源工程关键路径

Google AI Edge Gallery Android 工程中已定位的关键代码：

```text
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/data/Model.kt
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/data/Tasks.kt
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/data/ModelAllowlist.kt
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/ui/llmchat/LlmChatModelHelper.kt
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/runtime/LlmModelHelper.kt
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/ui/llmsingleturn/PromptTemplateConfigs.kt
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/agentchat/
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/assets/skills/*/SKILL.md
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/proto/skill.proto
```

模型下载相关来源路径：

```text
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/ui/modelmanager/ModelManager.kt
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/ui/modelmanager/ModelManagerViewModel.kt
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/data/DownloadRepository.kt
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/worker/DownloadWorker.kt
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/data/Consts.kt
```

模型 allowlist 来源：

```text
/Users/sanbo/Desktop/gallery/model_allowlists/1_0_12.json
```

## 4. 单模型策略

本项目只使用一个模型：

```text
Gemma-4-E2B-it
```

抽取来源：

```text
/Users/sanbo/Desktop/gallery/model_allowlists/1_0_12.json
```

模型配置：

```json
{
  "name": "Gemma-4-E2B-it",
  "modelId": "litert-community/gemma-4-E2B-it-litert-lm",
  "modelFile": "gemma-4-E2B-it.litertlm",
  "commitHash": "7fa1d78473894f7e736a21d920c3aa80f950c0db",
  "sizeInBytes": 2538766336,
  "minDeviceMemoryInGb": 8,
  "llmSupportImage": true,
  "llmSupportAudio": true,
  "llmSupportThinking": true,
  "defaultConfig": {
    "topK": 64,
    "topP": 0.95,
    "temperature": 1.0,
    "maxContextLength": 32000,
    "maxTokens": 4000,
    "accelerators": "gpu,cpu",
    "visionAccelerator": "gpu"
  },
  "taskTypes": [
    "llm_chat",
    "llm_prompt_lab",
    "llm_agent_chat",
    "llm_ask_image",
    "llm_ask_audio"
  ],
  "bestForTaskTypes": [
    "llm_chat",
    "llm_prompt_lab",
    "llm_agent_chat",
    "llm_ask_image",
    "llm_ask_audio"
  ]
}
```

下载地址：

```text
https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm?download=true
```

Flutter 固化位置：

```text
lib/src/core/model/gemma_model_config.dart
```

注意：后续不要重新引入其它模型列表；除非用户明确要求，否则保持单模型。

## 5. 新工程结构

当前主要 Flutter/Dart 文件：

```text
lib/main.dart
lib/src/app/gemma_local_app.dart
lib/src/core/model/gemma_model_config.dart
lib/src/core/runtime/local_gemma_runtime.dart
lib/src/core/runtime/platform_gemma_runtime.dart
lib/src/features/gemma_home/gemma_home_screen.dart
lib/src/features/models/model_download_service.dart
lib/src/features/models/models_drawer.dart
lib/src/features/prompt_lab/prompt_templates.dart
lib/src/features/skills/skill.dart
```

测试：

```text
test/widget_test.dart
```

已生成平台目录：

```text
android/
ios/
macos/
windows/
linux/
```

文档目录：

```text
docs/architecture.md
docs/feature_mapping.md
docs/model_download_flow.md
docs/model_gemma_4_e2b_it.md
docs/progress.md
CLAUDE.md
README.md
```

## 6. 当前依赖

`pubspec.yaml` 当前核心依赖：

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  path_provider: ^2.1.5
  http: ^1.6.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
```

依赖用途：

- `path_provider`：跨平台获取 Application Support Directory，用作模型下载和存储目录。
- `http`：Dart 前台下载 HuggingFace 模型，支持 HTTP Range 断点续传。

## 7. 架构设计

整体分层：

```text
UI 层
  GemmaHomeScreen
  ModelsDrawer

Feature 层
  models/model_download_service.dart
  prompt_lab/prompt_templates.dart
  skills/skill.dart

Core 层
  model/gemma_model_config.dart
  runtime/local_gemma_runtime.dart
  runtime/platform_gemma_runtime.dart

Platform 层
  Android MethodChannel -> LiteRT-LM Engine / Conversation，已建立桥接骨架，待构建/真机验证
  iOS/macOS/Windows/Linux 本地后端，待实现
```

### 7.1 App 入口

```text
lib/main.dart
```

职责：

- 调用 `runApp(const GemmaLocalApp())`。

### 7.2 App 壳

```text
lib/src/app/gemma_local_app.dart
```

职责：

- 配置 `MaterialApp`。
- 配置 light/dark theme。
- 入口页面为 `GemmaHomeScreen`。

### 7.3 模型配置

```text
lib/src/core/model/gemma_model_config.dart
```

职责：

- 定义 `GemmaModelConfig`。
- 定义 `GemmaTaskId`。
- 定义 `GemmaAccelerator`。
- 固化 `gemma4E2bIt`。
- 生成 HuggingFace 下载 URL。
- 生成本地模型路径。

关键路径生成逻辑：

```dart
String get huggingFaceDownloadUrl =>
    'https://huggingface.co/$modelId/resolve/$commitHash/$modelFile?download=true';

String get normalizedName => name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

String localModelPath(String appFilesDir) =>
    '$appFilesDir/$normalizedName/$commitHash/$modelFile';
```

注意：这里必须使用真实 Dart 字符串插值，不要写成 `\$modelId` 或 `\${config.name}`。

### 7.4 运行时抽象

```text
lib/src/core/runtime/local_gemma_runtime.dart
```

职责：

- 定义 Flutter 侧统一本地模型运行时接口。

接口：

```dart
abstract interface class LocalGemmaRuntime {
  Future<void> initialize(GemmaModelConfig config);
  Stream<String> generate(GemmaRequest request);
  Future<void> stop();
  Future<void> dispose();
}
```

请求结构：

```dart
class GemmaRequest {
  final String prompt;
  final String? systemPrompt;
  final List<String> imagePaths;
  final List<String> audioPaths;
  final List<String> enabledSkillNames;
}
```

### 7.5 当前平台运行时

```text
lib/src/core/runtime/platform_gemma_runtime.dart
```

职责：

- 当前 `MethodChannelGemmaRuntime` 在 Android 上调用 `com.example.gemma_local_app/runtime` MethodChannel 和 `com.example.gemma_local_app/runtime_events` EventChannel；非 Android 平台使用 `PlaceholderGemmaRuntime` 占位实现。
- 下载完成后可初始化 Android LiteRT-LM。
- `generate()` 在 Android 上通过 EventChannel 流式返回 token；非 Android 平台仍输出占位提示。

当前 Android 原生桥接：

- `android/app/src/main/kotlin/com/example/gemma_local_app/MainActivity.kt`
- MethodChannel：`com.example.gemma_local_app/runtime`
- EventChannel：`com.example.gemma_local_app/runtime_events`
- 方法：`initialize` / `generate` / `stop` / `dispose`

后续目标：

- Android：完成 Gradle 构建验证和真机 LiteRT-LM 推理验证。
- 其它平台：接入对应本地推理后端。

### 7.6 主页面

```text
lib/src/features/gemma_home/gemma_home_screen.dart
```

职责：

- 提供 ChatGPT 等主流聊天应用风格布局。
- 顶部展示应用名、模型名和模型下载状态 Chip。
- 中间展示用户/助手消息气泡和流式生成状态。
- 底部 composer 支持文字输入、图片入口、语音入口、Skills、Prompt Lab。
- Prompt Lab 开启时展示模板选择。
- 模型未下载时阻止真实发送并提示。
- 接入侧边 Models Drawer。

当前逻辑：

- `initState()` 中创建并监听 `ModelDownloadController` 状态。
- `refreshStatus(gemma4E2bIt)` 检查本地模型文件是否存在。
- 如果模型已下载，则调用 `_runtime.initialize(gemma4E2bIt)`。
- 点击发送前检查 `_downloadStatus.isDownloaded`。

### 7.7 Models 侧边栏

```text
lib/src/features/models/models_drawer.dart
```

职责：

- 提供左侧设置 UI。
- 显示 `Models` 分组。
- 只展示 `Gemma-4-E2B-it`。
- 展示状态、路径、进度、速度、错误。
- 提供按钮：下载、暂停、刷新、删除。

### 7.8 模型下载服务

```text
lib/src/features/models/model_download_service.dart
```

职责：

- 管理模型下载状态。
- 使用 `path_provider.getApplicationSupportDirectory()` 获取跨平台 app files dir。
- 使用 Dart `http.Client` 下载。
- 使用 `.gallerytmp` 临时文件。
- 支持 HTTP Range 断点续传。
- 下载完成后 rename 成正式 `.litertlm` 文件。
- 支持删除模型目录。

状态枚举：

```dart
enum ModelDownloadStatusType {
  notDownloaded,
  partiallyDownloaded,
  inProgress,
  succeeded,
  failed,
}
```

临时扩展名：

```dart
const galleryTmpFileExt = 'gallerytmp';
```

当前下载策略与原工程保持一致的部分：

- 不把模型打包进 App。
- 侧边 Models 触发下载。
- 临时文件：`{modelFile}.gallerytmp`。
- 存在临时文件时用 HTTP `Range` 继续下载。
- 下载成功后 rename。
- 主功能要求模型已下载。

当前与原工程差异：

- 原 Android 工程使用 WorkManager 后台下载和通知。
- 当前 Flutter 工程使用 Dart 前台下载。
- 后续 Android 真机可升级为 WorkManager 后台下载，或保留 Dart 方案。

## 8. 模型存储路径

### 8.1 原 Google AI Edge Gallery Android 模型目录

原始代码依据：

- `Android/src/app/src/main/java/com/google/ai/edge/gallery/data/Model.kt`
  - `Model.getPath(context, fileName)` 使用 `context.getExternalFilesDir(null)`。
  - 默认拼接：`{externalFilesDir}/{normalizedName}/{version}/{downloadFileName}`。
- `Android/src/app/src/main/java/com/google/ai/edge/gallery/worker/DownloadWorker.kt`
  - 下载目录：`applicationContext.getExternalFilesDir(null) / modelDir / version`。
  - 临时文件：`{fileName}.gallerytmp`。
  - 下载完成后 rename 成正式模型文件。

Android 外部应用文件目录实际对应：

```text
/storage/emulated/0/Android/data/<app_id>/files
```

原工程代码注释说明 app id 有两种常见情况：

```text
com.google.aiedge.gallery     # 从 GitHub source 构建的包名
com.google.ai.edge.gallery    # Play Store / internal / 其它发布包名
```

Gemma-4-E2B-it 的原始模型最终路径：

```text
/storage/emulated/0/Android/data/<app_id>/files/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm
```

如果还没下载完成，临时文件路径是：

```text
/storage/emulated/0/Android/data/<app_id>/files/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm.gallerytmp
```

可用以下命令在 Android 真机上确认原 Edge Gallery 包名和文件：

```bash
adb shell pm list packages | grep -i gallery
adb shell ls -lh /sdcard/Android/data/com.google.aiedge.gallery/files/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/
adb shell ls -lh /sdcard/Android/data/com.google.ai.edge.gallery/files/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/
```

导出到 Mac：

```bash
mkdir -p /Users/sanbo/Desktop/gallery/exported_models/Gemma_4_E2B_it
adb pull /sdcard/Android/data/com.google.aiedge.gallery/files/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm /Users/sanbo/Desktop/gallery/exported_models/Gemma_4_E2B_it/
# 如果上面包名不存在，换用：
adb pull /sdcard/Android/data/com.google.ai.edge.gallery/files/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm /Users/sanbo/Desktop/gallery/exported_models/Gemma_4_E2B_it/
```

导入到当前 galleryFlutter 测试 App，避免重复下载：

```bash
adb shell mkdir -p /sdcard/Android/data/com.example.gemma_local_app/files/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/
adb push /Users/sanbo/Desktop/gallery/exported_models/Gemma_4_E2B_it/gemma-4-E2B-it.litertlm /sdcard/Android/data/com.example.gemma_local_app/files/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm
```

注意：当前 Flutter 侧使用 `path_provider.getApplicationSupportDirectory()`；在 Android 上通常也是 app 专属 files 目录。若实际路径有差异，可在 Models 页面刷新状态确认，或后续增加“导入本地模型”按钮。

### 8.2 新 Flutter 工程模型目录

新 Flutter 工程使用：

```text
{applicationSupportDirectory}/{normalizedName}/{commitHash}/{modelFile}
```

对于当前模型，最终路径为：

```text
{applicationSupportDirectory}/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm
```

临时下载路径为：

```text
{applicationSupportDirectory}/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm.gallerytmp
```

## 9. 功能映射

### 9.1 对话

来源：

```text
LlmChatModelHelper.initialize(...)
LlmChatModelHelper.runInference(...)
```

当前 Flutter 抽取：

- 入口：`GemmaTaskId.chat`
- 请求：`GemmaRequest(prompt: ...)`
- 运行时：`LocalGemmaRuntime.generate(...)`

当前状态：

- Android 已通过 MethodChannel 接入 LiteRT-LM `Engine` / `Conversation`，并通过 EventChannel 流式回传 token。
- iOS 文字对话当前走 Dart 侧 `flutter_gemma` `.litertlm` FFI 路径，不走 `IOSGemmaRuntime.swift` 的 MediaPipe 原生占位 channel。
- 后续 audio / skills 改动必须先跑文字对话 smoke test，避免破坏当前已可用闭环。

### 9.2 图片理解

来源：

```text
Model.llmSupportImage
EngineConfig.visionBackend
runInference(images: List<Bitmap>)
```

当前 Flutter 抽取与稳定实现：

- 入口：`GemmaTaskId.askImage`
- 请求字段：`GemmaRequest.imagePaths`
- UI 流程：点击图片按钮弹出「拍照 / 从相册选择」，通过 `image_picker` 得到本地图片路径；发送前图片缩略图附着在输入框上方，可删除，可附带文字一起发送。
- 已发送图片展示：`_ChatMessage.imagePaths` 保存图片路径；`_SentImagePreviewGrid` 在用户消息气泡内展示缩略图，不再只显示 `[图片 × 1]`；点击图片打开 `_ImagePreviewDialog`，支持全屏查看、多图翻页、`InteractiveViewer` 缩放。
- Android 图片输入：Flutter MethodChannel 传 `imagePaths` 到 `android/app/src/main/kotlin/com/example/gemma_local_app/MainActivity.kt`；原生端按 Google AI Edge Gallery 的 `handleImagesSelected()` / `decodeSampledBitmapFromUri()` / `rotateBitmap()` 思路读取 EXIF 方向、按 1024x1024 采样解码、旋转 Bitmap，再转 PNG bytes。
- Android LiteRT-LM 内容构造：先将图片加入 `Content.ImageBytes(imageBytes)`，再将 prompt 加入 `Content.Text(prompt)`，最终调用 `currentConversation.sendMessageAsync(Contents.of(contents), callback)`。
- Android backend 关键决策：图片能力开启时必须走 Gallery 同款 GPU 多模态路线。Dart 侧 `platform_gemma_runtime.dart` 在 `supportImage` 为 true 时传 `accelerator: 'gpu'`；Kotlin 侧 `EngineConfig.backend = Backend.GPU()`，`visionBackend = Backend.GPU()`。此前 CPU 主 backend 或错误 vision backend 会导致 LiteRT-LM `Status Code: 12/13 / Failed to invoke the compiled model`。
- iOS 图片输入：Flutter 通过 `flutter_gemma` 的 `.litertlm` FFI 路径加载模型，`getActiveModel()` 显式 `supportImage: true` 与 `maxNumImages: 1`；发送图片时调用 `Message.withImage(text:imageBytes:isUser:)`。
- iOS 稳定性策略：iOS `.litertlm` FFI 的 vision session 不可靠复用，第一次图片识别成功后第二次可能失败或忽略图片。当前对每次图片请求执行 `forceReload`：关闭旧 chat session、关闭旧 `_flutterGemmaModel`、重新 `installModel/getActiveModel/createChat`，再发送图片；文字请求不做完整重启，避免普通对话变慢。
- Prompt 策略：`_visionPrompt()` 会把默认图片描述请求转换为明确视觉问答指令；用户带文字时转换为「请根据图片内容回答：...」，避免模型进入无图普通聊天。
- 真机验证：Android 与 iOS 均已完成真实图片发送、模型识别与回复验证；iOS 连续多次图片识别已测试成功。当前优先保证识别稳定性，接受 iOS 图片请求略慢。

### 9.3 声音理解 / 语音消息 / Live 语音通话

来源：

```text
Model.llmSupportAudio
EngineConfig.audioBackend = Backend.CPU()
runInference(audioClips: List<ByteArray>)
```

当前实现方案已整理到：

```text
docs/audio_voice_live_design.md
```

当前 Flutter 抽取与第一阶段实现：

- 入口：`GemmaTaskId.askAudio`
- 请求字段：`GemmaRequest.audioPaths`
- 新增 `lib/src/features/gemma_home/audio_input_service.dart`，通过 `com.example.gemma_local_app/audio_input` MethodChannel 统一调用原生音频能力。
- UI：点击 composer「语音」按钮弹出 bottom sheet，包含「实时录音 / 停止录音」「选择语音文件」「Live 语音通话探索」；录音中再次点击 composer 语音按钮会直接停止并附加，点击发送时如仍在录音也会先停止并附加，避免用户误把空消息发出。
- 发送前：输入框上方显示 `_AttachedAudioStrip`，包含语音波形、播放按钮、时长、删除按钮。
- 发送后：`_ChatMessage.audioAttachments` 保存语音消息；用户消息气泡显示 `_VoiceMessageGrid` / `_VoiceMessageCard`，不再只显示 `[语音 × 1]`；点击卡片可播放。
- 默认语音 prompt：如果用户只发语音不写文字，默认使用「请识别并总结这段语音内容。」

Android 第一阶段：

- 添加 `RECORD_AUDIO` 权限。
- `MainActivity.kt` 新增 `AndroidAudioInput`：系统音频文件选择、`AudioRecord` 录音并封装成 16k / mono / 16-bit PCM WAV、`MediaPlayer` 播放。
- Runtime 初始化对齐 Gallery：`audioBackend = if (supportAudio) Backend.CPU() else null`。
- Android 音频请求的主 backend 已修正为与 Gallery 一致的多模态优先路径：audio/image 请求优先走 GPU 主 backend，纯文字仍保持 CPU 首轮轻量初始化。
- Runtime generate 读取 `audioPaths.take(1)`，将输入规整为 16k / mono / 16-bit PCM WAV，并以完整 WAV bytes 加入 `Content.AudioBytes(audioBytes)`；内容顺序为图片、音频、文本。
- 对 audio-only 请求，若 LiteRT-LM native compiled model 调用报 `Status Code: 12/13`，Dart 侧会自动补一次 CPU fallback，再降级回文字模式。
- 选择语音文件时，若拿到 m4a/mp3 等压缩音频，Android 原生侧会先用 `MediaExtractor + MediaCodec` 解码为 PCM，再统一落成 16k mono 16-bit PCM WAV 存盘；若本身是 WAV，则保留/按需规整成 Gemma 可用格式。
- 注意：旧版“剥离 RIFF/WAVE header 只传 PCM”的说明已废弃；当前对齐 Gallery 的实际 Ask Audio 路线：PCM 数据在发送前带 44 字节 WAV header，模型侧接收完整 WAV 容器。

iOS 第一阶段当前事实：

- 添加 `NSMicrophoneUsageDescription`。
- iOS 自有 `audio_input` 原生 channel（`UIDocumentPickerViewController`、`AVAudioRecorder`、`AVAudioPlayer`）已接入；`audio_input_events` 已能输出录音状态和电平事件。录音目标格式为 16k / mono / 16-bit PCM WAV，单段上限 30 秒；文件选择音频会统一转换为 16k mono 16-bit PCM WAV，并做 WAV header/时长校验。
- `flutter_gemma` API 层存在 `Message.withAudio(...)` / `supportAudio` 等能力；2026-05-14 已改为 LiteRT-LM raw FFI Conversation JSON media 路径，并在校验 16k mono 16-bit PCM WAV 后保留完整 WAV 容器。当前默认顺序固定为 text -> image -> audio，audio-only 使用 path JSON + 非流式 `sendMessage`，people iPhone profile smoke 已返回真实模型输出 `AUDIO_RECEIVED`。
- 仍需继续用用户自然语音做转写质量验收；若自然语音仍出现“请提供音频”或 code 13，应优先检查 JSON 顺序/音频文件有效性/LiteRT-LM backend，而不能用非 Gemma ASR 冒充成功。

Live 语音通话探索：

- Phase 1 当前实现：开始 Live 后每 4 秒切一段，把片段串行送 `GemmaRequest.audioPaths`，AI 先文字回复；输入区显示 Live 状态条，可直接停止。
- Phase 2 再做原生 PCM streaming + VAD：Android `AudioRecord`，iOS `AVAudioEngine`，实时波形和分段队列。
- Phase 3 再接 TTS，形成完整语音对话和打断策略。

待实现：

- Android：继续补强多来源音频（系统录音、微信导出、浏览器下载、第三方 App 分享）的真机验证与异常兼容处理。
- Android：真机验证语音文件、实时录音、点击播放、Gemma 语音理解。
- iOS：用固定 WAV 做 `flutter_gemma Message.withAudio` 专项 harness；若仍 code 13，记录 Gemma iOS audio blocker 并暂停本项目内 iOS audio 深测。
- iOS：在上述验证完成前，UI 继续隐藏/拦截 iOS 语音理解入口，不影响文字/图片。
- Live：先做 Phase 1 分段通话，再探索 PCM/VAD 真流式。

### 9.4 Prompt Lab

来源：

```text
PromptTemplateConfigs.kt
```

来源模板：

- Free form
- Rewrite tone
- Summarize text
- Code snippet

当前 Flutter 抽取：

```text
lib/src/features/prompt_lab/prompt_templates.dart
```

职责：

- 定义 `PromptTemplate`。
- 提供基础模板和 prompt 拼接。

待增强：

- 复刻原工程更多 editor 配置。
- 复刻原工程更丰富样例。

### 9.5 Skills / Agent Chat

来源：

```text
AgentChatTaskModule.kt
SkillManagerViewModel.kt
skill.proto
assets/skills/*/SKILL.md
```

原工程核心机制：

1. 从 assets 和 DataStore 加载 Skills。
2. 生成包含 `___SKILLS___` 的系统提示词。
3. 通过 LiteRT-LM `ToolProvider` 暴露 `load_skill` / `run_intent` 等工具。
4. 使用 constrained decoding 提高工具调用稳定性。

当前 Flutter 抽取：

```text
lib/src/features/skills/skill.dart
```

当前内容：

- `GemmaSkill` 数据结构。
- `agentSkillsSystemPrompt`。
- 部分内置 skill 占位：
  - calculate-hash
  - query-wikipedia
  - qr-code
  - send-email

待实现：

- 读取 assets/skills/SKILL.md。
- 支持启用/禁用 skills。
- 支持 secret/API key。
- Android 原生 ToolProvider 桥接。
- Dart/平台侧 tool call 分发。

## 10. Android LiteRT-LM 接入规划

当前最重要的下一步：让 Android 真机使用已下载模型跑本地推理。

### 10.1 原工程运行时映射

来源：

```text
Android/src/app/src/main/java/com/google/ai/edge/gallery/ui/llmchat/LlmChatModelHelper.kt
```

原工程初始化核心：

```kotlin
val engineConfig = EngineConfig(
  modelPath = modelPath,
  backend = preferredBackend,
  visionBackend = if (shouldEnableImage) visionBackend else null,
  audioBackend = if (shouldEnableAudio) Backend.CPU() else null,
  maxNumTokens = maxTokens,
  cacheDir = if (modelPath.startsWith("/data/local/tmp"))
    context.getExternalFilesDir(null)?.absolutePath
  else null,
)

val engine = Engine(engineConfig)
engine.initialize()

val conversation = engine.createConversation(
  ConversationConfig(
    samplerConfig = SamplerConfig(
      topK = topK,
      topP = topP.toDouble(),
      temperature = temperature.toDouble(),
    ),
    systemInstruction = systemInstruction,
    tools = tools,
  )
)
```

本项目 Android MethodChannel 应接收 Dart 参数：

```json
{
  "modelPath": ".../Gemma_4_E2B_it/.../gemma-4-E2B-it.litertlm",
  "topK": 64,
  "topP": 0.95,
  "temperature": 1.0,
  "maxTokens": 4000,
  "supportImage": true,
  "supportAudio": true,
  "accelerator": "gpu"
}
```

### 10.2 MethodChannel 建议接口

Dart -> Android：

```text
gemma_local/runtime.initialize
gemma_local/runtime.generate
gemma_local/runtime.stop
gemma_local/runtime.dispose
```

或者统一 channel：

```text
com.sanbo.gemma_local/runtime
```

方法：

```text
initialize(Map config)
generate(Map request)
stop()
dispose()
```

返回方式：

- 简单版：`generate` 一次性返回完整字符串。
- 推荐版：MethodChannel + EventChannel 流式返回 token。

### 10.3 Android Gradle 依赖

需要从原工程确认 LiteRT-LM 依赖：

```text
Android/src/app/build.gradle.kts
```

已观察到：

```kotlin
implementation(libs.litertlm)
```

接入新 Flutter Android 工程时，需要把对应 Maven repository / version catalog / dependency 迁移到：

```text
android/app/build.gradle.kts
android/settings.gradle.kts
android/build.gradle.kts
```

注意：不要盲目复制整个 Android 工程，只迁移 LiteRT-LM 运行必要依赖。

### 10.4 Android 权限

下载当前由 Dart 完成，不需要 Android WorkManager 下载权限。但后续如果迁移 WorkManager 后台下载，可能需要通知权限：

```text
POST_NOTIFICATIONS
```

当前推理本身主要依赖本地文件访问和 native libs。

## 11. iOS/macOS/Windows/Linux 接入规划

当前只创建了统一 Flutter 壳和运行时接口。桌面与 iOS 本地推理后端尚未选型。

候选方案：

1. 如果 Google LiteRT-LM 有对应平台 SDK：优先使用同模型格式 `.litertlm`。
2. 如果 `.litertlm` 主要面向 Android：需要确认是否可在 iOS/macOS/Windows/Linux 直接加载。
3. 若不可用：考虑转换/替代本地后端，例如 MediaPipe、LiteRT、llama.cpp，但这会影响模型格式和下载源。

当前原则：

- Flutter 层保持 `LocalGemmaRuntime` 接口稳定。
- 每个平台单独实现平台 adapter。
- 不在业务 UI 里写平台分支，除非是输入选择器差异。

## 12. 已完成进度

已完成：

- [x] 检查来源工程位置：`/Users/sanbo/Desktop/gallery`
- [x] 确认来源工程是 Google AI Edge Gallery Android 工程
- [x] 定位 Gemma-4-E2B-it allowlist 配置
- [x] 确认 Gemma-4-E2B-it 支持图片、声音、对话、Skills、Prompt Lab
- [x] 新建 Flutter 工程：`/Users/sanbo/Desktop/gallery/gemma_local_app`
- [x] 创建 iOS / Android / macOS / Windows / Linux 平台目录
- [x] 抽取单模型配置到 Dart
- [x] 建立 `LocalGemmaRuntime` 统一接口
- [x] 建立主界面骨架
- [x] 建立 Prompt Lab 模板骨架
- [x] 建立 Skills 数据结构和系统提示词骨架
- [x] 实现侧边设置 `Models` 中下载 Gemma-4-E2B-it
- [x] 实现 `.gallerytmp` 临时文件和 HTTP Range 断点续传
- [x] 模型未下载时阻止发送并提示去 Models 下载
- [x] 下载完成后调用 `_runtime.initialize(gemma4E2bIt)`
- [x] 更新 docs 与 README
- [x] 创建本文件 `CLAUDE.md`
- [x] 明确：架构设计已完成，可以开始工程编程实现
- [x] Android 最小 LiteRT-LM 依赖迁移：`com.google.ai.edge.litertlm:litertlm-android:0.10.0`
- [x] Android `MainActivity.kt` 增加 MethodChannel/EventChannel 桥接骨架
- [x] Dart `platform_gemma_runtime.dart` 改为 Android/iOS MethodChannel 调用，桌面平台保留占位实现
- [x] 应用显示名称改为 `galleryFlutter`，已覆盖 Flutter 标题、Android label、iOS/macOS display name、Linux/Windows 窗口/资源名
- [x] 主界面改为 ChatGPT 类聊天布局：顶部状态、中间消息气泡、底部 composer
- [x] composer 增加图片、语音、Skills、Prompt Lab 快捷入口
- [x] Android 模型下载改为系统下载：DownloadManager + `.gallerytmp/.cfg` + 系统托管断点续传
- [x] Android 下载桥接新增 MethodChannel/EventChannel：`com.example.gemma_local_app/model_download` / `model_download_events`
- [x] Android 下载执行权迁移到系统 DownloadManager/DownloadProvider；“多进程”由系统下载服务进程承担，App 进程退出后系统仍可继续写 `.gallerytmp`
- [x] Android 模型文件路径调整为扁平路径：`/storage/emulated/0/Android/data/com.example.gemma_local_app/files/gemma-4-e2b-it.litertlm`；旧嵌套路径下载完成的模型会在 `refreshStatus` 时迁移
- [x] Android 发送文字后闪退/遮罩根因已定位为 LiteRT-LM 初始化在主线程触发 5s input dispatching ANR；已改为后台单线程初始化/生成，并将首轮推理降为 CPU + maxTokens 1024 + 暂停 vision/audio backend，避免首轮加载阻塞 UI
- [x] 聊天气泡支持 Markdown 渲染：新增 `flutter_markdown`，用户输入和模型输出均用 `MarkdownBody(selectable: true)` 展示，支持标题、列表、引用、行内代码和代码块
- [x] Android 真机已重新编译安装，并授予 POST_NOTIFICATIONS 权限用于前台下载通知
- [x] 常规验证通过：`dart format lib test`、`flutter analyze`、`flutter test`、`flutter build apk --debug`
- [x] Android 下载失败根因已重新收口：旧 WorkManager expedited worker 需要 ForegroundInfo，后续按用户要求废弃 App 进程内 Worker，改用系统 DownloadManager；adb 验证系统 DownloadThread 下载、App 被 kill 后临时文件仍增长
- [x] iOS 不再显示死胡同式“暂不支持”：参考 Google AI Edge Gallery 已上架 iOS App Store、Gallery README、LiteRT-LM iOS/macOS prebuilt 和 iOS allowlist，Dart runtime 旧 iOS 文案已移除；iOS 必须进入原生 MethodChannel runtime。
- [x] iOS 原生模型下载断点续传修复：`IOSModelDownloadManager.swift` 使用 `URLSessionConfiguration.background`，对已有 `.gallerytmp` 发送 `Range`；续传响应为 HTTP 206 时把本次下载片段追加到旧 `.gallerytmp`，响应为 200 时认为服务端忽略 Range 并覆盖重下，避免旧逻辑把剩余片段当成完整模型导致损坏文件；进度统计加入 resume offset。
- [x] Dart 前台下载兜底修复：如果已有 `.gallerytmp` 但 Range 请求返回 200，则删除旧 tmp 并用 `FileMode.write` 覆盖，不再 append 完整响应。
- [x] iOS runtime channel 已注册到 `com.example.gemma_local_app/runtime`：Flutter 侧现在 iOS 也走 MethodChannel，不再走 Dart Placeholder/占位输出。
- [x] Xcode/Swift toolchain 已从 Xcode 15.0.1 升级到 Xcode 26.4.1 / Swift 6.3.1，`ios/Podfile` 已启用 `MediaPipeTasksGenAI 0.10.35`，`pod install` 与 `flutter build ios --no-codesign` 均可成功链接。
- [x] iOS 真实文字对话 runtime 已接入：`IOSGemmaRuntime.swift` 使用 `LlmInference.Options(modelPath:)` 初始化模型，创建 `LlmInference.Session`，`generate` 调用 `session.addQueryChunk(inputText:)` 与 `session.generateResponseAsync()`，并把 partial token 通过 `com.example.gemma_local_app/runtime_events` 流式返回 Flutter。
- [x] 图片入口已升级为真实附件流程：点击图片弹出「拍照 / 从相册选择」，拍照或选择后缩略图附着到输入框，可删除，可附带文字一起发送；Android 参考 Gallery 以 1024x1024 采样 + EXIF 旋转后通过 `Content.ImageBytes` 接入 LiteRT-LM，iOS 通过 `flutter_gemma` 的 `Message.withImage` 接入。Android 与 iOS 真机图片识别均已测试成功；iOS 连续图片识别为保证稳定性，每次图片请求完整重建 vision runtime/model client。
- [x] 语音消息第一阶段已接入：新增 `audio_input_service.dart` 与 `com.example.gemma_local_app/audio_input` MethodChannel；Android 支持系统音频文件选择、`MediaRecorder` 实时录音、`MediaPlayer` 点击播放，发送后显示微信式语音波形卡片；runtime 已初步把 `audioPaths` 加入 `Content.AudioBytes`，并启用 Gallery 同款 `audioBackend = Backend.CPU()`。iOS runtime 已通过 `flutter_gemma` 的 `Message.withAudio(...)` 打开音频请求路径并添加麦克风权限文案。Live 语音通话架构、阶段方案和方案对比已记录到 `docs/audio_voice_live_design.md`。
- [x] Android 音频 runtime 已按 Gallery 工作基线补齐：音频请求不再错误地退回 CPU 主 backend，而是优先按多模态路径使用 GPU 主 backend + `audioBackend = Backend.CPU()`；若出现 LiteRT-LM `Status Code: 12/13 / Failed to invoke the compiled model`，Dart 侧会对 audio-only 请求自动补一次 CPU fallback，再回退到文字模式，减少不同 Android 设备上的 compiled model 调用失败。
- [x] Android 音频文件选择链路补强：系统 picker 对 m4a/mp3 等压缩音频会先经过 `MediaExtractor + MediaCodec` 解码为 PCM，再统一转成 16k mono 16-bit WAV；WAV 文件则保留/按需规整成 Gemma 可用格式，减少“选中了文件但 LiteRT-LM 只认 WAV”导致的失败。
- [x] iOS 录音链路已对齐运行时输入：`IOSAudioInput.swift` 录音输出已从 AAC/m4a 改为 16k / mono / 16-bit PCM WAV，并限制单段 30 秒，避免 iOS 应用内录音在 `flutter_gemma` 音频输入前就因容器格式不匹配而失败。
- [x] iOS 真机现状已重新确认：安装/启动链路可以打通，但 `flutter_gemma` 的 `.litertlm` iOS FFI 音频链在 `Gemma-4-E2B-it` 上会触发 `Failed to start streaming (code: 13)`；为保证整体稳定性，当前已在 Flutter 层显式关闭 iOS 语音输入 / Live，并给出清晰提示，不再让用户直接撞到 code 13。
- [x] Live 语音通话 Phase 1 已接入首个闭环：composer 里的「Live 语音通话」现在可直接开启/停止；运行时按 4 秒切一段，自动执行“录音 -> 音频理解 -> 文字回复 -> 继续监听”，并在输入区显示当前 Live 状态条，作为后续 VAD/真流式方案前的可用探索版。
- [x] Live Phase 1 细节补强：修复停止 Live 时递归调用 stop 的状态问题；对近似静音片段做跳过，避免持续把空白环境声发送给模型。
- [x] Live UX 已改为“前台持续通话、后台隐式切段”：Android 侧 runtime 初始化已改为可复用同一 audio conversation，避免每段都回到 text-only runtime 再重建；Flutter 侧 Live 使用全屏通话态覆盖层、持续时长、统一 AI 回复预览与“正在听/正在回应”状态，把 4 秒后台切段对用户隐藏起来，尽量让用户感知成“正在和 AI 持续语音对话”。

## 12.5 Google AI Edge GitHub 参考与用户体验设计（2026-05-02）

用户明确要求：必须参考 `https://github.com/google-ai-edge` 的公开代码，并基于 Google AI Edge Gallery 已在 App Store 上架的事实，设计良好的 iOS/Android/macOS 跨平台体验。

已调研的关键来源：

```text
google-ai-edge/gallery
google-ai-edge/LiteRT-LM
google-ai-edge/LiteRT
google-ai-edge/mediapipe-samples
App Store: Google AI Edge Gallery
```

结论：

1. `google-ai-edge/gallery` README 同时提供 Google Play 与 App Store 下载入口；本项目不能再把 iOS 简单标记为“暂不支持”。
2. `gallery/model_allowlists/ios_1_0_0.json` 存在 iOS allowlist，Gemma 3n E2B/E4B 条目明确描述 iOS 上支持 text、vision、audio input，说明 Gallery 的产品能力已经面向 iOS 规划/分发。
3. `google-ai-edge/LiteRT-LM` 存在 iOS/macOS 预编译组件目录，例如 `prebuilt/ios_arm64`、`prebuilt/ios_sim_arm64`、`prebuilt/macos_arm64`，说明 `.litertlm`/LiteRT-LM 路线不应被视为 Android-only。
4. `google-ai-edge/gallery` Android 端模型下载采用 `DownloadRepository.kt` + `DownloadWorker.kt` + WorkManager + notification；本项目 Android 曾按该方向实现，后按用户“必须使用系统下载”的要求改为 Android DownloadManager。
5. `google-ai-edge/mediapipe-samples/examples/llm_inference/ios` 展示 iOS LLM 示例的模型选择、下载页、聊天页、`NetworkService.swift`、`OnDeviceModel.swift`；可作为 iOS 下载/初始化/聊天体验参考。
6. Gallery Skills 公开资料包含 `skills/README.md`、`skill.proto`、内置/featured skills、本地导入、URL 导入、免责声明与校验流程。本项目 Skills Hub 设计应沿用这一产品形态。

新增 UX 设计文档：

```text
/Users/sanbo/Desktop/gallery/gemma_local_app/docs/google_ai_edge_ux_design.md
```

核心 UX 决策：

- 不再出现笼统“iOS 暂不支持 / 暂时不支持”。文字对话必须走真实 iOS runtime channel；如果失败，只能显示具体原因（模型未下载、文件缺失、初始化失败、安装包不是最新、签名/设备信任问题、MediaPipe 初始化错误）。图片/语音等未完成能力只描述具体能力边界，不能把 iOS 平台整体说成不支持。
- Models 页面采用 Gallery 风格单模型卡片，展示模型大小、来源、commit hash、保存路径、能力标签、平台状态、下载速度、剩余时间、暂停/继续/取消/删除/校验。
- iOS 下载主路径改为原生 Swift `URLSessionConfiguration.background`；前台可做 2-4 路 Range 分片加速，后台优先系统托管可靠性，UI 文案明确“前台加速，后台由 iOS 系统托管”。
- Chat 首页未下载时显示“下载并开始”行动卡片，不用 dead-end 支持提示。
- 图片/语音先完成权限、选择、预览和附件状态；runtime 未开启多模态时显示清晰降级提示，不阻塞文字对话。
- Skills 先实现内置/featured/URL/本地导入的 Hub 骨架、启用状态、Prompt 注入和免责声明，再逐步接真实工具调用。

下一步工程顺序：

1. 修复当前 iOS 原生下载编译接入：完整加入 `IOSModelDownloadManager.swift` 到 Xcode target，并修正 `AppDelegate.swift` channel 注册。
2. 通过 `flutter build ios --profile` 并安装 iPhone 验证启动。
3. 打通 iOS `refreshStatus/download/cancel/delete/EventChannel`。
4. 再实现 iOS 前台 Range 多分片与后台系统托管切换策略。
5. 每阶段同步 docs/CLAUDE.md，并在验证通过后提交 GitHub。

验证记录（2026-05-02）：

```text
flutter build ios --profile                         PASS
flutter analyze                                     PASS
flutter test                                        PASS
xcrun devicectl install/launch iPhone              BLOCKED: 指定 UDID 设备当前未连接/未被 CoreDevice 发现
flutter devices                                     仅发现 Android Pixel 8、iOS Simulator、macOS、Chrome；未发现 iPhone 真机
```

本次修复了 iOS 编译阻塞，但还不能声明 iOS 真机后台下载已完成；下一步需要在 iPhone 重新连接后安装 Profile 包并验证下载 channel、后台切换、重启恢复。

追加修复（2026-05-02）：

```text
flutter analyze                                     PASS
flutter build ios --no-codesign                    PASS
```

修复点：iOS runtime 不再使用 Dart Placeholder/占位输出；已新增 `IOSGemmaRuntime.swift` 注册原生 runtime channel，Flutter 侧 iOS 进入 MethodChannel。已按 `google-ai-edge/mediapipe-samples/examples/llm_inference/ios` 的 `MediaPipeTasksGenAI` + `LlmInference.Session.generateResponseAsync()` 路线写出接入方案并尝试集成；当前构建机 Xcode 15.0.1 可编译 app，但链接 MediaPipeTasksGenAI 0.10.35 时缺 Swift 6 runtime 符号，因此真实 iOS 推理还需升级 Xcode 后启用 Podfile 中的依赖。下载侧：iOS `URLSessionDownloadTask` 的 Range 续传不再删除旧 `.gallerytmp` 后把剩余片段当完整文件，HTTP 206 追加、HTTP 200 覆盖重下，并修正进度 offset。还修复 Dart 前台下载兜底的 200+append 坏文件风险。真机下载长时间后台/断网/重启恢复仍需在可用 iPhone 上验证。

追加修复（2026-05-02，升级 Xcode 后继续推进 iOS 真对话）：

```text
xcodebuild -version                              Xcode 26.4.1 / Build 17E202
swift --version                                  Apple Swift 6.3.1
pod install                                      PASS，安装 MediaPipeTasksGenAI 0.10.35 / MediaPipeTasksGenAIC 0.10.35
flutter analyze                                  PASS
flutter test                                     PASS
flutter build ios --no-codesign                 PASS，Runner.app 38.2MB
flutter build ios --release                     PASS，自动签名 Team 6X97AH5URL，Runner.app 38.3MB
devicectl install iPhone                         BLOCKED: 设备安装阶段签名完整性校验失败，Flutter.framework verification failed 0xe8008001
flutter run -d 00008120-000605C42244201E --release --no-resident  BLOCKED: install/launch 阶段失败，需用 Xcode 打开 ios/Runner.xcworkspace 修复设备签名/信任/嵌入 framework 签名
```

本次已完成真实 iOS 对话链路的代码接入与构建验证：

- `ios/Podfile` 正式启用 `pod 'MediaPipeTasksGenAI', '~> 0.10.35'`，不再注释掉 GenAI Pod。
- `ios/Podfile.lock` 记录 `MediaPipeTasksGenAI 0.10.35` 与 `MediaPipeTasksGenAIC 0.10.35`。
- `ios/Runner/IOSGemmaRuntime.swift` 现在持有 `LlmInference` 与 `LlmInference.Session`，`initialize` 在后台队列加载模型，`generate` 用 Swift concurrency Task 调 `generateResponseAsync()` 并通过 EventChannel 流式发 token；`stop/dispose` 取消生成并释放 session/inference。
- `lib/src/core/runtime/platform_gemma_runtime.dart` 已移除旧 iOS “还没有接通 LiteRT-LM iOS 推理引擎”文案。若手机上仍显示该文案，说明安装的是旧包，或新包没有成功覆盖安装。

仍未能声明 iPhone 上已“实际看到 token 输出”，原因不是 iOS runtime 仍是占位，而是当前真机安装被代码签名完整性校验挡住。下一步应优先用 Xcode 打开 `ios/Runner.xcworkspace`，选择已连接 iPhone 与 Team `6X97AH5URL` 执行 Product > Run，让 Xcode 重新修复 Runner/嵌入 framework 签名；安装成功后再下载或确认模型文件存在，发送一条短中文 prompt 验证 `runtime_events` 是否返回真实 token。


追加修复（2026-05-02，iOS 系统后台下载与已下载模型恢复）：

```text
flutter build ios --release                         PASS
flutter run -d 00008120-000605C42244201E --release --no-resident  PASS，安装并启动到 iPhone people
xcrun devicectl device info processes               PASS，Runner.app/Runner 进程存在
```

用户反馈：模型之前已下载完毕，但当前 iOS 仍显示下载失败/无法正常下载，并明确希望使用系统级、支持后台的下载方式。

处理结果：

- iOS 下载主路径确认是 `IOSModelDownloadManager.swift` 的 `URLSessionConfiguration.background(withIdentifier:)`，不是 Dart 前台 HTTP 下载；Flutter 侧 Android/iOS 都优先调用 `com.example.gemma_local_app/model_download` 原生 MethodChannel。
- 增强 `refreshStatus` 与 `download` 前的恢复逻辑：扫描 Application Support、Documents、Caches 中已有的 `gemma-4-E2B-it.litertlm`、小写 `gemma-4-e2b-it.litertlm`、以及 Gallery 风格嵌套目录；如果发现大小达到 `2538766336` 的本地完整模型，会迁移到当前 iOS 标准路径 `{ApplicationSupport}/Gemma_4_E2B_it/{commitHash}/gemma-4-E2B-it.litertlm` 并直接返回 `succeeded`，避免重复下载。
- 如果发现 final 文件存在但大小不足，会转成 `.gallerytmp` 并显示 partiallyDownloaded，后续使用 HTTP Range 续传。
- 如果 `.gallerytmp` 已经完整，会 promote 为正式模型文件。
- 下载仍由 iOS background URLSession 托管，支持 App 切后台后由系统继续调度。

下一步：请在 iPhone 上打开刚安装的 galleryFlutter，进入 Models 点“刷新”。如果之前完整模型仍在当前 App 容器的 Application Support/Documents/Caches 内，应直接识别为已下载；如果旧模型属于被 iOS 卸载后删除的旧容器，则需要重新点下载，但新下载会走系统后台 URLSession。


追加修复（2026-05-02，iOS MissingPluginException down）：

用户反馈 iOS 下载报错：`MissingPluginException no implementation found for method down on channel com.example.gemma_local_app/model_download`。

根因处理：

- Flutter iOS 工程启用了 SceneDelegate，`AppDelegate.didFinishLaunching` 中 `window?.rootViewController` 可能还不是最终 FlutterViewController，导致原生 `model_download` channel 没有注册到当前 messenger，Dart 侧调用时出现 MissingPluginException。
- `SceneDelegate.swift` 已新增 `scene(_:willConnectTo:options:)`，在 FlutterViewController 可用后调用 `AppDelegate.registerFlutterChannels(with:)` 注册 `IOSModelDownloadManager` 与 `IOSGemmaRuntime`。
- `AppDelegate.swift` 增加 `didRegisterFlutterChannels` 防重复注册保护，并保留 AppDelegate 路径注册。
- `IOSModelDownloadManager.swift` 同时兼容 `download` 与用户当前旧包/旧调用里出现的 `down` 方法名，避免 method name 不一致时再次 MissingPluginException。

验证：

```text
flutter build ios --release                                      PASS
flutter run -d 00008120-000605C42244201E --release --no-resident PASS，已安装并启动到 iPhone people
flutter analyze                                                  PASS
flutter test                                                     PASS
```

## 13. 待完成规划

### 13.0 自动工作模式总计划

用户已授权自动工作模式，要求持续推进以下能力，并且每个功能实现、测试后立即同步文档并提交 GitHub：

1. iOS 下载改造为后台下载模式：原生 `URLSessionConfiguration.background`，支持后台继续下载、基础断点续传；多线程/多连接分片作为第二阶段，需兼容 iOS background session 限制。
2. 图片支持：相机拍摄 + 系统图片选择；优先 Android/iOS，macOS/Linux/Windows 先做文件选择或可用降级。
3. 语音支持：录音文件选择 + 实时录音；移动端优先，桌面端可降级到音频文件选择。
4. Skills：参考 Google AI Edge Gallery 的 assets/skills、SkillManager、ToolProvider 机制，构建本地 skills 目录、启用状态和 Skills Hub 雏形。
5. Markdown：文字输入与输出均支持 Markdown 合理渲染，当前已接入 `flutter_markdown`，后续继续优化代码块、主题和复制体验。

详细实施方案已新增：

```text
docs/auto_work_plan.md
```

自动工作规则：

- 每个功能块完成后运行 `flutter analyze`、`flutter test` 和相关平台 build。
- Android/iOS 有设备时安装并启动验证。
- 同步 `CLAUDE.md` 与 `docs/`。
- 每个功能块单独 git commit 并 push 当前 `ios` 分支到 GitHub。

优先级 P0：Android 真推理

- [x] 迁移 LiteRT-LM Android 依赖到 Flutter Android 工程。
- [x] 实现 Android MethodChannel runtime 骨架。
- [x] 用下载后的本地模型路径初始化 `Engine` 的代码路径。
- [x] 创建 `Conversation` 的代码路径。
- [x] 实现文本对话 generate 的 EventChannel 流式返回代码路径。
- [x] 支持 stop/cancel 的代码路径。
- [x] 支持 dispose/cleanup 的代码路径。
- [ ] Android Gradle 编译通过。
- [ ] Android 真机下载模型后完成真实推理验证。
- [ ] Android 真机 Profile/Release 验证。

优先级 P1：输入能力

- [ ] 图片选择器。
- [ ] 图片路径/bytes 传给 Android。
- [ ] Android Bitmap 转换并传给 LiteRT-LM。
- [ ] 音频选择或录音。
- [ ] 音频 bytes 传给 Android。
- [ ] Android ByteArray 输入接入 LiteRT-LM。

优先级 P1：Skills

- [ ] 把原工程 assets/skills 的 SKILL.md 复制/整理到 Flutter assets。
- [ ] 在 `pubspec.yaml` 注册 skills assets。
- [ ] Flutter 侧加载 SKILL.md。
- [ ] 实现 selected/enabled 状态。
- [ ] 实现 `___SKILLS___` 注入。
- [ ] Android ToolProvider 桥接 `load_skill`。
- [ ] Android ToolProvider 桥接 `run_intent` 或 Dart tool 分发。
- [ ] 支持 require_secret。

优先级 P2：模型下载增强

- [ ] 下载文件完整性校验。
- [ ] sha256 或 size 校验。
- [ ] 下载失败重试策略。
- [x] Android 系统下载：DownloadManager + DownloadProvider 系统通知/任务托管。
- [x] Android 断点续传：由系统 DownloadManager 维护 `.gallerytmp/.cfg`，远端支持 `Accept-Ranges: bytes`。
- [x] Android 模型最终路径扁平化为 `/storage/emulated/0/Android/data/com.example.gemma_local_app/files/gemma-4-e2b-it.litertlm`。
- [ ] 下载速度、剩余时间展示优化。

优先级 P2：Prompt Lab

- [ ] 复刻更多原工程 PromptTemplateConfigs。
- [ ] 支持模板参数编辑器。
- [ ] 增加样例 prompt。

优先级 P3：多平台后端

- [ ] iOS 本地后端调研。
- [ ] macOS 本地后端调研。
- [ ] Windows 本地后端调研。
- [ ] Linux 本地后端调研。
- [ ] 保持 Flutter `LocalGemmaRuntime` 接口不变。

## 14. 当前验证记录

### 14.1 Android 真机优先验证顺序

用户明确要求严格按平台顺序验证：

1. Android 真机先测试。
2. Android 可以稳定工作后，再测试 iOS 真机。
3. iOS 稳定后，再测试 macOS / Windows / Linux。

当前不能跳到 iOS/macOS/Windows/Linux。

### 14.2 Android 真机启动验证

设备：

```text
Pixel 8 • 37101FDJH0077P • android-arm64 • Android 16 API 36
```

已执行：

```bash
cd /Users/sanbo/Desktop/gallery/gemma_local_app
flutter build apk --debug
adb -s 37101FDJH0077P install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s 37101FDJH0077P shell monkey -p com.example.gemma_local_app -c android.intent.category.LAUNCHER 1
adb -s 37101FDJH0077P shell pidof com.example.gemma_local_app
adb -s 37101FDJH0077P logcat -d -t 300 | grep -E "GemmaLiteRtRuntime|gemma_local_app|FATAL EXCEPTION|AndroidRuntime" | tail -120
```

结果：

```text
Install Success
Displayed com.example.gemma_local_app/.MainActivity
Fully drawn com.example.gemma_local_app/.MainActivity
pid: 31382
未发现 FATAL EXCEPTION / AndroidRuntime 崩溃日志
```

结论：Android 真机 Debug APK 已可安装并启动，当前只验证到 App 启动稳定；尚未验证模型下载完成后的真实 LiteRT-LM 推理。下一步仍必须继续 Android 真机：下载 Gemma-4-E2B-it，触发 initialize/generate，检查 GemmaLiteRtRuntime 日志和模型输出。

### 14.3 iOS 真机 Profile 安装验证

设备：

```text
people • 00008120-000605C42244201E • iPhone 14 Pro Max • iOS 18.3.2
```

已执行：

```bash
cd /Users/sanbo/Desktop/gallery/gemma_local_app
git switch -c ios
flutter analyze
flutter test
flutter build ios --profile
xcrun devicectl device install app --device 00008120-000605C42244201E build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device 00008120-000605C42244201E com.example.gemmaLocalApp
```

结果：

```text
flutter analyze: No issues found
flutter test: All tests passed
flutter build ios --profile: Built build/ios/iphoneos/Runner.app
install: App installed, bundleID com.example.gemmaLocalApp
launch: RequestDenied / Security
Unable to launch com.example.gemmaLocalApp because it has an invalid code signature, inadequate entitlements or its profile has not been explicitly trusted by the user.
```

结论：iOS Profile 包已成功构建并安装到物理 iPhone，但首次启动被 iOS 系统拦截。需要在 iPhone 上手动信任开发者证书/描述文件后再重新执行 `devicectl process launch` 做进程存活和 crash log 验证。该状态不是 Dart/Flutter 页面崩溃。

### 14.4 常规工程验证

最近一次常规验证命令：

```bash
cd /Users/sanbo/Desktop/gallery/gemma_local_app
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

结果：

```text
Formatted lib/src/features/gemma_home/gemma_home_screen.dart
Formatted lib/src/features/models/model_download_service.dart
Formatted lib/src/features/models/models_drawer.dart
Formatted 11 files (3 changed) in 0.03 seconds.
Analyzing gemma_local_app...
No issues found! (ran in 2.1s)
00:00 +0: loading /Users/sanbo/Desktop/gallery/gemma_local_app/test/widget_test.dart
00:00 +0: Gemma Local smoke test
00:00 +1: All tests passed!
```

每次修改后至少运行：

```bash
dart format lib test
flutter analyze
dart --disable-dart-dev --packages=.dart_tool/package_config.json tool/check_prompt_and_skills.dart
flutter test
```

## 15. 开发规范和注意事项

### 15.1 Dart import 规则

对于跨 feature 引用，优先使用清晰路径；若路径变深，建议改为 package import：

```dart
import 'package:gemma_local_app/src/core/model/gemma_model_config.dart';
```

避免过深相对路径造成 analyzer 解析问题。

### 15.2 不要引入多模型

本项目明确只使用 `Gemma-4-E2B-it`。不要把原工程整个 model allowlist 搬过来作为运行列表。

### 15.3 模型不打包进 App

模型必须通过侧边 `设置 > Models` 下载。

不要把 `.litertlm` 加入 Flutter assets。

### 15.4 下载临时文件规则

保持与原工程一致：

```text
{modelFile}.gallerytmp
```

Android 并发分片下载额外使用：

```text
{modelFile}.gallerytmp.part0
{modelFile}.gallerytmp.part1
...
```

临时文件或 part 文件存在时，使用 HTTP Range 继续下载。part 续传规则是：根据该 part 文件已有长度，从 `partStart + existingBytes` 继续请求到 `partEnd`。

下载完成后，Android 先把所有 part 合并为 `.gallerytmp`，再 rename 为正式文件；非 Android 单流下载直接把 `.gallerytmp` rename 为正式文件。

### 15.5 iOS 真机验证注意

如果后续验证 iOS 真机，不要用 Debug 从手机桌面启动作为是否可独立运行的依据。应使用 Release/Profile 包验证。

推荐模式：

```bash
flutter build ios --release
xcrun devicectl device install app --device <UDID> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device <UDID> <bundle_id>
```

并检查进程是否持续存活和 crash logs。

### 15.6 文档同步要求

后续所有重大变化必须更新本文件：

```text
/Users/sanbo/Desktop/gallery/gemma_local_app/CLAUDE.md
```

如保留 docs 目录，也要同步更新相关 docs。

## 16. 2026-05-04 起推荐推进队列

当前总体原则：**Gemma 本地模型是本项目所有能力的基础；文字对话和图片识别已经是移动端高质量体验的主闭环；audio / skills 的推进不能破坏这两条链路。** 每推进一项都要先记录事实、再小步验证。若某方向确认必须改用非 Gemma 方案作为主要能力来源，则不再作为本项目内的核心验证目标继续深测。

### 16.1 P0：状态对齐与回归保护

1. 统一文档事实：
   - `CLAUDE.md` 作为进展和待办主文件。
   - `docs/` 作为具体实现方案文件。
   - 如果代码事实和文档冲突，以当前代码与真机验证结果为准，随后修正文档。
2. 修正已过期条目：
   - Android `Engine` / `Conversation` 已接入，不再列为未实现。
   - iOS `audio_input` channel 已有文件选择/录音/播放骨架，但音频理解 runtime 当前主动关闭。
   - iOS audio 当前真实 blocker 是 `flutter_gemma + Gemma-4-E2B-it` 音频请求触发 `Failed to start streaming (code: 13)`。
3. 建立回归基线：
   - Android：文字首轮、连续多轮、图片识别、图片后继续文字。
   - iOS：文字首轮、连续多轮、图片连续识别、图片后继续文字。
   - 每次 audio / skills 改动后至少运行 `flutter analyze`，并优先做移动端文字/图片 smoke test。

### 16.2 P0：iOS audio 基础能力先补齐，不直接冒险打开 runtime

1. `IOSAudioInput.swift`：
   - 文件选择后统一转换为 16k / mono / 16-bit PCM WAV。
   - 录音继续保持 16k / mono / 16-bit PCM WAV，单段上限 30 秒。
   - 增加 `com.example.gemma_local_app/audio_input_events`，输出 recording started/stopped/cancelled 和录音电平。
   - 增加 WAV header / 时长 / 文件大小校验，避免把不可用音频送进 runtime。
2. `platform_gemma_runtime.dart`：
   - 当前继续拦截 iOS `audioPaths`。
   - 后续增加一个固定 WAV harness，只在专项验证通过后再考虑打开 `Message.withAudio(...)`。
3. 如果 `Message.withAudio(...)` 仍触发 code 13：
   - 先记录为 Gemma iOS audio runtime blocker，并暂停把 iOS audio 作为本项目核心能力继续深测。
   - 独立 iOS ASR -> Gemma 文本对话只能作为外部降级/另项目方案评估，不能算作本项目的 audio 能力成功路径。
   - UI 文案必须说明这是非 Gemma audio modality 的降级能力，不能误导为 Gemma 原生语音理解。

### 16.3 P0：Android audio 专项验证

1. 对齐 Google AI Edge Gallery：
   - `MAX_AUDIO_CLIP_COUNT = 1`。
   - `MAX_AUDIO_CLIP_DURATION_SEC = 30`。
   - `SAMPLE_RATE = 16000`。
   - `EngineConfig.audioBackend = Backend.CPU()`。
   - 内容顺序为 `Content.ImageBytes`、`Content.AudioBytes`、`Content.Text`。
2. 真机覆盖：
   - 应用内录音。
   - 标准 wav。
   - m4a。
   - mp3。
   - 微信/浏览器/第三方 App 导出的音频。
3. 若出现 `Status Code: 12/13`：
   - 记录 backend、header、采样率、声道、时长、bytes。
   - 与 Gallery `ChatMessageAudioClip.genByteArrayForWav()` 输出做 byte-level 对比。
   - 必要时只保留 raw PCM，在发送前按 Gallery 方式加 WAV header。

### 16.4 P1：Live 语音通话

1. Android 先稳定：
   - 静音切段。
   - 队列背压。
   - 停止/中断后的状态恢复。
   - 片段失败重试和“重新发送语音”。
2. iOS 等 Gemma audio runtime 路径验证稳定后再打开；非 Gemma ASR 不能作为本项目 Live 语音成功路径。
3. TTS 放到后续阶段，不阻塞“语音输入可用”。

### 16.5 P1：Skills / Agent Chat

1. 从 `/Users/sanbo/Desktop/gallery/Android/src/app/src/main/assets/skills/*/SKILL.md` 整理内置 skills 到 Flutter assets 或 App Support。
2. 做 Skills Hub：
   - 内置 skills。
   - 启用/禁用。
   - 本地导入。
   - URL 导入预留。
   - secret/API key 管理。
   - 第三方 skill 安全提示。
3. Android runtime 接 Gallery 同款工具机制：
   - `ToolProvider` / `ToolSet`。
   - `load_skill`。
   - `run_intent`。
   - 后续再接 JS skill。
4. iOS / Flutter 侧处理 `FunctionCallResponse`：
   - 解析 function call。
   - 分发到 Dart/platform tool executor。
   - 把 tool result 回传模型或展示给用户。

### 16.6 当前执行顺序

本轮开始按以下顺序推进：

1. 更新 `CLAUDE.md` 与 `docs/` 中过期状态。
2. 给 iOS audio input 补格式归一化和 event channel，但保持 iOS audio runtime 关闭。
3. 跑 `flutter analyze`。
4. 再进入 Android audio 多来源真机验证与修正。
5. 最后做 Skills 工具桥接。

### 16.7 本轮推进记录（2026-05-04）

已完成：

1. 更新 `CLAUDE.md`、`docs/progress.md`、`docs/audio_voice_live_design.md`、`docs/feature_mapping.md`，对齐当前真实状态：
   - Android `Engine` / `Conversation` 已接入。
   - Android audio runtime 已按 Gallery 路线重新接入，但待多来源真机验证。
   - iOS audio runtime 因 `Failed to start streaming (code: 13)` 继续关闭。
   - Skills 当前仍是 prompt 占位，尚未接 Gallery `load_skill` / `run_intent` 工具桥接。
2. 推进 iOS audio input 基础能力：
   - `IOSAudioInput.swift` 注册 `com.example.gemma_local_app/audio_input_events`。
   - 录音开始/停止/取消会发 recording event。
   - 录音中按约 120ms 输出电平 event，供后续 Live/VAD 使用。
   - 文件选择音频会通过 `AVAudioFile` + `AVAudioConverter` 转成 16k / mono / 16-bit PCM WAV。
   - 录音和文件选择结果会做 RIFF/WAVE、PCM、采样率、声道、bit depth、30 秒上限校验。
3. 验证：
   - `flutter analyze`：通过。
   - `flutter build ios --no-codesign`：通过，输出 `build/ios/iphoneos/Runner.app`。
   - `flutter test --no-pub`：未通过，失败点是 macOS native asset `libGemmaModelConstraintProvider.dylib` 执行 `install_name_tool` 时 load command 空间不足；这是当前测试宿主/Native Assets 链路问题，不是本轮 iOS Swift 编译错误。后续需要单独处理 macOS native asset relink/headerpad 或改用移动端 smoke test 作为本轮主验收。

仍未打开：

- iOS `Message.withAudio(...)` runtime 仍保持关闭；下一步必须先做固定 WAV harness。若仍确认 code 13，则记录为 Gemma iOS audio blocker 并暂停本项目内深测，不用非 Gemma ASR 方案替代验收。

### 16.8 本轮质量复查与补强（2026-05-04）

本轮按用户要求重点复查：文字对话、图片对话、Android audio。结论：文字/图片主链路保持可编译；Android audio 还缺真机设备验证，但静态链路和构建已补强。

已完成：

1. 文字/Skills prompt 质量补强：
   - 发现 Android `generate` 调用虽然把 `systemPrompt` / `enabledSkillNames` 传给 MethodChannel，但 Kotlin `generate(...)` 当前没有消费这些字段；这会导致 Android Skills/system 指令实际不进入模型上下文。
   - 已在 Dart `MethodChannelGemmaRuntime` 侧统一构造 contextual prompt：system instructions、enabled skills 与用户请求一起进入 Android prompt，避免 Android 文字/Skills 质量被空转。
   - iOS 文字路径同步复用同一 contextual prompt 逻辑，保持平台一致。
2. 图片对话质量补强：
   - Android 现在也会像 iOS 一样，对图片请求使用明确视觉指令：要求以图片为主要证据、按系统语言回答、默认图片 prompt 时描述主要物体/场景/文字/细节。
   - 图片 + 音频同时存在时，prompt 会明确要求同时利用 image/audio 作为证据，避免模型只按普通文本聊天。
3. Android audio 质量补强：
   - 音频请求进入 Android runtime 前会补明确 audio prompt：要求识别语音/声音/数字/姓名/关键信息；不清楚时说明不确定点。
   - Android 录音达到 30 秒上限时，原生 event 会带 `reason=maxDuration`；Flutter 收到后自动调用 `stopRecording()` 并把录音附件回填到输入框，避免原生已停止但 UI 仍显示录音中、且录音文件没有附着的问题。
   - Android 系统音频选择补 `FLAG_GRANT_READ_URI_PERMISSION`；对返回 UNKNOWN_LENGTH 的 DocumentProvider 音频，先复制到 cache 临时文件再交给 `MediaExtractor`，避免部分云盘/文件管理器 URI 因负 length 不能解码。
4. 多模态/Live 边界补强：
   - 纯图片、纯音频、图片+音频三种无文字输入分别使用不同默认 prompt；图片+音频不会再误用“请描述这张图片”而忽略音频。
   - Live 语音每段推理增加错误隔离：单段 PlatformException 不再直接杀掉后台 processor；如果 audio runtime 不可用则停止 Live 并给出明确错误，避免后台循环持续失败。

验证记录：

- `flutter analyze`：通过。
- `flutter build apk --debug`：通过，输出 `build/app/outputs/flutter-apk/app-debug.apk`。
- `cd android && ./gradlew :app:lintDebug`：通过；只有既有 Gradle/插件 deprecated/experimental 警告。
- `flutter build ios --no-codesign`：通过，输出 `build/ios/iphoneos/Runner.app`。
- 第二轮补强后再次运行 `flutter analyze`、`flutter build apk --debug`、`cd android && ./gradlew :app:lintDebug`、`flutter build ios --no-codesign`：均通过。
- `flutter test --no-pub`：仍未通过，失败点仍是 macOS native asset `libGemmaModelConstraintProvider.dylib` 的 `install_name_tool` load command/headerpad 问题；与本轮 Dart/Kotlin 补强无关。
- `adb devices`：当前无 Android 设备连接，因此 Android audio 的模型真实理解仍需要接真机/模拟器后覆盖录音、wav、m4a、mp3、多来源导出音频。

继续待做：

1. Android 真机专项：安装 debug/release 包，下载或复用模型后逐项验证文字、图片、录音、wav/m4a/mp3 audio。
2. 若 Android audio 出现 LiteRT-LM `Status Code: 12/13`，记录 backend、WAV header、采样率、声道、bit depth、时长、bytes，并与 Gallery `ChatMessageAudioClip.genByteArrayForWav()` 做 byte-level 对比。
3. iOS audio runtime 仍不打开；只能继续固定 WAV harness 验证 Gemma 原生 audio，不能用非 Gemma ASR 当作本项目成功路径。

### 16.9 第三轮复查补强（2026-05-04）

继续按“文字对话 / 图片对话 / Android audio / Skills 诚实边界”复查后，又补了三个质量缺口：

1. Prompt Lab：
   - 发现 `Rewrite tone`、`Summarize text`、`Code snippet` 模板把 `\$input` 字面量发给 Gemma，没有真实插入用户输入。
   - 已修复为真正插入用户文本，并新增 `test/prompt_and_skills_test.dart` 覆盖模板不能包含字面量 `\$input`。
2. Skills prompt：
   - 发现当前只传 `enabledSkillNames`，Gemma 实际只知道技能名，不知道 Gallery skill 的说明/工具调用意图。
   - 已把内置 skills 对齐 `/Users/sanbo/Desktop/gallery/Android/src/app/src/main/assets/skills/*/SKILL.md` 的名称、说明和 `run_js` / `run_intent` 调用要求。
   - 新增 `buildAgentSkillsSystemPrompt(...)`，发送请求时把选中 skills 的 description/instructions 注入 system prompt。
   - 重要边界：当前 Flutter app 的原生 `ToolProvider` dispatch 尚未接通，所以 prompt 明确要求 Gemma 不得伪装已经执行 `run_js` / `run_intent`；只能输出预期 tool call payload，并说明等待原生 Skills 桥接。这样保证本地 Gemma 仍是能力基础，同时不产生假执行结果。
3. 语音波形 / Live 静音判断：
   - Android 与 iOS 的语音卡片波形估算此前直接统计整个 WAV 文件字节，RIFF/WAVE header 会污染音量估算。
   - 已改为解析 WAV `data` chunk 的 16-bit PCM sample 后再分桶估算振幅；这会让静音检测、Live 切段和 UI 波形更接近真实音量。

第三轮验证：

- `flutter analyze`：通过。
- `flutter build apk --debug`：通过，输出 `build/app/outputs/flutter-apk/app-debug.apk`。
- `cd android && ./gradlew :app:lintDebug`：通过；仍只有既有 Gradle/插件 deprecated/experimental 警告。
- `flutter build ios --no-codesign`：通过，输出 `build/ios/iphoneos/Runner.app`。
- `git diff --check`：通过。
- `dart --disable-dart-dev --packages=.dart_tool/package_config.json tool/check_prompt_and_skills.dart`：通过，用来绕开当前 macOS native asset hook，直接验证 Prompt Lab 插值和 Skills prompt 内容。
- `flutter test --no-pub test/prompt_and_skills_test.dart`：仍被 macOS native asset `libGemmaModelConstraintProvider.dylib` 的 `install_name_tool` headerpad/load command 问题阻断；这不是新增测试逻辑失败。后续需要单独修 macOS native asset relink/headerpad，或继续用移动端 build/smoke 作为当前主验收。
- Android AVD 33 本轮尝试启动用于复测录音，但 emulator 进程在 adb online 前退出，`adb devices` 无 Android 设备；因此本轮无法新增 Android 设备 smoke，Android audio 的 Gemma 真实理解仍待真机/可用 emulator + 模型文件验证。

### 16.10 Skills Hub / 线上 Skills 第一阶段（2026-05-04）

根据用户补充“Skills 最好支持 Skills Hub，类似 `https://skillhub.cn/`，希望支持线上 skills”，本轮继续推进 Skills Hub 第一阶段。核心原则仍然不变：Gemma 是本地大模型基础；线上 skill 只是给 Gemma 提供可加载 instructions / tool schema / 本地工具执行入口，不能变成云端模型替代。

已完成：

1. Flutter Skills Hub UI：
   - 点击 composer 的 `Skills` 按钮不再只是简单 toggle，而是打开 `Skills Hub` bottom sheet。
   - Hub 中可统一启用/关闭 Skills 模式。
   - 可查看内置 skills 与线上导入 skills。
   - 每个 skill 可单独启用/禁用。
   - 线上 skill 可删除。
2. SkillHub.cn / 线上入口：
   - Hub 面板提供 `https://skillhub.cn/` 链接复制，作为线上 skills 社区入口。
   - 当前未新增 `url_launcher` 依赖，因此先不直接拉起外部浏览器；用户可复制链接或粘贴具体 Skill URL。
3. 线上 Skill 导入：
   - 新增 `lib/src/features/skills/skill_repository.dart`。
   - 支持粘贴：
     - 直接 `SKILL.md` URL。
     - GitHub `blob/.../SKILL.md` URL，会自动转换 raw。
     - GitHub raw URL。
     - 包含 `SKILL.md` 链接的 HTML 页面，会尝试提取第一个 `SKILL.md` 链接再下载。
   - 下载大小限制 512KB。
   - 解析 `--- name / description ---` front matter。
   - 校验 skill name：`[a-zA-Z0-9][a-zA-Z0-9._-]{1,63}`。
   - 线上 skills 持久化到 Application Support 的 `online_skills.json`。
4. Runtime 请求结构：
   - `GemmaRequest` 新增 `enabledSkillDetails`，把 name / description / instructions / sourceUrl 送入 runtime。
   - Dart system prompt 继续注入选中 skill 的详细 instructions，保证 iOS 与 Android 至少都能让 Gemma 读到线上 skill 内容。
5. Android ToolProvider 第一阶段：
   - Android Skills 模式初始化时启用 `ConversationConfig.tools = listOf(tool(GemmaSkillToolSet(...)))`。
   - Skills 模式启用 constrained decoding：`ExperimentalFlags.enableConversationConstrainedDecoding = true`。
   - `loadSkill(skillName)`：可返回内置/线上 skill 的完整 instructions。
   - `runJs(skillName, scriptName, data)`：当前 JS/WebView sandbox 尚未接通，返回 `pending_bridge`，明确告诉模型不要声称已执行。
   - `runIntent(intent, parameters)`：第一阶段接 `send_email`，通过 Android `ACTION_SENDTO mailto:` 拉起邮件 App。

验证：

- `dart --disable-dart-dev --packages=.dart_tool/package_config.json tool/check_prompt_and_skills.dart`：通过。
- `flutter analyze`：通过。
- `flutter build apk --debug`：通过，输出 `build/app/outputs/flutter-apk/app-debug.apk`。
- `cd android && ./gradlew :app:lintDebug`：通过；仍只有既有 Gradle/插件 deprecated/experimental 警告。
- `flutter build ios --no-codesign`：通过，输出 `build/ios/iphoneos/Runner.app`。
- `git diff --check`：通过。

仍待做：

1. Skills Hub 深化：
   - 如果 SkillHub.cn 提供稳定 API，再接目录浏览、搜索、分页、评分/来源信息。
   - 增加来源信任提示、hash/签名校验、更新检查。
2. `run_js` 真执行：
   - 参考 Gallery `CallJsAgentAction` / local webview sandbox。
   - 支持 JS skill 输出 result / image / webview。
   - 支持 secret/API key 本地保存与授权弹窗。
3. iOS / Dart tool dispatch：
   - 解析 `flutter_gemma FunctionCallResponse`。
   - 分发到 Dart/platform tool executor。
   - 把 tool result 回传模型或至少在 UI 中结构化展示。
4. 真机验证：
   - Android：Skills Hub 导入线上 skill、loadSkill 调用、send_email intent、run_js pending_bridge 行为。
   - iOS：线上 skill prompt 注入与 FunctionCallResponse 展示。

### 16.11 Android bundled `run_js` 本地 WebView sandbox（2026-05-04）

在已推送 GitHub checkpoint 后，继续推进 Skills 的下一项：把 Android built-in `run_js` 从 `pending_bridge` 提升为本地执行。

已完成：

1. 参考 Gallery `AgentTools.runJs` / `AgentChatScreen`：
   - 把 `/Users/sanbo/Desktop/gallery/Android/src/app/src/main/assets/skills` 中的 built-in skill assets 复制到 `android/app/src/main/assets/skills`。
   - 新增 `AndroidSkillJsExecutor`：在 Android 主线程创建临时 headless `WebView`，加载 `file:///android_asset/skills/<skill>/scripts/<script>.html`。
   - 通过 `JavascriptInterface AiEdgeGallery.onResultReady(...)` 接收 `ai_edge_gallery_get_result(data, secret)` 的返回。
   - 增加 30 秒执行超时、asset path 校验、脚本名禁止 `..` / 绝对路径 / 非 `.html`，避免任意文件访问。
2. `GemmaSkillToolSet.runJs(...)`：
   - 对 enabled skill 做校验。
   - bundled built-in asset 存在时真实执行 JS。
   - 解析 JSON 结果：`error` -> failed；`result` -> succeeded；`image` 会保存到 Android cache 并通过 runtime event 附着到 assistant 气泡；`webview` 目前返回诚实文字说明 UI 展示桥接仍待接入，不伪装 Flutter 已显示。
3. Android manifest 增加 `INTERNET`，让 query-wikipedia / qr-code 这类需要网络资源的 bundled JS 能按原 Gallery 语义请求网络。
4. Dart Skills system prompt 同步更新：Android 支持 `loadSkill` / `run_intent(send_email)` / bundled built-in `run_js`，iOS/Dart tool-result dispatch 仍明确标为在建。

验证：

- `dart --disable-dart-dev --packages=.dart_tool/package_config.json tool/check_prompt_and_skills.dart`：通过。
- `flutter analyze`：通过。
- `flutter build apk --debug`：通过，输出 `build/app/outputs/flutter-apk/app-debug.apk`。
- `cd android && ./gradlew :app:lintDebug`：通过；仍只有既有 Gradle/插件 deprecated/experimental 警告。
- `flutter build ios --no-codesign`：通过，输出 `build/ios/iphoneos/Runner.app`。

仍待做：

1. Android 真机用本地模型触发 `calculate-hash` / `query-wikipedia` / `qr-code` / `mood-tracker`，验证 ToolProvider 是否会稳定调用 `runJs` 并把结果回到 Gemma。
2. Flutter UI 继续深化 JS result 展示：Android image 已可附着到 assistant 气泡；webview 仍需原生/Flutter 展示。
3. 线上/custom skill 不能只保存 `SKILL.md`；要继续下载/校验 sibling `scripts/` 与 `assets/`，再纳入 sandbox 执行。
4. Secret/API key 授权弹窗和本地保存仍未接。

### 16.12 iOS/Dart Skills tool loop 第一阶段（2026-05-04）

继续推进 iOS/Flutter 侧 Skills 诚实工具链，避免 iOS 只把 `FunctionCallResponse` 裸文本展示给用户。

已完成：

1. `platform_gemma_runtime.dart` 在 iOS Skills 模式下为 `flutter_gemma` `createChat(...)` 注册 `loadSkill` / `runJs` / `runIntent` tools，并启用 `supportsFunctionCalls` / `ToolChoice.auto`。
2. iOS 文本/图片生成循环现在会处理 `FunctionCallResponse` / `ParallelFunctionCallResponse`：
   - `loadSkill`：从 `GemmaRequest.enabledSkillDetails` 查找当前启用 skill，返回 `skill_instructions`，通过 `Message.toolResponse(...)` 回传模型，然后继续生成。
   - `runJs`：返回 `pending_bridge`，明确 iOS/Dart JS 执行尚未接通。
   - `runIntent`：返回 `pending_bridge`，明确 iOS/Dart platform intent 尚未接通。
3. 最多允许 3 轮 tool response 循环，避免模型反复调用未接工具导致无限生成。

验证：

- `dart --disable-dart-dev --packages=.dart_tool/package_config.json tool/check_prompt_and_skills.dart`：通过。
- `flutter analyze`：通过。
- `flutter build ios --no-codesign`：通过，输出 `build/ios/iphoneos/Runner.app`。
- `flutter build apk --debug`：通过，输出 `build/app/outputs/flutter-apk/app-debug.apk`。

仍待做：

1. iOS 真机触发 Skills 模式下的 `loadSkill` function call，验证 tool response 能稳定回到 Gemma 并生成最终答复。
2. iOS/Dart 真正执行 `run_js` / `run_intent`，或把这些明确保留为 Android-only capability。
3. Flutter UI 结构化展示 tool call / tool result，而不是只追加 `[tool:name] status` 文本。

### 16.13 Android Skills image result 展示闭环（2026-05-04）

继续补齐 `run_js` 的用户可见结果质量，避免 QR code 等 skill 只把 image 结果变成文字。

已完成：

1. Android `GemmaSkillToolSet.runJs(...)` 解析 JS 返回的 `image.base64`：
   - 支持 `data:image/png/jpeg/webp;base64,...` 和裸 base64。
   - 保存到 `context.cacheDir/skill_<name>_<timestamp>.<ext>`。
   - tool response 中保留 `image_path`，同时通过 runtime `EventChannel` 发送 `tool_result` event。
2. Dart runtime `platform_gemma_runtime.dart` 处理 `tool_result` event：
   - 将 skill result 文本追加到 streaming assistant。
   - 使用内部 marker `[[skill_image:<path>]]` 把 Android cache 图片路径送到 UI。
3. Home UI `_appendAssistantText(...)` 会移除 marker，并把图片路径加入当前 assistant message 的 `imagePaths`，复用现有图片缩略图/全屏预览组件展示结果图。
4. `webview_url` 当前仍以文字展示，不伪装已经嵌入渲染。

验证：

- `dart --disable-dart-dev --packages=.dart_tool/package_config.json tool/check_prompt_and_skills.dart`：通过。
- `flutter analyze`：通过。
- `flutter build apk --debug`：通过，输出 `build/app/outputs/flutter-apk/app-debug.apk`。
- `cd android && ./gradlew :app:lintDebug`：通过；仍只有既有 Gradle/插件 deprecated/experimental 警告。
- `flutter build ios --no-codesign`：通过，输出 `build/ios/iphoneos/Runner.app`。

仍待做：

1. Android 真机触发 `qr-code` skill，确认 WebView 产出的 PNG 能真实显示在 assistant 气泡。
2. Webview result 的 Flutter/Android 展示卡片。
3. image cache 清理策略，避免长期积累。

### 16.14 SkillHub.cn 公开目录浏览/搜索第一阶段（2026-05-04）

根据用户要求“Skills 最好可以支持 Skills Hub，类似 `https://skillhub.cn/`，希望可以支持线上的 skills”，在已完成粘贴 URL 导入之后，继续接入 SkillHub.cn 公开目录。

核心边界仍不变：Gemma-4-E2B-it 是本项目所有能力的本地模型基础；线上 skill 只能提供 instructions / tool 意图，不能把执行基础替换成云端模型，也不能把未审查的远端脚本当成本地能力直接执行。

已完成：

1. 从 SkillHub 前端 bundle 和线上响应确认当前公开 API：
   - `https://api.skillhub.cn/api/skills?page=<page>&pageSize=<size>&keyword=<keyword>`：公开目录/搜索。
   - `https://api.skillhub.cn/api/v1/skills/{slug}/files`：文件清单，包含 `path` / `sha256` / `size`。
   - `https://api.skillhub.cn/api/v1/skills/{slug}/file?path=SKILL.md`：读取单个 `SKILL.md`。
2. `SkillRepository` 增加：
   - `searchSkillHub(...)`：解析公开目录、total、slug、name、description、owner、category、version、downloads、stars、requires_api_key。
   - `importSkillHubSkill(slug)`：校验 slug，读取文件清单，确认存在 `SKILL.md` 且不超过 512KB，然后只下载 `SKILL.md` 并复用现有 Markdown/front matter parser。
   - Repository 支持注入 `http.Client` / API base，便于后续测试与 mock。
3. `Skills Hub` 面板增加“浏览 SkillHub 公开目录”卡片：
   - 打开 Hub 时自动加载热门目录。
   - 支持关键词搜索。
   - 展示 owner/category/version/downloads/stars/API-key 标记。
   - 点击“导入”后保存到 Application Support `online_skills.json`、自动启用 Skills 模式和该 skill。
4. 明确安全边界：
   - 当前只导入远端 `SKILL.md` instructions 给本地 Gemma。
   - 不下载、不执行远端 `scripts/` / `assets/`。
   - 需要 API key 的 skill 只显示提示，不自动索取或保存密钥。

验证：

- `https://api.skillhub.cn/api/skills?page=1&pageSize=3&keyword=vetter`：HTTP 200，返回公开目录 JSON。
- `https://api.skillhub.cn/api/v1/skills/skill-vetter/files`：HTTP 200，返回 `SKILL.md` 与 sha256/size。
- `https://api.skillhub.cn/api/v1/skills/skill-vetter/file?path=SKILL.md`：HTTP 200，返回 markdown。
- `dart --disable-dart-dev --packages=.dart_tool/package_config.json tool/check_prompt_and_skills.dart`：通过。
- `flutter analyze`：通过。
- `flutter build apk --debug`：通过，输出 `build/app/outputs/flutter-apk/app-debug.apk`。
- `cd android && ./gradlew :app:lintDebug`：通过；仍只有既有 Gradle/插件 deprecated/experimental 警告。
- `flutter build ios --no-codesign`：通过，输出 `build/ios/iphoneos/Runner.app`。

仍待做：

1. SkillHub 分页加载更多、排序、分类筛选、详情页/版本列表。
2. 对 `/files` 返回的 `sha256` 做下载后完整性校验；当前只记录远端 API 暴露了 sha256，尚未验证本地内容 hash。
3. 线上/custom skill 的 sibling `scripts/` / `assets/` 下载、大小限制、路径校验、hash/签名校验、信任 UI 和 sandbox 执行策略。
4. 需要 API key / secret 的 skill 授权弹窗和本地密钥保存策略。
5. Android/iOS 真机验证目录搜索、导入、Gemma prompt 注入和最终回答质量。


### 16.15 Android audio 历史修正记录（2026-05-04，已被 20.3 更新）

继续按用户要求复查 Android audio 与 iOS audio blocker，重点对齐 `/Users/sanbo/Desktop/gallery/Android` 的实际 Ask Audio 输入路径。

已完成：

1. Android `Content.AudioBytes` 输入修正：
   - 该小节当时对 Gallery 的理解不完整，已被 2026-05-14 的 20.3 纠正：Gallery 的 `genByteArrayForWav()` 是 raw PCM + 44 字节 WAV header 后传 `Content.AudioBytes`。当前 `MainActivity.readAudioForGemma(...)` 会解析输入 WAV、按需转 mono/resample/trim，然后重新构造完整 16k mono 16-bit PCM WAV bytes 传给模型。
2. iOS 固定 WAV probe：
   - 默认行为不变：iOS 语音文件、实时录音、Live 入口继续关闭，避免普通用户撞到 `Failed to start streaming (code: 13)`。
   - 新增 `GEMMA_IOS_AUDIO_PROBE` dart-define：只有使用 `--dart-define=GEMMA_IOS_AUDIO_PROBE=true` 构建时，iOS UI 才允许语音入口。
   - iOS runtime 会校验 16kHz / mono / 16-bit PCM WAV、30 秒上限，并保留完整 WAV bytes 走 `LiteRtLmFfiClient.chatRaw(audioBytes: ...)`。
3. 继续保持项目根因边界：不能用非 Gemma ASR 把 iOS audio “做成可用”来冒充 Gemma 原生语音理解。

验证：

- `dart --disable-dart-dev --packages=.dart_tool/package_config.json tool/check_prompt_and_skills.dart`：通过。
- `flutter analyze`：通过。
- `flutter build apk --debug`：通过，输出 `build/app/outputs/flutter-apk/app-debug.apk`。
- `cd android && ./gradlew :app:lintDebug`：通过；仍只有既有 Gradle/插件 deprecated/experimental 警告。
- `flutter build ios --no-codesign --dart-define=GEMMA_IOS_AUDIO_PROBE=true`：通过，输出 `build/ios/iphoneos/Runner.app`。
- `flutter test --no-pub`：未通过，仍卡在既有 macOS native asset `libGemmaModelConstraintProvider.dylib` 的 `install_name_tool` headerpad/load command 问题；不是本次 Android/iOS audio 变更引入。

仍待做：

1. Android 真机继续专项验证录音、WAV、m4a、mp3、多来源导出音频，确认完整 WAV 输入后的 Gemma 理解质量。
2. iOS 真机在线后跑固定 WAV / 录音专项；如果仍 code 13，则把它记录为 Gemma iOS audio runtime blocker 并暂停本项目内 iOS audio 深测。
3. 如果 iOS 真机验证仍不稳定，再决定是否把默认 UI 降为实验入口；否则保持当前实现但诚实提示风险。

### 16.16 Flutter test 短 build-dir 闸口恢复（2026-05-04）

根因复查：

- `flutter test --no-pub` 不是 Dart 测试逻辑失败，而是 Flutter tester 在 macOS Native Assets 安装阶段会把 dylib install name 改成绝对路径：
  `.../build/native_assets/macos/libGemmaModelConstraintProvider.dylib`。
- `flutter_gemma 0.14.1` 下载的 `libGemmaModelConstraintProvider.dylib` 没有足够 Mach-O load command/headerpad 空间，长路径写入时 `install_name_tool` 报：
  `larger updated load commands do not fit`。
- 直接重链/替换上游 prebuilt 不适合本轮低风险修改；当前项目核心目标是 Android/iOS Gemma 能力验证，macOS tester 只作为本地质量闸口。

已完成：

1. 新增 `tool/flutter_test_short_builddir.sh`：
   - 使用项目内 `.dart_tool/flutter_test_config/settings`，不写用户全局 `~/.config/flutter/settings`。
   - 将 Flutter `build-dir` 临时设为相对到 `/tmp/gla_ft` 的短路径，缩短 Flutter tester 需要写入 dylib 的绝对 install name。
   - 继续执行 `flutter test --no-pub "$@"`，可传入单个测试文件或其它 flutter test 参数。
2. 保留真实风险边界：
   - 这不是上游 dylib 的根治；直接运行裸 `flutter test --no-pub` 在当前 repo 深路径下仍可能失败。
   - 后续若升级 `flutter_gemma` 或重新发布带 `-headerpad_max_install_names` 的 macOS prebuilt，可移除 wrapper。

验证：

- `tool/flutter_test_short_builddir.sh`：通过，5 个测试全部通过。

### 16.17 SkillHub.cn SKILL.md sha256 校验（2026-05-04）

继续推进线上 skills，但仍保持 Gemma/local-first 和不执行远端代码的边界。

已完成：

1. `SkillRepository.importSkillHubSkill(...)` 导入前读取 `/api/v1/skills/{slug}/files`：
   - 必须找到 `SKILL.md`。
   - 必须存在合法 64 位 hex `sha256`。
   - `size` 超过 512KB 继续拒绝。
2. 下载 `/api/v1/skills/{slug}/file?path=SKILL.md` 后按原始 `bodyBytes` 计算 SHA-256：
   - 与 files API 的 `sha256` 不一致时直接抛 `SkillImportException`，不会保存到本地。
   - 校验通过后才解析 YAML front matter / instructions。
3. 本地线上 skill 元数据补齐：
   - `GemmaSkill` 新增 `sourceSha256` / `sha256Verified`。
   - `online_skills.json` 持久化 hash 与 verified 状态。
   - Hub 已导入列表显示短 hash，例如 `sha256 已验证：xxxx…yyyy`。
4. 继续保持安全边界：
   - 当前只校验并导入 `SKILL.md` instructions 给本地 Gemma。
   - 仍不下载、不执行远端 `scripts/assets`，更不会把远端 skill 当成已执行工具结果。

验证：

- `tool/flutter_test_short_builddir.sh test/skill_repository_test.dart`：通过，覆盖搜索解析、只下载 SKILL.md、sha256 mismatch 拒绝。
- `dart --disable-dart-dev --packages=.dart_tool/package_config.json tool/check_prompt_and_skills.dart`：通过。
- `flutter analyze`：通过。
- `tool/flutter_test_short_builddir.sh`：通过，6 个测试全部通过。
- `flutter build apk --debug`：通过，输出 `build/app/outputs/flutter-apk/app-debug.apk`。
- `flutter build ios --no-codesign`：通过，输出 `build/ios/iphoneos/Runner.app`。
- live SkillHub API smoke：`skill-vetter` 的 files API 期望 hash 与下载 `SKILL.md` 实际 SHA-256 一致，bytes=4561。

### 16.18 iOS 图片识别 Markdown 不分段修复（2026-05-04）

用户反馈：iOS 图片识别输出看起来是 Markdown，但不分段、不换行，内容粘成一行。

根因：

- 不是 `_visionPrompt(...)` 要求“不换行”或限制 Markdown；当前图片 prompt 只要求看图、回答语言，并没有禁止分段。
- 真正问题在 UI streaming append：`_appendAssistantText(...)` 对每个 token/chunk 都执行 `trimRight()`。
- iOS `flutter_gemma` 的流式输出经常把 `\n` 放在 chunk 尾部，甚至单独发 `\n\n` chunk；逐 chunk `trimRight()` 会把这些换行全部吞掉，MarkdownBody 收到的最终文本自然就无法渲染标题/列表/段落。

已完成：

- `lib/src/features/gemma_home/gemma_home_screen.dart`：移除 streaming token 的 `trimRight()`，只剥离 `[[skill_image:...]]` 协议标记，保留模型原始空白和换行。
- 不新增“必须 Markdown / 必须几段 / 必须换行”的提示词限制，继续让 Gemma 自然输出；如果模型输出换行，UI 会忠实渲染。

待验证：

- iOS 真机重新跑图片识别，确认标题、列表、段落换行不再被吞。

### 16.19 iOS Gemma 懒初始化稳定性（2026-05-04）

继续分析 iOS “打开/发送后卡住”的路径，发现当前 `_runRequest(...)` 会先调用 `_runtime.initialize(gemma4E2bIt)`，而 iOS `initialize()` 又会立即执行 `FlutterGemma.getActiveModel(...)`，默认 `supportImage=true`、GPU backend。随后图片请求进入 `_generateWithFlutterGemma(...)` 又会 `forceReload` 再创建一次多模态 engine。

这导致两个问题：

1. 普通启动/发送阶段过早进入 LiteRT-LM FFI native library / engine 初始化，用户看到像“卡住”。
2. 图片请求实际存在“先默认 image-capable init，再 media forceReload”的双重初始化，增加 iOS 卡顿/失败概率。

已完成：

- iOS `initialize()` 现在只做：
  - 模型路径解析；
  - 文件存在/size 校验；
  - `FlutterGemma.initialize(...)` 与 `installModel(...).fromFile(...).install()` 注册 active model；
  - 不再创建 `InferenceModel` / FFI engine。
- `_generateWithFlutterGemma(...)` 改为按请求懒加载：
  - 纯文字：首次请求才创建 text-only model/session。
  - 图片：每次图片请求仍 `forceReload`，只创建 image-capable model/session。
  - iOS audio probe：仅 `GEMMA_IOS_AUDIO_PROBE=true` 时创建 audio-capable probe session。
- `createChat(...)` 的 `supportImage` 现在跟随本次请求，而不是无条件继承模型配置的 `supportImage=true`。
- 如果未来切换模型配置，会先关闭旧 chat/model，避免旧模型对象被错误复用。

验证：

- `flutter analyze`：通过。
- `tool/flutter_test_short_builddir.sh`：通过。
- `tool/flutter_test_short_builddir.sh test/model_download_progress_smoother_test.dart`：通过。
- `flutter build apk --debug`：通过。
- `flutter build ios --no-codesign`：通过。
- `flutter build ios --release`：通过并完成签名。
- iPhone `00008120-000605C42244201E` release 安装后 `devicectl process launch --console --timeout 12`：未再生成 15:18/15:19 新 Runner crash；命令因 App 持续运行超过 timeout 退出，说明“打开即闪退”已被当前 smoke 排除。

### 16.20 iOS 打开即闪退与下载进度稳定化（2026-05-04）

真机闪退根因已通过 `.ips` crash report 定位：触发线程停在 `BackgroundDownloaderPlugin.register(with:) -> BDPlugin.register(with:) -> swift_getObjectType`，发生在 `GeneratedPluginRegistrant.register(with:)` 的 App 启动注册阶段，早于用户发送请求和 Gemma 推理。也就是说本轮“打开即闪退”不是 Gemma 模型推理崩溃，而是 `flutter_gemma` 传递依赖 `background_downloader 9.5.4` 的 iOS 插件注册崩溃。

项目自己的模型下载并不依赖这个插件：

- Android：`DownloadManager` 系统下载任务，可在 App 后台/进程被杀后继续由系统下载服务调度，并显示系统下载通知。
- iOS：`IOSModelDownloadManager` 使用 `URLSessionConfiguration.background(withIdentifier:)`，`sessionSendsLaunchEvents = true`，并通过 `AppDelegate.handleEventsForBackgroundURLSession` 接系统回调；App 退后台后由 iOS 系统托管继续/调度下载。
- iOS 限制：系统后台下载会被电量、网络、温控、锁屏等策略调度，不保证一直满速，但任务可保留、恢复、完成后唤醒 App。

已完成：

- 新增 `SafePluginRegistrant`，启动时注册本项目实际需要的 `flutter_gemma`、`image_picker_ios`、`large_file_handler`、`shared_preferences_foundation`，明确排除会在当前设备/toolchain 下闪退且本项目不使用的 `background_downloader` 插件注册路径。
- 保留 `GeneratedPluginRegistrant.m` 文件用于 Flutter 生成兼容，但 AppDelegate 改为调用 `SafePluginRegistrant.register(with:)`。
- 下载进度统一做“单条聚合状态”：Dart 层新增 `ModelDownloadProgressSmoother`，对 native 高频/并发 progress 做 800ms 节流、速度指数平滑、received bytes 单调保护。
- UI 显示百分比、已下载/总大小、平滑速度与预计剩余时间；顶部状态 chip 显示下载百分比，不再只显示闪动的“下载中”。
- Android worker 进度发布间隔从 500ms 放宽到 1000ms，继续只向 Flutter 汇总单条进度，不展示多分片/多线程细节。

验证：

- Crash 证据：`.omx/logs/ios-crash-after-release/Runner-2026-05-04-150609.ips` 的触发栈为 `swift_getObjectType -> static BDPlugin.register(with:) -> static BackgroundDownloaderPlugin.register(with:) -> GeneratedPluginRegistrant.registerWithRegistry -> AppDelegate.application`。
- `flutter analyze`：通过。
- `tool/flutter_test_short_builddir.sh`：通过。
- `tool/flutter_test_short_builddir.sh test/model_download_progress_smoother_test.dart`：通过。
- `flutter build apk --debug`：通过。
- `flutter build ios --release`：通过。
- iPhone release 安装并启动：未再生成 15:18/15:19 后的新 Runner crash；`--console --timeout 12` 因 App 持续运行超时退出。

注意：本轮验证没有改用任何非 Gemma 模型或云端 ASR；Gemma-4-E2B-it 仍是文字、图片、audio probe、Prompt Lab、Skills 的本地能力基础。

### 16.21 iOS 图片识别人数漂移修复（2026-05-04）

用户反馈：同一张图片里明明是两个人，但 iOS 图片识别经常回答成三个人。这个问题不能靠硬编码“人数答案”或换其它视觉模型解决；本项目仍必须让 `Gemma-4-E2B-it` 承担本地图片理解。

根因排查：

- Android 路线已经参考 Gallery 做了图片输入归一化：读取 EXIF orientation、按 1024 目标采样、旋转/翻转后重新编码为 PNG，再作为 `Content.ImageBytes` 送入 LiteRT-LM。
- iOS `flutter_gemma` FFI 路线此前直接读取 `image_picker` 的 raw 文件 bytes 送给 LiteRT-LM JSON blob。相册/相机图片可能仍携带 orientation metadata，尺寸也可能明显大于 Gallery 参考输入；模型看到的 vision tensor 与用户预览不完全一致时，容易出现人物数、物体数这类视觉 grounding 漂移。
- 本轮还发现当前未提交代码已经调用 `_readGalleryStyleVisionImageBytes(...)`，但函数定义缺失，`flutter analyze` 直接失败；这说明 iOS 图片质量补强处于半完成状态，必须补完整而不是继续叠 prompt。

已完成：

- `ios/Runner/IOSGemmaRuntime.swift` 新增 `prepareVisionImage` channel 方法：
  - 使用 `UIImage(contentsOfFile:)` 读取 iOS 图片；
  - 通过 `UIGraphicsImageRenderer` 按显示方向重绘，归一化 orientation；
  - 长边限制到 1024，保持原始宽高比，不裁切人物；
  - 输出 PNG bytes 给 Dart/`flutter_gemma` FFI。
- `lib/src/core/runtime/platform_gemma_runtime.dart` 补齐 `_readGalleryStyleVisionImageBytes(...)`：
  - iOS 优先调用 native UIKit 归一化；
  - 缺少 channel 的测试/兜底环境使用 `dart:ui` codec 按同样长边 1024 + PNG 编码处理；
  - 图片请求仍每次重建 image-capable session，并使用较低随机采样，减少 visible count 随机漂移。
- Prompt 只保留“基于可见证据、无法确定就说明不确定”的通用视觉 grounding 指令，不加入固定人数或硬编码答案。

验证：

- 先验证到真实缺口：`flutter analyze` 失败于 `_readGalleryStyleVisionImageBytes` 未定义。
- 修复后 `flutter analyze`：通过。
- `tool/flutter_test_short_builddir.sh`：通过，8 个测试全部通过。
- `flutter build ios --no-codesign`：通过，Swift/UIKit 归一化代码已完成 Xcode 编译。
- `flutter build ios --release`：通过并完成签名。
- `xcrun devicectl device install app --device 00008120-000605C42244201E build/ios/iphoneos/Runner.app`：安装成功，未使用 `flutter install`，避免主动卸载容器。
- `xcrun devicectl device process launch --device 00008120-000605C42244201E --terminate-existing --console --timeout 12 com.example.gemmaLocalApp`：App 持续运行到 12 秒 timeout，未立刻退出。
- `idevicecrashreport -u 00008120-000605C42244201E -k -e -f Runner .omx/logs/ios-crash-post-vision-fix`：只拉到 15:06 及更早旧 crash，15:32 安装/启动后没有新 Runner crash。
- `flutter build apk --debug`：通过，确认 Android 参考路径未被本轮破坏。

仍需真机专项：

- 用用户反馈的“两个人”原图在 iOS 上重新跑图片识别，和 Android 同图输出做 A/B。
- 如果归一化后仍把两个人回答成三个人，下一步继续查 `flutter_gemma` FFI 的 image JSON / LiteRT-LM vision encoder 行为；不能换成非 Gemma/cloud vision 作为本项目验收路径。

### 16.22 iOS 图片人数漂移二次根因（2026-05-04）

用户复测后仍反馈：同一张两人图片 iOS 还是回答“三个人”。

继续取证：

- 已从 iPhone app 容器拉取最近的 `tmp/image_picker_*.jpg` 到 `.omx/logs/ios-images/`，最新图片为蓝色游船场景。
- 直接查看图片可确认：主船/前景中是 1 个成年人 + 1 个儿童，共 2 个主要人物。
- 同时图片远处岸边确实有很小的背景路人/人形。模型如果被提示“描述 people/visible people”但没有区分主体和背景，容易把背景小人混入一个确定总数，回答成“3 人”。这不是正确的产品体验；默认图片理解应该优先说“主体/前景两人”，背景小人只能单独标为远处/不确定。
- 继续查 `flutter_gemma 0.14.1` FFI 代码还发现更深一层差异：`Message.transformToChatPrompt(...)` 对 iOS `.litertlm` 会手动添加 Gemma `<start_of_turn>...` turn markers；但 `.litertlm` FFI 实际走的是 LiteRT-LM JSON conversation API，Android / non-iOS `.litertlm` 路线都是传 raw text，由 LiteRT-LM SDK 自己处理模板。也就是说 iOS 图片链路存在 `JSON role=user + text 内再嵌一层 turn markers` 的 nested-template 风险，这和 Android Gallery 路线不一致，可能进一步影响视觉 grounding。

已完成：

- iOS 普通图片请求（不带 audio、不带 Skills tools）绕过 `flutter_gemma` 的 `InferenceChat/Message.transformToChatPrompt` path，改为直接使用 `LiteRtLmFfiClient`：
  - `initialize(... enableVision: true, maxNumImages: 1)`；
  - `createConversation(temperature: 0.1, topK: 1, topP: 0.95, seed: 1)`；
  - `chatRaw(mediaPrompt, imageBytes: normalizedPng)`；
  - 让 LiteRT-LM JSON conversation API 接收 `content=[image,text]` 和未包 turn markers 的 raw prompt，尽量贴近 Android `Content.ImageBytes + Content.Text(prompt)`。
- `stop()` / `dispose()` 已能取消和释放这个 iOS raw FFI client。
- `_visionPrompt(...)` 调整为更准确的视觉 grounding：
  - 默认先描述 main foreground subject / people；
  - 对人数问题先给主体/前景人数；
  - 远处很小的背景人形、倒影、人形物体要单独说明为 background/uncertain；
  - 不把背景小人和主体混成一个确定主人数。
- 这仍然是 Gemma 本地推理，不引入非 Gemma 视觉模型，也没有写死“这张图是两个人”。

验证：

- `flutter analyze`：通过。
- `tool/flutter_test_short_builddir.sh`：通过，8 个测试全部通过。
- `flutter build ios --no-codesign`：通过，确认 raw FFI import 和 iOS 编译可过。
- `flutter build ios --release`：通过并完成签名。
- `flutter build apk --debug`：通过。
- iPhone 安装复测暂未完成：构建完成后设备 `people` 变为 `unavailable`，`devicectl` 报 `CoreDeviceService was unable to locate a device matching the requested device identifier`；需要设备重新解锁/连接后再安装复测。

仍需真机专项：

- 安装新构建后，用同一张蓝色游船图复测 iOS 图片识别；预期回答应类似“主体/前景有两个人，远处背景可能有很小的路人/人形，不确定是否计入”。
- 如果仍输出单一“三个人”，下一步继续在 raw FFI 层记录 exact message JSON / normalized PNG hash / backend，并比较 GPU vs CPU vision backend，不改变 Gemma-4-E2B-it 作为本地基础模型的边界。

## 17. 本地整理与提交边界（2026-05-04）

当前工程已经是独立 Git 仓库：

```text
repo: /Users/sanbo/Desktop/gallery/gemma_local_app
branch: main
remote: https://github.com/hhhaiai/galleryFlutter.git
```

本轮按功能整理后的提交边界：

1. 文本 / 图片 / Prompt Lab 质量：保留 Gemma 作为唯一回复基础；Prompt Lab 模板真实插入用户输入；文字、图片、图片+语音请求都有明确本地 Gemma prompt。
2. Audio：Android 继续走 Gallery/LiteRT-LM audio 路线，UI/播放保留 16k mono 16-bit PCM WAV，送模型时重新构造完整 WAV bytes；iOS 已接入 audio input/录音/选择/波形/权限与完整 WAV FFI 输入，真机仍需设备在线后复测。
3. Skills / Skills Hub：`Skills Hub` UI 已从 Home 大文件抽到 `lib/src/features/skills/skills_hub_sheet.dart`，线上导入和持久化由 `lib/src/features/skills/skill_repository.dart` 负责；当前已支持粘贴 URL 导入、SkillHub.cn 公开目录搜索/导入、`SKILL.md` sha256 校验与本地 hash 元数据展示。Android ToolProvider 已支持 `loadSkill` / `run_intent(send_email)` / bundled built-in `run_js`，image 结果可附着到 assistant 气泡；webview、线上/custom JS、secret/API key 仍诚实标为待深化。
4. 验证辅助：`tool/check_prompt_and_skills.dart` 可快速验证 Prompt/Skills；`tool/flutter_test_short_builddir.sh` 已恢复 Flutter test 本地闸口。裸 `flutter test --no-pub` 仍需后续上游/根治 `libGemmaModelConstraintProvider.dylib` headerpad/install_name_tool 问题。

提交到 GitHub 时必须继续使用 Lore Commit Protocol，并在 commit message 中明确记录：

- `Constraint: Gemma-4-E2B-it remains the local foundation for text, image, audio, Prompt Lab, and Skills.`
- `Rejected: Replace iOS audio with non-Gemma ASR | violates this project's core validation boundary.`
- `Not-tested: flutter test --no-pub is blocked by macOS native asset install_name_tool/headerpad issue.`

## 18. 快速命令

进入工程：

```bash
cd /Users/sanbo/Desktop/gallery/gemma_local_app
```

格式化和验证：

```bash
dart format lib test
flutter analyze
tool/flutter_test_short_builddir.sh
```

运行 macOS 版本：

```bash
flutter run -d macos
```

运行 Android，需设备/emulator：

```bash
flutter devices
flutter run -d <device_id>
```

构建 Android APK：

```bash
flutter build apk --release
```

构建 iOS Release，需签名配置：

```bash
flutter build ios --release
```

## 19. 文件维护要求

本文件是项目主上下文。后续 agent 接手时：

1. 先读本文件。
2. 再读当前相关代码。
3. 修改代码后更新本文件中的：
   - 已完成进度
   - 待完成规划
   - 验证记录
   - 架构变更
   - 重要决策
4. 运行验证命令。
5. 最终回复用户时说明改动路径和验证结果。

## 20. Android Gallery 最新 Skills 变动同步（2026-05-14）

本轮根据来源工程 `Android/` 当前 `main` 最新提交 `c8c7cef` 同步到 Flutter 工程的 Android/Skills 路线。

来源变动要点：

- Android Gallery 最新提交将 `calculate-hash`、`kitchen-adventure`、`text-spinner`、`send-email` 改为默认不启用。
- 试用入口移除上述几个 skill 的 try-out chip，并新增 `schedule-notification` 的 “Schedule Reminder” 入口。
- `Skill` proto 新增 `user_modified_selection`，用于区分“用户手动选择”和“内置默认选择”。Flutter 工程当前没有 DataStore proto 持久化 built-in 选择，因此本轮用 `selectedByDefault` 保留同等默认语义；用户在运行期仍可通过 Skills Hub 手动开关。
- 来源 Android assets 中还存在 `create-calendar-event`、`read-calendar-events`、`schedule-notification` 三个本地 intent 类 skill，Flutter Android assets 此前缺失，本轮已补齐。

已完成更新：

- `lib/src/features/skills/skill.dart`
  - `GemmaSkill` 增加 `selectedByDefault`；新增 `defaultEnabledBuiltInSkillNames()`。
  - 默认禁用 `calculate-hash`、`kitchen-adventure`、`text-spinner`、`send-email`。
  - 新增 `schedule-notification`、`create-calendar-event`、`read-calendar-events` 三个 built-in skill 定义。
  - Skills system prompt 更新为 Android 已支持 `send_email`、`get_current_date_and_time`、`create_calendar_event`、`read_calendar_events`、`schedule_notification` 等 `run_intent` 动作。
- `lib/src/features/gemma_home/gemma_home_screen.dart`
  - 初始启用 skill 集合改为 `defaultEnabledBuiltInSkillNames()`，与 Android Gallery 最新默认选择保持一致。
- `android/app/src/main/assets/skills/`
  - 从来源工程补齐 `schedule-notification/`、`create-calendar-event/`、`read-calendar-events/`。
- `android/app/src/main/kotlin/com/example/gemma_local_app/MainActivity.kt`
  - Android ToolSet 的 `runIntent` 新增 `get_current_date_and_time`、`create_calendar_event`、`read_calendar_events`、`schedule_notification`。
  - 新增 `ScheduledNotificationReceiver`，用 AlarmManager + NotificationManager 支撑本地提醒通知。
  - `schedule_notification` 支持 `title`、`message`、`hour`、`minute`、可选日期、每日重复和 deeplink。
  - `read_calendar_events` 在缺少 `READ_CALENDAR` 权限时会触发权限请求并诚实返回失败，授权后可重试。
- `android/app/src/main/AndroidManifest.xml`
  - 增加日历/提醒相关权限、Flutter app 自身 deeplink scheme、通知 receiver。
- `test/prompt_and_skills_test.dart`
  - 增加默认启用集合回归测试，锁定 Android Gallery 最新默认策略。

验证记录：

- `flutter test`：失败，原因仍是既有 `flutter_gemma` macOS native asset dylib install_name_tool/headerpad 问题，不是本轮代码逻辑失败。
- `tool/flutter_test_short_builddir.sh`：通过，9 个测试全部通过。
- `flutter analyze`：通过，No issues found。
- `flutter build apk --debug --no-pub`：通过，产物为 `build/app/outputs/flutter-apk/app-debug.apk`。

仍需真机专项验证：

- Android 真机打开 Skills，确认默认启用项为 `interactive-map`、`schedule-notification`、`mood-tracker`、`query-wikipedia`、`qr-code`，且四个默认禁用项可手动开启。
- 授权通知权限后，用 Gemma 请求 “Set a daily reminder at 9am to check my schedule for today.”，确认可触发 `schedule_notification` 并在系统侧创建提醒。
- 如需 `read-calendar-events`，需先授予日历读取权限；未授权时返回失败是预期行为。

### 20.1 Android 可用性收口（2026-05-14）

用户要求确保 `gemma_local_app` 稳定、可用后，继续做了设备级冒烟验证。

发现的问题：

- 首次安装 `build/app/outputs/flutter-apk/app-release.apk` 到已连接 Android 设备 `M2012K11AC` 失败：
  - `INSTALL_FAILED_OLDER_SDK`
  - 设备 SDK 为 30，但工程 Android `minSdk = 31`。
- 这会导致当前连接设备无法安装，属于真实可用性问题。

修复：

- `android/app/build.gradle.kts`
  - `minSdk` 从 31 调整为 30。
  - 代码中 Android 12+ exact alarm 能力仍通过 `Build.VERSION.SDK_INT >= Build.VERSION_CODES.S` 做运行期分支；SDK 30 设备会走兼容的 `AlarmManager.set(...)` / `setAndAllowWhileIdle(...)` 路径。

验证：

- `flutter build apk --release --no-pub`：通过，产物 `build/app/outputs/flutter-apk/app-release.apk`。
- Android 真机安装：通过。
  - device: `M2012K11AC`
  - serial: `986b35a0`
  - package: `com.example.gemma_local_app`
  - installed `versionName=1.0.0`, `versionCode=1`, `minSdk=30`, `targetSdk=36`
- Android 真机启动：通过。
  - `adb shell monkey -p com.example.gemma_local_app -c android.intent.category.LAUNCHER 1`
  - app pid: `9585`
  - 启动后未在当前进程 logcat 中发现 `FATAL EXCEPTION` / `AndroidRuntime` 崩溃输出。
- `flutter analyze`：通过，No issues found。
- `tool/flutter_test_short_builddir.sh`：通过，9 个测试全部通过。

注意：

- 当前安装的是新包 `com.example.gemma_local_app`，不是来源工程包 `com.google.aiedge.gallery`，不会覆盖原 Gallery 应用数据。
- 真正模型推理仍需要在 app 内下载 `Gemma-4-E2B-it` 模型后验证；本轮已经证明 APK 可构建、可安装、可启动，且基础代码闸口通过。


### 20.2 Android 系统 DownloadManager 下载与本地模型快速导入验证（2026-05-14）

用户反馈 Android 端“下载不了”，并明确要求下载必须使用系统下载、多进程下载、支持断点续传；随后提供本机已下载模型 `/Users/sanbo/Desktop/models/gemma/gemma-4-E2B-it.litertlm` 用于快速完成手机端模型就绪。

本轮修复/收口：

- `android/app/src/main/kotlin/com/example/gemma_local_app/download/ModelDownloadRepository.kt`
  - Android 主下载路径从 App 进程内 WorkManager/自写 HTTP Worker 改为系统 `DownloadManager`。
  - 使用 `DownloadManager.enqueue(...)`，目标文件先写入 `gemma-4-e2b-it.litertlm.gallerytmp`。
  - 使用 `setDestinationInExternalFilesDir(context, null, ...)`，兼容 Android 11 / MIUI 的系统下载目标路径。
  - download id 写入 `SharedPreferences("model_downloads")`，App 重启后通过 `DownloadManager.Query` 恢复进度/状态。
  - 成功后 `promoteSystemDownload()` 将 `.gallerytmp` rename/copy 为正式 `gemma-4-e2b-it.litertlm`。
  - `cancel/delete` 调用 `downloadManager.remove(id)`，避免系统任务继续写临时文件。
- `android/app/src/main/kotlin/com/example/gemma_local_app/download/ModelDownloadWorker.kt`
  - 删除旧 Worker，避免继续依赖 App 进程内下载实现。
- `android/app/build.gradle.kts` / `android/app/src/main/AndroidManifest.xml`
  - 移除 App 自己不再需要的 WorkManager foreground-service 下载依赖/声明；系统下载由 Android DownloadManager/DownloadProvider 托管。
- `docs/model_download_flow.md`
  - 更新为当前真实架构：Android DownloadManager 系统下载、系统进程托管、`.gallerytmp/.cfg` 断点续传。

adb 真机验证：

- 设备：`M2012K11AC`，serial `986b35a0`，Android SDK 30。
- 安装：`adb install -r -d build/app/outputs/flutter-apk/app-debug.apk` 成功，保留 App 数据。
- 系统下载验证：
  - UI 点击 Models 下载后显示 `状态: 下载中`。
  - logcat 出现 `DownloadManager: call insert is com.example.gemma_local_app`、`DownloadThread: in runInternal ... huggingface.co/...gemma-4-E2B-it.litertlm?download=true`、`ModelDownloadRepository: Enqueued system download id=1213`。
  - 设备文件出现：`gemma-4-e2b-it.litertlm.gallerytmp` 与 `gemma-4-e2b-it.litertlm.gallerytmp.cfg`。
  - `am kill com.example.gemma_local_app` 后 `pid_after_kill=none`，20 秒后 `.gallerytmp` 从 `24773697` 增长到 `25624576`，证明下载不依赖 App 进程。
- 快速导入已下载模型：
  - 先在 App UI 点 `删除`，取消当前系统下载任务并清空临时文件。
  - `adb push /Users/sanbo/Desktop/models/gemma/gemma-4-E2B-it.litertlm /sdcard/Android/data/com.example.gemma_local_app/files/gemma-4-e2b-it.litertlm`。
  - 推送结果：`2538766336 bytes`，手机路径 `stat` 同为 `2538766336`。
  - App 点击 `刷新` 后顶部状态显示 `已下载`。
  - 重新安装最新 debug 包并启动后仍显示 `已下载`，证明模型路径和状态恢复可用。

验证命令：

- `flutter analyze`：通过，No issues found。
- `tool/flutter_test_short_builddir.sh`：通过，9 个测试全部通过。
- `./android/gradlew -p android :app:assembleDebug --offline`：通过。
- `adb install -r -d build/app/outputs/flutter-apk/app-debug.apk`：通过。

注意：logcat 中仍可看到 `com.google.aiedge.gallery` 的旧 `AGDownloadWorker` 输出，那是来源 Gallery App 包名，不是当前 `com.example.gemma_local_app`，不要误判为本项目仍在使用 WorkManager。

### 20.3 Android/iOS 语音识别修复（2026-05-14）

用户继续反馈：iOS 语音不识别，Android 也不识别。

根因/风险收口：

- iOS FFI 路径此前把 16k mono PCM WAV 的 `data` chunk 剥离成 raw PCM 后传给 `LiteRtLmFfiClient.chatRaw(audioBytes: ...)`。但 `flutter_gemma 0.14.1` 官方 example 是直接发送完整 WAV bytes；Google Android Gallery 也是 `raw PCM + WAV header` 后传 `Content.AudioBytes`。剥离 header 会导致 LiteRT-LM 侧拿到无容器的 opaque PCM blob，表现为语音附件可播放但模型无法识别。
- Android 录音停止时只置 `isRecording=false` 后等待线程，`AudioRecord.read()` 仍可能阻塞；如果等待超时，存在把尚未写完/空 WAV 交给模型的风险。
- 默认语音 prompt 偏“总结”，对“先转写”约束不够强，容易让模型泛泛回复或忽略语音细节。

修复：

- `lib/src/core/runtime/platform_gemma_runtime.dart`
  - `_readGemmaPcm16FromWav` 改为 `_readGemmaWavBytes`。
  - iOS FFI audio 不再剥离 WAV header，校验 16k/mono/16-bit/<=30s 后返回完整 WAV bytes。
  - 默认 audio prompt 改为“先准确转写，再总结/回答”，强调姓名、数字、日期和不确定点。
- `android/app/src/main/kotlin/com/example/gemma_local_app/MainActivity.kt`
  - `stopRecording()` 主动 `AudioRecord.stop()` 打断阻塞 read，再等待录音线程写完 WAV。
  - 增加空文件/未保存完成保护，避免把坏音频交给 Gemma。
- `docs/audio_voice_live_design.md`
  - 同步 Android/iOS 语音输入真实数据格式与本轮修复记录。

验证：

- `flutter analyze`：通过，No issues found。
- `tool/flutter_test_short_builddir.sh`：通过，9 tests。
- `./android/gradlew -p android :app:assembleDebug --offline`：通过。
- `flutter build ios --simulator --debug --no-pub`：通过，产物 `build/ios/iphonesimulator/Runner.app`。
- Android 真机 `adb install -r -d build/app/outputs/flutter-apk/app-debug.apk`：通过；启动后顶部仍显示 `Gemma-4-E2B-it · Local AI / 已下载`，模型文件大小仍为 `2538766336`，当前 app 进程未见 FATAL。

剩余风险：

- 当前 `xcrun xctrace list devices` 显示两台 iPhone offline，因此本轮不能声明 iOS 真机语音识别已通过，只能声明 iOS simulator 编译通过。
- Android 真机已通过 UI 录音发送链路验证：logcat 出现 `GemmaLiteRtRuntime: audio input ready: wavBytes=176044`，界面输出“转录：你好，这是第二四期音讯测试。请实别这句。”和总结；说明录音停止、附件发送、LiteRT-LM audio runtime 与模型转写链路已打通。


### 20.4 语音录制交互稳定性补强（2026-05-14）

- 录音中点击 composer「语音」按钮现在直接停止并附加，不再先弹 bottom sheet，避免用户以为已停止但实际还在录音。
- 点击「发送」时如果仍处于录音中，会先停止录音、校验附件并一起发送，避免空语音/旧语音被误发。
- Android 原生录音保存增加 `AndroidAudioInput` 日志：`recording saved/ready` 和保存不完整告警，便于 adb 真机定位。
- Android 真机验证：录音发送后 logcat 出现 `audio input ready: wavBytes=960044`，Gemma 输出了“音频转录”段落，证明音频链路已进入 LiteRT-LM audio runtime。

### 20.5 Android 语音复测纠偏（2026-05-14）

- 复测纠偏：直接用手机麦克风录电脑外放时，Gemma 会明显幻听，不能作为语音识别质量结论；将同一个 UI 附件文件替换为清晰 16k mono WAV 后复测，logcat 显示 `audio input ready: wavBytes=246564`，UI 转写为“你好，这是一个非常清晰的语音测试。今天是5月14日，请准确地读出这句。”，说明 App audio 文件链路可用，主要风险在麦克风采集/环境声与模型 ASR 精度。

### 20.6 iOS code 13 音频推理专项修复（2026-05-14）

用户在 people iPhone 真机复测 iOS 语音时仍报：`iOS 多模态推理失败，已重置会话，请重试：Exception: Failed to start streaming (code: 13)`。

本轮修复收口：

- `lib/src/core/runtime/platform_gemma_runtime.dart`
  - iOS 音频输入仍保留完整 WAV 容器，但不再把带 `FLLR` 等 padding/metadata chunk 的原始容器直接传入 LiteRT-LM；现在会解析 `data` chunk 后重建最小 44-byte `RIFF/fmt/data` 16k mono 16-bit PCM WAV。
  - iOS audio-only raw FFI 推理优先使用 `cpu` backend，并在失败时 fallback `gpu`；错误信息会带出已尝试 backend，便于继续定位 code 13。
  - 高级 `flutter_gemma` audio-only fallback 路径同样选择 CPU backend，避免主 decoder GPU + audio executor CPU 的 iOS 组合触发 streaming 启动失败。
- `test/gemma_wav_normalization_test.dart`
  - 新增带 `FLLR` padding chunk 的 iOS/macOS 风格 WAV 归一化测试，锁定输出为最小 44-byte WAV + 原 PCM data。
- `docs/audio_voice_live_design.md` / `docs/feature_mapping.md` / `docs/progress.md`
  - 同步 code 13 根因假设与当前修复策略：iOS runtime 送模型前使用干净 WAV 容器、audio-only CPU 优先；仍需 people iPhone 真机手动发送语音验证模型实际转写。

验证：

- `flutter analyze`：通过，No issues found。
- `FLUTTER_TEST_BUILD_DIR=/tmp/gla_ft_unit tool/flutter_test_short_builddir.sh test/gemma_wav_normalization_test.dart`：通过。
- `FLUTTER_TEST_BUILD_DIR=/tmp/gla_ft_all tool/flutter_test_short_builddir.sh`：通过，10 tests。

待真机复测：

- people iPhone 已 USB 连接，下一步需安装当前构建并在 UI 重新发送一段语音；期望 syslog 出现 `[GemmaIOS] raw media inference backend=cpu audioBytes=...`，若 CPU 仍失败再自动尝试 GPU 并输出最终 backend 列表。

### 20.7 iOS code 13 streaming fallback（2026-05-14）

用户在 people iPhone 安装 20.6 后手动复测仍提示同样的 `Failed to start streaming (code: 13)`。

追加修复：

- `lib/src/core/runtime/platform_gemma_runtime.dart`
  - 在 iOS raw FFI media path 中捕获 streaming API 的 code 13：`LiteRtLmFfiClient.chatRaw(...)` 如果启动 streaming 失败，不再直接向 UI 报错，而是使用同一 conversation 和同一 `{type: audio, blob: ...}` JSON 调用非 streaming `LiteRtLmFfiClient.sendMessage(...)`。
  - 该 fallback 仍是真实 LiteRT-LM/Gemma 推理，只是不走 token streaming；若成功，会一次性返回完整回复。
  - 若 sync `sendMessage(...)` 也失败，再按 backend fallback 继续尝试 CPU/GPU，最后返回真实错误。

验证与安装：

- `flutter analyze`：通过。
- `FLUTTER_TEST_BUILD_DIR=/tmp/b tool/flutter_test_short_builddir.sh`：通过，10 tests。
- `flutter run --debug --no-resident -d 00008120-000605C42244201E`：Xcode build 成功并执行安装/启动；仍因 Dart VM Service 未 attach 而长时间等待，随后使用 `xcrun devicectl device process launch --device BAD258BF-4E4A-5C40-9701-AEF8CCF43E6D com.example.gemmaLocalApp` 启动成功。
- 为避免残留挂起，已清理两个旧 `flutter run --debug --no-resident` 进程。

下一步：people iPhone 需要再次手动发送语音。若仍报错，说明并非 streaming API 专项问题，而更可能是 iOS LiteRT-LM audio executor / Gemma-4-E2B-it 音频支持在当前设备链路上的 native blocker；届时需要抓 `[GemmaIOS] streaming failed... trying sync sendMessage` 之后的真实 sync 错误。

### 20.8 对齐 Google AI Edge iOS allowlist（2026-05-14）

用户指出“Google AI Edge 好像已经实现了，iOS 可以工作”。复查官方 `google-ai-edge/gallery` 最新公开仓库后，关键结论是：**Gallery 的 iOS 可工作音频模型不是 Gemma 4，而是 iOS allowlist 中的 Gemma 3n E2B/E4B**。

证据：

- `model_allowlists/ios_1_0_0.json` 只列出 `Gemma-3n-E2B-it`、`Gemma-3n-E4B-it`、`Gemma3-1B-IT`；其中 Gemma 3n E2B/E4B 标注 `llmSupportAudio: true` 和 `llm_ask_audio`。
- Android 最新 allowlist `1_0_14.json` 才列出 `Gemma-4-E2B-it` / `Gemma-4-E4B-it` 的 `llm_ask_audio`。
- GitHub issue #692 正好记录了同类问题：Gemma 4 LiteRT-LM 在 iOS 初始化/推理失败，而公开 iOS allowlist 不列 Gemma 4。

本轮代码调整：

- `lib/src/core/model/gemma_model_config.dart`
  - 新增 `gemma3nE2bItIos`，字段按 Google AI Edge iOS allowlist：`google/gemma-3n-E2B-it-litert-lm`、`gemma-3n-E2B-it-int4.litertlm`、commit `73b019b63436d346f68dd9c1dbfd117eb264d888`、size `3388604416`、`supportImage/supportAudio=true`、`modelTypeName='gemmaIt'`。
- `lib/src/features/gemma_home/gemma_home_screen.dart`
  - `_activeModel` 改为平台选择：iOS 使用 `Gemma-3n-E2B-it`，Android 继续使用 `Gemma-4-E2B-it`。
  - App title / Models drawer 显示当前平台模型；iOS tag 为 `iOS 音频模型`。

验证：

- `flutter analyze`：通过。
- `FLUTTER_TEST_BUILD_DIR=/tmp/c tool/flutter_test_short_builddir.sh`：通过，10 tests。
- 已重新安装并启动到 people iPhone，保留 App 数据。

注意：Gemma 3n 的 Hugging Face 仓库是 gated repo；直接 HEAD 下载返回 `401 GatedRepo`。所以 iOS 现在会正确要求/下载 Gallery iOS allowlist 模型，但如果没有 HF token/授权或本地预下载文件，仍无法完成模型获取。当前 `/Users/sanbo/Desktop/models/gemma` 只有 Gemma 4 E2B/E4B，没有 Gemma 3n E2B。

### 20.9 macOS 中文输入与桌面图片选择修复记录（2026-05-20）

本轮用户在 macOS 调试中连续反馈两个桌面可用性问题：

1. **中文输入不稳定/不能正常上屏**
2. **图片图标点击后没有正确弹出可用的文件选择流程**

#### 中文输入问题的根因

问题不在 Gemma runtime，而在 Flutter `TextField` 上叠加了移动端式输入干预：

- composer 输入框的 `TextField` 绑定了自定义 `onTap`
- `onTap` 内部手动执行：
  - `focusNode.requestFocus()`
  - `SystemChannels.textInput.invokeMethod('TextInput.show')`

这类逻辑在 Android/iOS 上常用于确保软键盘弹出，但在 macOS 上会干扰系统输入法（尤其是中文 IME）的组合输入流程，表现为：

- 中文候选不稳定
- 点击输入框后中文无法正常输入
- 桌面端输入行为和原生 App 不一致

#### 中文输入问题的修复方式

已在：

- `lib/src/features/gemma_home/gemma_home_screen.dart`

做以下调整：

- 删除 `TextField` 上针对桌面端的自定义 `onTap` 干预
- 不再在 macOS 上主动调用 `TextInput.show`
- 输入框行为回退到 Flutter/macOS 原生文本输入路径

最终结论：

- **桌面端不要为了“模仿手机键盘弹出”去手动操控 `TextField` 的 focus/text input channel**
- macOS/Windows/Linux 应优先保持系统原生输入法链路

#### 后续防回归原则（中文输入）

以后如果继续改 composer 输入框，必须遵守：

1. **不要在桌面端 `TextField` 上主动调用 `SystemChannels.textInput.show`**
2. **不要在桌面端为普通输入框额外写 `requestFocus()` 型 onTap 干预**
3. 如果必须保留手机端软键盘逻辑，必须显式限制到：
   - `Platform.isAndroid || Platform.isIOS`
4. 出现“中文无法输入 / 候选异常 / 上屏异常”时，先回查输入框是否又加回了移动端输入干预，再排查 Flutter/macOS 本身

#### 图片图标无效的根因

macOS 上 `image_picker` 底层走的是 `file_selector`，而不是移动端相机/系统相册弹层。当前项目最初仍沿用了手机图片入口：

- 点击图片按钮
- 弹出 “拍照 / 从相册选择”

这在桌面端交互上不合适，而且 macOS 沙盒如果没有补对应 entitlement，用户选择文件后也可能没有可读权限，最终表现为“点图标没反应”或“选完无结果”。

#### 图片图标无效的修复方式

已完成两层修复：

1. **桌面端图片入口改造**
   - 在 `lib/src/features/gemma_home/gemma_home_screen.dart`
   - macOS/Windows/Linux 点击图片图标时，不再弹移动端 bottom sheet
   - 直接走 `ImageSource.gallery` 的文件选择器路径

2. **macOS 文件访问 entitlement 补齐**
   - `macos/Runner/DebugProfile.entitlements`
   - `macos/Runner/Release.entitlements`
   - 新增：
     - `com.apple.security.files.user-selected.read-only = true`

#### 后续防回归原则（桌面图片选择）

1. `image_picker` 在桌面端本质是文件选择器，不要继续套用手机端“拍照/相册”交互
2. 只要桌面端需要用户手选文件，就必须先检查 sandbox entitlement 是否齐全
3. 以后若再次出现“图标点击无效”，优先检查：
   - 是否误回退成移动端图片入口
   - macOS entitlement 是否缺失
   - 文件选择器是否被 sandbox 拦截

#### 本轮涉及文件

- `lib/src/features/gemma_home/gemma_home_screen.dart`
- `macos/Runner/DebugProfile.entitlements`
- `macos/Runner/Release.entitlements`

#### 本轮验证

- `flutter analyze`：通过
- macOS app 重启后：
  - 模型仍走私有目录
  - 输入框可承载中文文本
  - 图片入口已切到桌面文件选择逻辑

备注：

- 中文输入法候选上屏这类问题很难完全靠自动化稳定验证，因此后续每次修改桌面 composer 输入框后，都要保留一次真实人工中文输入回归。

### 21.0 2026-05-20 移动端默认模型重新统一到 Gemma-4-E2B-it

用户最新要求已经改变：

- **Android 默认模型必须是 `Gemma-4-E2B-it`**
- **iOS 默认模型也必须是 `Gemma-4-E2B-it`**
- **图片 / 文字 / 语音识别都继续要求支持**
- **文字上下文要更长一些**

因此当前仓库的最新基线不再沿用之前的：

- “iOS 默认切到 `Gemma-3n-E2B-it` 以对齐旧 allowlist”

而改为：

- `lib/src/features/gemma_home/gemma_home_screen.dart`
  - `_activeModel` 固定返回 `gemma4E2bIt`
- `lib/src/core/model/gemma_model_config.dart`
  - `availableModels` 收敛回单模型 `Gemma-4-E2B-it`

#### 为什么要同步调整 runtime token window

用户随后给出的 macOS / Apple 多模态错误是：

- `Input token ids are too long. Exceeding the maximum number of tokens allowed: 3863 >= 1024`

这说明当前 runtime session window 被硬编码得过小，图片或多模态请求很容易在进入模型前就被拒绝。

为满足“文字上下文更长一些”，并同时减少图片/语音请求的 token 上限错误，已在：

- `lib/src/core/runtime/platform_gemma_runtime.dart`

新增统一的 session token window 规则：

- 纯文字请求：目标窗口 `8192`
- 图片 / 语音等多模态请求：目标窗口 `4096`
- 最终仍受模型自身 `maxTokens` / `maxContextLength` 限制

#### 后续防回归要求

1. 以后如果再看到 “iOS 默认模型是 Gemma-3n-E2B-it”，优先检查是不是又把 `_activeModel` 改回平台分流了。
2. 以后如果再看到 `Input token ids are too long ... >= 1024`，优先检查 runtime session window 是否又回退成固定 `1024`。
3. 不要再把“旧 iOS allowlist 结论”直接当成当前产品策略；当前产品策略以用户最新明确要求为准：**双端统一 Gemma-4-E2B-it**。

### 21.1 2026-05-20 双端 Gemma-4-E2B-it 基线复检与防回退加固

本轮继续落实用户要求：Android / iOS 全部默认 `Gemma-4-E2B-it`，图片、文字、语音识别都走该本地模型，文字上下文窗口加长。

已加固内容：

- `lib/src/core/model/gemma_model_config.dart`
  - 删除历史 iOS `Gemma-3n-E2B-it` 配置常量，避免后续误把 iOS 默认模型切回 Gemma 3n。
  - `availableModels` 只保留 `gemma4E2bIt`。
- `lib/src/features/gemma_home/gemma_home_screen.dart`
  - `_activeModel` 当前固定为 `gemma4E2bIt`。
- `lib/src/core/runtime/platform_gemma_runtime.dart`
  - runtime session window 规则保留并加单测锁定：纯文字 `8192`，图片/语音多模态 `4096`，不再回退到旧的 `1024`。
- `test/model_baseline_test.dart`
  - 新增防回归测试：只暴露 `Gemma-4-E2B-it`，且模型能力包含 text / image / audio；session token window 不得回退到 `1024`。
- `docs/progress.md`、`docs/feature_mapping.md`、`docs/audio_voice_live_design.md`、`docs/google_ai_edge_ux_design.md`
  - 将 2026-05-14 iOS Gemma 3n allowlist 方案明确标为历史排查记录，不再作为当前默认产品路线。

本轮验证：

```bash
flutter analyze
FLUTTER_TEST_BUILD_DIR=/tmp/c tool/flutter_test_short_builddir.sh
flutter build apk --release
flutter build ios --release
```

验证结果：

- `flutter analyze`：通过，No issues found。
- `tool/flutter_test_short_builddir.sh`：通过，13 tests passed。
- Android Release：通过，产物 `build/app/outputs/flutter-apk/app-release.apk`。
- iOS Release：通过，产物 `build/ios/iphoneos/Runner.app`。

注意：直接使用较长临时目录跑 Flutter test 仍可能触发 `flutter_gemma` macOS native asset `install_name_tool` headerpad 问题；本仓库继续使用短路径 `FLUTTER_TEST_BUILD_DIR=/tmp/c` 作为当前稳定测试闸口。

### 21.2 2026-05-20 本地安装默认预置 Gemma_4_E2B_it

用户要求本地仓库安装时直接把本机模型预置进应用，不再让移动端重新下载。当前固定本地来源为：

```text
/Users/sanbo/Desktop/models/gemma/Gemma_4_E2B_it/20260325/gemma4_2b_v09_obfus_fix_all_modalities_thinking.litertlm
```

已落地：

- `Gemma-4-E2B-it.sizeInBytes` 改为本地文件真实大小 `2538766336`，避免 Android/iOS 预置后被误判为“不完整模型”。
- 新增本地安装脚本：

```bash
tool/install_release_with_local_gemma4.sh
```

脚本行为：

1. 校验本机模型文件存在且大小为 `2538766336`。
2. 编译：`flutter build apk --release` 和 `flutter build ios --release`。
3. Android：`adb install -r -d` 保留数据安装 release APK，然后把模型推到：

```text
/sdcard/Android/data/com.example.gemma_local_app/files/gemma-4-e2b-it.litertlm
```

4. iOS：`devicectl device install app` 保留数据安装 release Runner.app，然后把模型复制到 app data container：

```text
Library/Application Support/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm
```

5. 复制完成后启动 App。

可选环境变量：

```bash
ANDROID_DEVICE=37101FDJH0077P \
IOS_DEVICE=CAFC7AFA-4565-5C8D-B724-090061D144D0 \
tool/install_release_with_local_gemma4.sh
```

如果只想重新预置模型、不重新编译：

```bash
BUILD_RELEASE=0 tool/install_release_with_local_gemma4.sh
```

### 21.3 2026-05-20 稳定优先的更大上下文增强

用户确认“不追求 256K 单次会话”，但希望在稳定基础上增强更大上下文。本轮先采用渐进式放大，不直接打满模型 32K：

- 纯文字 session window：从 `8192` 提高到 `16384`。
- 图片 / 语音多模态 session window：Android/default 从 `4096` 提高到 `8192`；iOS 为稳定保留 `4096`。

原因：

- 纯文字没有额外视觉/音频 encoder 内存，可以先扩大到 16K，明显改善长对话。
- 图片/语音请求会额外占用多模态 encoder 与 KV cache，先从 4K 提到 8K，避免直接 16K/32K 带来 iOS/Android 内存和初始化风险。
- `Gemma-4-E2B-it.maxContextLength` 仍保留 `32000`，未来如果真机长期稳定，可以再做高配设备开关或自适应 32K。

防回退：`test/model_baseline_test.dart` 已锁定纯文字不回退到 `1024`，并在后续 21.6/21.7 中升级为按设备内存分档。

### 21.4 2026-05-20 仓库内本地模型缓存（GitHub 忽略）

用户进一步明确：本地编译/安装时希望直接使用本地模型，并把模型拷贝到代码仓库一份；但 GitHub 有大小限制，模型文件必须忽略。

已落地：

- 仓库本地模型缓存路径：

```text
local_models/Gemma_4_E2B_it/20260325/gemma-4-E2B-it.litertlm
```

- 该文件已从本机模型源复制/克隆，大小校验为 `2538766336` bytes。
- `.gitignore` 已新增：

```text
/local_models/
/models/
/bundled_models/
*.litertlm
*.litertlm.gallerytmp
*.xnnpack_cache
*.mldrift_program_cache.bin
```

- 新增 `tool/prepare_local_gemma4_model.sh`：如果仓库内模型不存在，会从：

```text
/Users/sanbo/Desktop/models/gemma/Gemma_4_E2B_it/20260325/gemma4_2b_v09_obfus_fix_all_modalities_thinking.litertlm
```

复制到仓库 `local_models/.../gemma-4-E2B-it.litertlm`。

- `tool/install_release_with_local_gemma4.sh` 已改为默认使用仓库内 `local_models/.../gemma-4-E2B-it.litertlm`，安装时自动预置到 Android/iOS app data container，不走下载。
- iOS 大文件 copy 增加重试，并在验证前启动 App，让 `IOSModelDownloadManager.refreshStatus` 有机会把 Application Support 里已有的完整模型迁移到标准路径。

验证：

```bash
tool/prepare_local_gemma4_model.sh
git check-ignore -v local_models/Gemma_4_E2B_it/20260325/gemma-4-E2B-it.litertlm
bash -n tool/prepare_local_gemma4_model.sh tool/install_release_with_local_gemma4.sh
flutter analyze
FLUTTER_TEST_BUILD_DIR=/tmp/c tool/flutter_test_short_builddir.sh
```

结果：模型文件已在仓库本地缓存中，且被 `.gitignore` 忽略；脚本语法、analyze、13 个测试均通过。

### 21.5 2026-05-20 iPhone 13 图片识别闪退稳定性修正

用户反馈：iPhone 13 识别图片时 App 会闪退。

排查结论：最近为了“更大上下文”把图片/语音多模态 session window 提到 `8192`。图片识别在 iOS 上会同时占用 LiteRT-LM decoder KV cache 与 vision encoder 内存；iPhone 13 这类较低内存设备在启动 iOS image runtime 时更容易被系统直接终止，Dart 层无法捕获成普通异常。因此这不是模型文件缺失，也不是 UI 选择图片问题，而是 iOS 多模态窗口放大过激导致的稳定性风险。

修复策略：保留更大文字上下文，但 iOS 多模态回到已知更稳的窗口。

- 纯文字：先继续 `16384` 稳定基线，后续只在 text-only 路径按设备内存继续放大。
- Android/default 图片/语音：继续 `8192`。
- iOS 图片/语音：回退为 `4096`。

代码位置：

- `lib/src/core/runtime/platform_gemma_runtime.dart`
  - `_runtimeSessionTokenLimit(...)` 现在会对 `Platform.isIOS` 的多模态请求启用 `appleSafeMultimodal`。
- `test/model_baseline_test.dart`
  - 新增断言：iOS safe multimodal image/audio 均为 `4096`，防止再次把 iPhone 13 图片路径提高到 8K 后闪退。

后续如果要再提升 iOS 图片上下文，必须做设备分档/开关，不能直接全量提升。

### 21.6 2026-05-20 按设备内存自适应上下文和图片尺寸

用户问是否可以根据手机内存设置大小。已实现：App 启动/初始化 runtime 时读取设备内存，并按内存分档设置文字上下文、多模态上下文、图片预处理长边和 iOS 图片 backend 顺序。

原生内存探测：

- Android `MainActivity.kt`
  - 新增 `getDeviceMemoryInfo`，返回 `ActivityManager.MemoryInfo.totalMem / availMem / lowMemory / memoryClassMb / largeMemoryClassMb`。
- iOS `IOSGemmaRuntime.swift`
  - 新增 `getDeviceMemoryInfo`，返回 `ProcessInfo.physicalMemory / processorCount / thermalState / lowPowerModeEnabled`。

Dart 自适应策略：

- `lib/src/core/runtime/platform_gemma_runtime.dart`
  - 新增 `DeviceRuntimeProfile.forMemoryBytes(...)`。
  - iOS 低内存档（例如 iPhone 13 约 4GB）：
    - text token window: `12288`
    - image/audio token window: `2048`
    - image max dimension: `640`
    - image backend: `cpu -> gpu`
  - iOS 中内存档（约 6GB）：
    - text: `16384`
    - multimodal: `3072`
    - image max dimension: `768`
  - iOS 高内存档（>7GB）：
    - text: `24576`
    - multimodal: `4096`
    - image max dimension: `896`
  - Android 低内存档（<=6GB）：
    - text: `12288`
    - multimodal: `3072`
    - image max dimension: `640`
  - Android 中内存档（<=10GB）：
    - text: `24576`
    - multimodal: `8192`
    - image max dimension: `1024`
  - Android 高内存档（>10GB）：
    - text: `32000`
    - multimodal: `8192`
    - image max dimension: `1024`

原因：iPhone 13 图片闪退更像 iOS native / jetsam 内存峰值问题；只降低 token 到 4096 仍不够，所以低内存 iOS 同时降低图片长边到 640，并优先尝试 CPU image backend，避免 GPU vision 初始化峰值。

验证：

```bash
flutter analyze
FLUTTER_TEST_BUILD_DIR=/tmp/c tool/flutter_test_short_builddir.sh
flutter build ios --release
BUILD_RELEASE=0 INSTALL_ANDROID=0 IOS_DEVICE=CAFC7AFA-4565-5C8D-B724-090061D144D0 tool/install_release_with_local_gemma4.sh
```

结果：analyze 通过，14 tests passed，iOS release 构建通过，并已安装启动到 iPhone13。

补充验证：Android release 也已重新编译通过，并通过 `adb install -r -d` 安装启动到 Pixel 8，pid `17045`。

### 21.7 2026-05-20 文字对话上下文二次放大

用户希望“文字对话更大一些，不过需要验证”。本轮只放大 text-only session window，不同步放大图片/语音多模态窗口，避免重新触发 iPhone 13 图片识别内存峰值问题。

新的文字分档：

- iOS 内存探测失败 fallback：`8192`（保守）
- iOS 低/中/高内存：`12288 / 16384 / 24576`
- Android 内存探测失败 fallback：`16384`（保守）
- Android 低/中/高内存：`12288 / 24576 / 32000`

稳定边界：

- 图片/语音多模态窗口保持 21.6 的稳定值，不跟随文字窗口放大。
- `Gemma-4-E2B-it.maxContextLength=32000` 仍是最终上限；Android 高内存文字会话打到 `32000`，不会超过模型配置。
- 低内存/探测失败时不激进放大，优先保启动和图片路径稳定。

验证要求：

- `test/model_baseline_test.dart` 新增文字窗口分档断言，同时断言 iOS low 图片仍为 `2048`。
- 已重新跑 `flutter analyze`、短路径 Flutter test、Android/iOS release build。
- 已用 `tool/install_release_with_local_gemma4.sh` 把 release 包安装启动到 Pixel 8 和 people / iPhone 14 Pro Max，并确认预置模型仍存在。
