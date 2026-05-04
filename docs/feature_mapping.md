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
- Android 实现：Flutter 通过 MethodChannel 把 `imagePaths` 传给 `MainActivity.kt`；Dart runtime 会先把图片请求转成明确视觉 prompt；原生端按 Google AI Edge Gallery 做法读取 EXIF 方向、按 1024x1024 采样 decode、旋转 Bitmap、转 PNG bytes 后加入 `Content.ImageBytes`，再把文本作为 `Content.Text` 放在图片之后调用 `sendMessageAsync(Contents.of(contents), ...)`。
- Android backend：多模态初始化必须使用 Gallery 同款 GPU 路线。Dart 侧图片能力开启时传 `accelerator: 'gpu'`；Kotlin 侧 `EngineConfig.backend = Backend.GPU()`，`visionBackend = Backend.GPU()`。此前 CPU 主 backend 或错误 vision backend 会触发 LiteRT-LM `Status Code: 12/13 / Failed to invoke the compiled model`。
- iOS 实现：Flutter 通过 `flutter_gemma` 的 `.litertlm` FFI 路径加载模型，初始化时显式 `supportImage: true` 与 `maxNumImages: 1`，发送时用 `Message.withImage(text:imageBytes:isUser:)`。
- iOS 稳定性策略：iOS `.litertlm` FFI vision session 不可靠复用，第二次图片请求可能失败或忽略图片。当前实现对每次图片请求执行 `forceReload`：关闭旧 chat session、关闭旧 `_flutterGemmaModel`、重新 `installModel/getActiveModel/createChat`，再发送图片；文字请求不做完整重启。
- Prompt 策略：图片默认 prompt 会被 `_visionPrompt()` 转成明确视觉问答指令；用户带文字时转成“以图片为主要证据回答用户请求”；Android 与 iOS 都走这套 prompt 包装，避免模型进入无图普通聊天。
- 真机验证：Android 与 iOS 均已完成真实图片发送、模型识别与回复验证；iOS 连续多次图片识别通过，当前以稳定性优先，牺牲少量二次启动速度。

## 声音理解 / 语音消息 / Live 语音通话

来源：

- `Model.llmSupportAudio`
- `EngineConfig.audioBackend = Backend.CPU()`
- `runInference(audioClips: List<ByteArray>)`
- Gallery 常量：`MAX_AUDIO_CLIP_COUNT = 1`、`MAX_AUDIO_CLIP_DURATION_SEC = 30`、`SAMPLE_RATE = 16000`

抽取后：

- Flutter 页面入口：`GemmaTaskId.askAudio`
- 请求字段：`GemmaRequest.audioPaths`
- 方案文档：`docs/audio_voice_live_design.md`
- UI 流程：点击 composer 语音按钮 → bottom sheet 选择「实时录音 / 选择语音文件 / Live 语音通话探索」→ 录音或音频文件附着到输入框 → 发送后用户消息气泡显示微信式语音波形卡片。
- 已发送语音展示：`_ChatMessage.audioAttachments` 保存语音路径、时长、波形；`_VoiceMessageCard` 显示播放按钮、波形条和时长；点击调用原生 `playAudio(path)` 播放。
- Android 实现：`MainActivity.kt` 新增 `AndroidAudioInput`，通过 `com.example.gemma_local_app/audio_input` 提供系统音频文件选择、`AudioRecord` 录音、`MediaPlayer` 播放；系统文件选择若拿到 m4a/mp3 等压缩音频，会先用 `MediaExtractor + MediaCodec` 解码为 PCM，再统一转成 16k mono 16-bit WAV；runtime 初始化时 `audioBackend = Backend.CPU()`；generate 时 Dart 先注入明确 audio prompt，原生再把第一条 `audioPath` 读为 bytes 并加入 `Content.AudioBytes`，顺序为图片、音频、文本；对 UNKNOWN_LENGTH 的系统 URI 会先复制到 cache 再解码。
- iOS 实现当前状态：`Info.plist` 添加麦克风权限文案，`IOSAudioInput.swift` 已接入文件选择、录音、播放、`audio_input_events` 电平事件；文件选择音频会统一转换为 16k mono 16-bit PCM WAV，并做 WAV header/时长校验。但真机验证显示 `flutter_gemma + Gemma-4-E2B-it` 音频请求会触发 `Failed to start streaming (code: 13)`，所以 `platform_gemma_runtime.dart` 当前显式拦截 `audioPaths`，Flutter UI 也暂时关闭 iOS 语音文件、实时录音和 Live 入口。
- 格式策略：当前录音与文件选择都尽量在原生侧落成 16k mono 16-bit PCM WAV，再送 `Content.AudioBytes`，降低模型端格式差异；Android 录音达到 30 秒上限会自动停止并回填附件；图片+语音混合输入会使用专门的混合媒体 prompt；Android/iOS 语音波形估算解析 WAV PCM 16-bit sample，不再用 RIFF header 字节估算音量，降低静音判断误差。
- Live 策略：Android Phase 1 已先落地固定切段/静音切段的伪实时通话（segment -> `GemmaRequest.audioPaths` -> AI 文字回复）；iOS 等 Gemma audio runtime 路径稳定后再打开，不能以非 Gemma ASR 作为本项目 Live 语音成功路径；最后 Phase 3 接 TTS。

## Prompt Lab

来源：

- `PromptTemplateConfigs.kt`
- 模板：Free form / Rewrite tone / Summarize text / Code snippet

抽取后：

- `lib/src/features/prompt_lab/prompt_templates.dart`
- 先保留核心模板和 prompt 拼接逻辑。
- 已修复模板插值：`Rewrite tone` / `Summarize text` / `Code snippet` 现在会真实插入用户输入，避免 `$input` 字面量进入本地 Gemma。

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
- `lib/src/features/skills/skill_repository.dart`
- 保留 Skill 数据结构、系统提示词、内置 skill 清单，并对齐 Gallery `assets/skills/*/SKILL.md` 的名称/说明/工具调用意图。
- Skills Hub：点击 composer 的 `Skills` 会打开 Hub 面板；支持启用/禁用内置 skills；支持从线上 `SKILL.md`、GitHub raw/blob URL、或包含 `SKILL.md` 链接的页面导入线上 skill；线上 skill 持久化到 Application Support 的 `online_skills.json`。
- SkillHub.cn：UI 中提供 `https://skillhub.cn/` 线上社区入口链接复制；当前不新增 `url_launcher` 依赖，先支持粘贴具体 Skill URL 导入。
- Android runtime：Skills 模式会启用 Gallery 同款 `ToolProvider` 方向的原生工具集，`ConversationConfig.tools = listOf(tool(GemmaSkillToolSet(...)))`，并打开 constrained decoding；已接 `loadSkill`、`runJs`、`runIntent` 三个工具形态。
- 当前工具执行边界：`loadSkill` 能返回内置/线上 skill instructions；`run_intent(send_email)` 会拉起 Android 邮件 Intent；Android 已内置 Gallery `assets/skills/*` 并通过本地 headless WebView 执行 bundled built-in `run_js`；image/webview 输出目前会以文字说明“UI 展示待接入”，线上/custom skill 的 JS 文件下载与执行仍待深化。
- iOS/Flutter 侧已把 Skills 模式下的 `loadSkill` / `runJs` / `runIntent` 作为 `flutter_gemma` tools 注册；`loadSkill` 可从 Dart enabledSkillDetails 返回 instructions 并回传模型继续生成，`runJs` / `runIntent` 仍返回诚实 `pending_bridge`，避免伪装已执行。
