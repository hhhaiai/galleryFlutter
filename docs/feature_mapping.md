# 功能映射

## 对话

来源：

- `LlmChatModelHelper.initialize(...)`
- `LlmChatModelHelper.runInference(...)`

抽取后：

- Flutter 页面入口：`GemmaTaskId.chat`
- 统一请求结构：`GemmaRequest(prompt: ...)`
- 统一运行时：`LocalGemmaRuntime.generate(...)`

## 图片理解

来源：

- `Model.llmSupportImage`
- `EngineConfig.visionBackend`
- `runInference(images: List<Bitmap>)`

抽取后：

- Flutter 页面入口：`GemmaTaskId.askImage`
- 请求字段：`GemmaRequest.imagePaths`
- 原生桥接时需要把图片路径转换为平台侧 Bitmap / tensor 输入。

## 声音理解

来源：

- `Model.llmSupportAudio`
- `EngineConfig.audioBackend = Backend.CPU()`
- `runInference(audioClips: List<ByteArray>)`

抽取后：

- Flutter 页面入口：`GemmaTaskId.askAudio`
- 请求字段：`GemmaRequest.audioPaths`
- 原生桥接时需要把音频文件转换为 ByteArray。

## Prompt Lab

来源：

- `PromptTemplateConfigs.kt`
- 模板：Free form / Rewrite tone / Summarize text / Code snippet

抽取后：

- `lib/src/features/prompt_lab/prompt_templates.dart`
- 先保留核心模板和 prompt 拼接逻辑。

## Skills / Agent Chat

来源：

- `AgentChatTaskModule.kt`
- `SkillManagerViewModel.kt`
- `skill.proto`
- `assets/skills/*/SKILL.md`

核心机制：

1. 从 assets 和 DataStore 加载 Skills。
2. 生成包含 `___SKILLS___` 的系统提示词。
3. 通过 LiteRT-LM `ToolProvider` 暴露 `load_skill` / `run_intent` 等工具。
4. 使用 constrained decoding 提高工具调用稳定性。

抽取后：

- `lib/src/features/skills/skill.dart`
- 保留 Skill 数据结构、系统提示词、部分内置 skill 占位。
- 原生工具调用桥接待接入。
