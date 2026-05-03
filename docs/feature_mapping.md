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
- UI 流程：点击 composer 图片按钮 → bottom sheet 选择「拍照 / 从相册选择」→ `image_picker` 返回本地路径 → 输入框上方显示可删除缩略图 → 发送后用户消息气泡展示图片缩略图。
- 已发送图片展示：`_ChatMessage.imagePaths` 保存本地图片路径；`_SentImagePreviewGrid` 在消息气泡中展示图片卡片；点击图片打开 `_ImagePreviewDialog`，支持全屏查看、左右翻页和 `InteractiveViewer` 缩放。
- Android 实现：Flutter 通过 MethodChannel 把 `imagePaths` 传给 `MainActivity.kt`；原生端按 Google AI Edge Gallery 做法读取 EXIF 方向、按 1024x1024 采样 decode、旋转 Bitmap、转 PNG bytes 后加入 `Content.ImageBytes`，再把文本作为 `Content.Text` 放在图片之后调用 `sendMessageAsync(Contents.of(contents), ...)`。
- Android backend：多模态初始化必须使用 Gallery 同款 GPU 路线。Dart 侧图片能力开启时传 `accelerator: 'gpu'`；Kotlin 侧 `EngineConfig.backend = Backend.GPU()`，`visionBackend = Backend.GPU()`。此前 CPU 主 backend 或错误 vision backend 会触发 LiteRT-LM `Status Code: 12/13 / Failed to invoke the compiled model`。
- iOS 实现：Flutter 通过 `flutter_gemma` 的 `.litertlm` FFI 路径加载模型，初始化时显式 `supportImage: true` 与 `maxNumImages: 1`，发送时用 `Message.withImage(text:imageBytes:isUser:)`。
- iOS 稳定性策略：iOS `.litertlm` FFI vision session 不可靠复用，第二次图片请求可能失败或忽略图片。当前实现对每次图片请求执行 `forceReload`：关闭旧 chat session、关闭旧 `_flutterGemmaModel`、重新 `installModel/getActiveModel/createChat`，再发送图片；文字请求不做完整重启。
- Prompt 策略：图片默认 prompt 会被 `_visionPrompt()` 转成明确视觉问答指令；用户带文字时转成「请根据图片内容回答：...」，避免模型进入无图普通聊天。
- 真机验证：Android 与 iOS 均已完成真实图片发送、模型识别与回复验证；iOS 连续多次图片识别通过，当前以稳定性优先，牺牲少量二次启动速度。

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
