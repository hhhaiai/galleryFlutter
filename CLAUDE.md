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
  "sizeInBytes": 2583085056,
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

待实现：

- Android MethodChannel 真调用 LiteRT-LM `Conversation.generateResponseAsync` 或等效 API。

### 9.2 图片理解

来源：

```text
Model.llmSupportImage
EngineConfig.visionBackend
runInference(images: List<Bitmap>)
```

当前 Flutter 抽取：

- 入口：`GemmaTaskId.askImage`
- 请求字段：`GemmaRequest.imagePaths`
- UI 已接入真实图片附件流程：点击图片按钮弹出「拍照 / 从相册选择」，拍照或选择后缩略图附着在输入框上方，可删除，可附带文字一起发送。
- Android：MethodChannel 传图片路径；原生 `MainActivity.kt` 参考 Google AI Edge Gallery，读取图片 EXIF 方向、按 1024x1024 采样解码并旋转，再编码为 PNG bytes，通过 `Content.ImageBytes` 与文本一起发送给 LiteRT-LM；启用图片时固定 `visionBackend = Backend.GPU()`（Gemma 4 多模态要求 vision encoder 走 GPU）。避免直接传原始大图或错误 vision backend 导致 `Status Code: 12/13 / Failed to invoke the compiled model`。
- iOS：`flutter_gemma` 初始化启用 `supportImage`，发送时读取图片 bytes 并使用 `Message.withImage(text:imageBytes:isUser:)`。

### 9.3 声音理解

来源：

```text
Model.llmSupportAudio
EngineConfig.audioBackend = Backend.CPU()
runInference(audioClips: List<ByteArray>)
```

当前 Flutter 抽取：

- 入口：`GemmaTaskId.askAudio`
- 请求字段：`GemmaRequest.audioPaths`
- UI 目前仅保留入口和提示，尚未接音频选择/录音。

待实现：

