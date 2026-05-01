# 架构梳理

## 来源工程

当前目录是 Google AI Edge Gallery Android 工程，核心路径：

- 模型定义：`Android/src/app/src/main/java/com/google/ai/edge/gallery/data/Model.kt`
- 任务定义：`Android/src/app/src/main/java/com/google/ai/edge/gallery/data/Tasks.kt`
- Allowlist 转模型：`Android/src/app/src/main/java/com/google/ai/edge/gallery/data/ModelAllowlist.kt`
- LiteRT-LM 对话运行时：`Android/src/app/src/main/java/com/google/ai/edge/gallery/ui/llmchat/LlmChatModelHelper.kt`
- 运行时接口：`Android/src/app/src/main/java/com/google/ai/edge/gallery/runtime/LlmModelHelper.kt`
- Agent Skills：`Android/src/app/src/main/java/com/google/ai/edge/gallery/customtasks/agentchat/`
- Prompt Lab 模板：`Android/src/app/src/main/java/com/google/ai/edge/gallery/ui/llmsingleturn/PromptTemplateConfigs.kt`
- 内置 Skills 资产：`Android/src/app/src/main/assets/skills/*/SKILL.md`

## 抽取后的工程分层

```text
lib/
  main.dart
  src/app/gemma_local_app.dart
  src/core/model/gemma_model_config.dart
  src/core/runtime/local_gemma_runtime.dart
  src/core/runtime/platform_gemma_runtime.dart
  src/features/gemma_home/gemma_home_screen.dart
  src/features/prompt_lab/prompt_templates.dart
  src/features/skills/skill.dart
```

## 运行时抽象

`LocalGemmaRuntime` 是 Flutter 侧统一接口：

- `initialize(GemmaModelConfig config)`：初始化本地模型。
- `generate(GemmaRequest request)`：流式生成文本。
- `stop()`：停止当前生成。
- `dispose()`：释放模型资源。

Android 目标实现映射到原工程 `LlmChatModelHelper`：

- `EngineConfig.modelPath` -> `GemmaModelConfig.localModelPath(...)`
- `backend` -> GPU/CPU
- `visionBackend` -> 图片输入开启时 GPU
- `audioBackend` -> 声音输入开启时 CPU
- `ConversationConfig.systemInstruction` -> Skills 系统提示词
- `ConversationConfig.tools` -> Skills 工具提供器

桌面/iOS 先保持同一 Dart 接口，后续可接入对应平台本地后端。