- Flutter 侧音频选择或录音。
- MethodChannel 传音频路径或 bytes。
- Android 原生转换为 ByteArray。

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
- [x] Android 模型下载改为系统后台下载：WorkManager + ForegroundInfo 通知 + `.gallerytmp` + HTTP Range 断点续传
- [x] Android 下载桥接新增 MethodChannel/EventChannel：`com.example.gemma_local_app/model_download` / `model_download_events`
- [x] Android 模型下载新增并发分片能力：Worker 对支持 Range 的大文件最多开启 4 路 HTTP byte-range coroutine，分片保存为 `{modelFile}.gallerytmp.partN`，每个 part 按已有长度断点续传，全部完成后合并为 `.gallerytmp` 并 rename 为正式 `.litertlm`
- [x] Android 模型文件路径调整为扁平路径：`/storage/emulated/0/Android/data/com.example.gemma_local_app/files/gemma-4-e2b-it.litertlm`；旧嵌套路径下载完成的模型会在 `refreshStatus` 时迁移
- [x] Android 发送文字后闪退/遮罩根因已定位为 LiteRT-LM 初始化在主线程触发 5s input dispatching ANR；已改为后台单线程初始化/生成，并将首轮推理降为 CPU + maxTokens 1024 + 暂停 vision/audio backend，避免首轮加载阻塞 UI
- [x] 聊天气泡支持 Markdown 渲染：新增 `flutter_markdown`，用户输入和模型输出均用 `MarkdownBody(selectable: true)` 展示，支持标题、列表、引用、行内代码和代码块
- [x] Android 真机已重新编译安装，并授予 POST_NOTIFICATIONS 权限用于前台下载通知
- [x] 常规验证通过：`dart format lib test`、`flutter analyze`、`flutter test`、`flutter build apk --debug`
- [x] Android 后台下载点击闪退已定位并修复：Android 16 / targetSdk 36 禁止 foreground service type none，已给 WorkManager SystemForegroundService 合并 `android:foregroundServiceType="dataSync"`，ForegroundInfo 显式传 `ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC`；adb 点击下载验证无 FATAL/ANR，WorkManager 持续下载，退后台仍有 progress，回前台 pid 不变
- [x] iOS 不再显示死胡同式“暂不支持”：参考 Google AI Edge Gallery 已上架 iOS App Store、Gallery README、LiteRT-LM iOS/macOS prebuilt 和 iOS allowlist，Dart runtime 旧 iOS 文案已移除；iOS 必须进入原生 MethodChannel runtime。
- [x] iOS 原生模型下载断点续传修复：`IOSModelDownloadManager.swift` 使用 `URLSessionConfiguration.background`，对已有 `.gallerytmp` 发送 `Range`；续传响应为 HTTP 206 时把本次下载片段追加到旧 `.gallerytmp`，响应为 200 时认为服务端忽略 Range 并覆盖重下，避免旧逻辑把剩余片段当成完整模型导致损坏文件；进度统计加入 resume offset。
- [x] Dart 前台下载兜底修复：如果已有 `.gallerytmp` 但 Range 请求返回 200，则删除旧 tmp 并用 `FileMode.write` 覆盖，不再 append 完整响应。
- [x] iOS runtime channel 已注册到 `com.example.gemma_local_app/runtime`：Flutter 侧现在 iOS 也走 MethodChannel，不再走 Dart Placeholder/占位输出。
- [x] Xcode/Swift toolchain 已从 Xcode 15.0.1 升级到 Xcode 26.4.1 / Swift 6.3.1，`ios/Podfile` 已启用 `MediaPipeTasksGenAI 0.10.35`，`pod install` 与 `flutter build ios --no-codesign` 均可成功链接。
- [x] iOS 真实文字对话 runtime 已接入：`IOSGemmaRuntime.swift` 使用 `LlmInference.Options(modelPath:)` 初始化模型，创建 `LlmInference.Session`，`generate` 调用 `session.addQueryChunk(inputText:)` 与 `session.generateResponseAsync()`，并把 partial token 通过 `com.example.gemma_local_app/runtime_events` 流式返回 Flutter。
- [x] 图片入口已升级为真实附件流程：点击图片弹出「拍照 / 从相册选择」，拍照或选择后缩略图附着到输入框，可删除，可附带文字一起发送；Android 参考 Gallery 以 1024x1024 采样 + EXIF 旋转后通过 `Content.ImageBytes` 接入 LiteRT-LM，iOS 通过 `flutter_gemma` 的 `Message.withImage` 接入。

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
4. `google-ai-edge/gallery` Android 端模型下载采用 `DownloadRepository.kt` + `DownloadWorker.kt` + WorkManager + notification；本项目 Android 已按该方向升级为系统后台下载、多 Range 分片、断点续传。
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
- 增强 `refreshStatus` 与 `download` 前的恢复逻辑：扫描 Application Support、Documents、Caches 中已有的 `gemma-4-E2B-it.litertlm`、小写 `gemma-4-e2b-it.litertlm`、以及 Gallery 风格嵌套目录；如果发现大小达到 `2583085056` 的完整模型，会迁移到当前 iOS 标准路径 `{ApplicationSupport}/Gemma_4_E2B_it/{commitHash}/gemma-4-E2B-it.litertlm` 并直接返回 `succeeded`，避免重复下载。
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
- [x] Android 后台下载/通知：WorkManager + ForegroundInfo dataSync + SystemForegroundService dataSync。
- [x] Android 并发分片下载：最多 4 路 Range part，支持 `.partN` 级断点续传。
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

## 16. 推荐下一步执行计划

下一次继续开发时，建议直接从 P0 开始：

1. 阅读原工程 LiteRT-LM Gradle 配置。
2. 把 LiteRT-LM 依赖最小迁移到 Flutter Android 工程。
3. 在 Android `MainActivity` 或独立 Kotlin 类中实现 MethodChannel。
4. Dart `MethodChannelGemmaRuntime.initialize()` 传入模型本地路径和参数。
5. Android 创建 `Engine` 和 `Conversation`。
6. 先做最小文本 generate，一次性返回完整文本。
7. 跑 Android emulator/真机验证。
8. 再升级 EventChannel 流式 token。
9. 最后接图片、音频、Skills。

P0 最小验收标准：

- 在侧边 Models 下载 Gemma-4-E2B-it。
- 下载完成后主页面输入文字。
- Android 原生 LiteRT-LM 使用本地 `.litertlm` 文件返回真实模型输出。
- `flutter analyze` 和 `flutter test` 通过。
- Android Profile/Release 真机可启动。

## 17. 当前 Git/文件状态说明

当前 `gemma_local_app/` 是新建目录，在父仓库中显示为 untracked：

```text
?? gemma_local_app/
```

父目录还存在其它未跟踪文件：

```text
?? ai-edge-gallery.apk
?? model_download_urls_android_1_0_11.json
```

不要误删这些用户文件。

## 18. 快速命令

进入工程：

```bash
cd /Users/sanbo/Desktop/gallery/gemma_local_app
```

格式化和验证：

```bash
dart format lib test
flutter analyze
flutter test
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

