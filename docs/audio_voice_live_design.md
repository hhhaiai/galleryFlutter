# 语音理解、语音消息与 Live 语音通话实现方案

## 目标

移动端需要补齐三类语音能力：

1. 语音文件：用户从系统文件选择音频，作为一条语音消息发给 Gemma。
2. 实时录音：用户像微信一样录一段语音，发送后消息气泡显示语音波形卡片，并可点击播放。
3. Live 语音通话探索：用户可以持续说话，App 分段处理语音并把内容发给 AI；AI 第一阶段只需要文字回复，后续再加 TTS 语音回复。

所有语音消息必须满足：

- 发送前可在输入框上方预览。
- 发送后用户消息气泡不只显示 `[语音 × 1]`，而是显示可点击播放的语音卡片。
- 语音卡片形态参考微信等实时通讯软件：播放按钮、波形条、时长。
- 语音文件与录音都进入 `GemmaRequest.audioPaths`，由移动端 runtime 转给本地 Gemma。

## Google AI Edge Gallery 参考

参考路径：

```text
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/data/Consts.kt
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/common/Utils.kt
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/ui/llmchat/LlmChatModelHelper.kt
/Users/sanbo/Desktop/gallery/Android/src/app/src/main/java/com/google/ai/edge/gallery/ui/common/AudioAnimation.kt
```

关键结论：

- Gallery 模型配置支持 `llmSupportAudio`。
- `EngineConfig.audioBackend = Backend.CPU()`，音频后端应走 CPU。
- `MAX_AUDIO_CLIP_COUNT = 1`，先保持单条音频稳定。
- `MAX_AUDIO_CLIP_DURATION_SEC = 30`，单段音频建议控制在 30 秒以内。
- `SAMPLE_RATE = 16000`，Gallery 对 wav 做 16k/mono/16-bit PCM 归一化。
- 推理内容构造顺序：`Content.ImageBytes`、`Content.AudioBytes`、最后 `Content.Text`。
- Gallery 的 `AudioAnimation.kt` 可作为实时录音波形视觉参考。

## 当前第一阶段实现

### Flutter UI

新增文件：

```text
lib/src/features/gemma_home/audio_input_service.dart
```

新增能力：

- `AudioInputService.pickAudioFile()`：调用原生系统音频文件选择。
- `AudioInputService.startRecording()` / `stopRecording()`：调用原生录音。
- `AudioInputService.play(path)`：点击语音卡片播放。
- `AudioAttachment` 保存 `path`、`durationMs`、`waveform`。

主界面：

```text
lib/src/features/gemma_home/gemma_home_screen.dart
```

实现：

- 点击「语音」按钮弹出 bottom sheet：
  - 实时录音 / 停止录音
  - 选择语音文件
  - Live 语音通话探索说明
- 输入框上方显示 `_AttachedAudioStrip`。
- 发送后 `_ChatMessage.audioAttachments` 保存语音消息。
- 用户消息气泡显示 `_VoiceMessageGrid` / `_VoiceMessageCard`。
- `_VoiceMessageCard` 包含播放按钮、波形条、时长，点击调用原生播放。
- 没有文字时默认 prompt 为：`请识别并总结这段语音内容。`；Android runtime 发送前还会把音频请求包装成明确 audio prompt，要求识别语音/声音/数字/姓名/关键信息，并在不清楚时说明不确定点；图片+语音同时存在时使用混合媒体 prompt。

### Android 原生

修改文件：

```text
android/app/src/main/AndroidManifest.xml
android/app/src/main/kotlin/com/example/gemma_local_app/MainActivity.kt
```

实现：

- 添加 `RECORD_AUDIO` 权限。
- 新增 MethodChannel：

```text
com.example.gemma_local_app/audio_input
```

方法：

```text
pickAudioFile()
startRecording()
stopRecording()
cancelRecording()
playAudio(path)
stopPlayback()
```

当前 Android 音频输入：

- 录音使用 `AudioRecord` 直接录制 16k / mono / 16-bit PCM，并封装成 WAV 保存到 cacheDir；达到 30 秒上限时原生事件会带 `reason=maxDuration`，Flutter 自动停止并把录音附件回填到输入框。
- 语音文件通过系统 `ACTION_OPEN_DOCUMENT audio/*` 选择；若是 m4a/mp3 等压缩音频，原生侧会先解码为 PCM，再统一封装成 16k / mono / 16-bit WAV 保存到 cacheDir。
- 播放使用 `MediaPlayer`。
- 波形估算解析 WAV 的 PCM 16-bit data chunk 后按 sample 振幅分桶，不再直接统计包含 RIFF header 的原始字节；Live 静音判断因此更接近真实音量。
- 发送给模型时读取第一条 `audioPaths.take(1)`，解析并归一化 WAV `data` chunk 后重新构造完整 16k / mono / 16-bit WAV，送入 `Content.AudioBytes`。这与 Google AI Edge Gallery 的 `ChatMessageAudioClip.genByteArrayForWav()` 路径一致。
- `EngineConfig.audioBackend = Backend.CPU()`。

注意：当前 Android runtime 对 UI/播放保留 16k mono PCM WAV 文件，模型输入也保留 WAV 容器。旧版“剥离 WAV header 后只发 raw PCM”的说明已废弃，因为 Gallery 的 Ask Audio 路径实际是 raw PCM + 44 字节 WAV header。

### iOS

修改文件：

```text
ios/Runner/Info.plist
ios/Runner/IOSAudioInput.swift
ios/Runner/AppDelegate.swift
lib/src/core/runtime/platform_gemma_runtime.dart
```

实现：

- 添加 `NSMicrophoneUsageDescription`。
- 新增 `IOSAudioInput.swift`，通过同一个 `com.example.gemma_local_app/audio_input` MethodChannel 提供：
  - `UIDocumentPickerViewController` 选择语音文件。
  - `AVAudioRecorder` 录制 16k / mono / 16-bit PCM WAV 语音。
  - `AVAudioPlayer` 点击播放已发送语音。
- flutter_gemma API 已存在 `Message.withAudio(...)`、`supportAudio`、`enableAudioModality`、`addAudio(...)` 能力；当前产品基线要求 Android / iOS 都只使用 `Gemma-4-E2B-it`，iOS 仍绕过插件高级封装，直接使用 LiteRT-LM raw FFI Conversation JSON。
- iOS 原生 `audio_input` channel 已接入文件选择/录音/播放，`audio_input_events` 已能输出录音状态和电平事件，文件选择音频会统一转换为 16k mono 16-bit PCM WAV，并做 WAV header/时长校验。
- 2026-05-14 修复了 iOS 语音识别失败的关键输入格式问题：Dart 侧不再剥离 WAV `data` chunk 后只发送 raw PCM，而是保留完整 WAV 容器；针对 people iPhone 复测出现的 `Failed to start streaming (code: 13)`，当前会进一步把 iOS/macOS 常见的 `FLLR` 等 padding/metadata chunk 规整为最小 44-byte `RIFF/fmt/data` 16k mono 16-bit PCM WAV 后再传给 FFI。剥离 header 会导致 LiteRT-LM 侧拿到无容器的 opaque PCM blob；带额外 chunk 的容器则可能触发 iOS LiteRT-LM streaming code 13。
- 与图片一致，音频属于多模态请求；每次 iOS media request 会重建 raw FFI client/conversation，避免文字会话模板与多模态 JSON 混用。audio-only 请求优先使用 CPU backend，并在失败时 fallback GPU，错误会带出已尝试 backend。默认走 path-based JSON + 非流式 `sendMessage(...)`，并固定 text -> image -> audio 顺序，让 LiteRT-LM data processor 负责音频预处理。

当前 people iPhone profile smoke 已验证固定 WAV 能被模型处理并返回 `AUDIO_RECEIVED`。后续真机专项仍需覆盖自然录音、选择 WAV、选择 m4a/mp3 后转 WAV，以及 Gemma 实际转写质量。

## Live 语音通话方案探索

Live 通话不是传统电话通话，而是“持续语音输入 + 本地模型连续理解 + AI 文字回复”。第一阶段 AI 暂时文字回复即可。

推荐架构：

```text
Flutter LiveVoiceController
  ↓ 控制状态：idle / listening / processing / replying
Native Audio Stream Recorder
  ↓ 16k mono PCM 分帧
Voice Activity Detection / Silence Detection
  ↓ 每 2-5 秒或静音边界切段
Segment Queue
  ↓ audio segment path / pcm bytes
LocalGemmaRuntime.generate(audioPaths: [segment], prompt: livePrompt)
  ↓ streaming text response
Chat transcript append assistant text
```

分阶段：

### Phase 1：伪实时分段通话

- 用户点 Live 开始。
- 当前实现先以最长约 7 秒为上限生成音频片段，并已接入基于电平的静音切段（最短约 1.6 秒，静音保持约 850ms）。
- 每段进入 `GemmaRequest.audioPaths`。
- AI 对每段输出文字回复。
- 优点：复用当前音频文件/录音链路，实现快，稳定性好。
- 缺点：不是真正 token-level streaming STT，延迟约 3-8 秒。

### Phase 2：实时 PCM + VAD

- 原生侧使用 `AudioRecord` / `AVAudioEngine` 获取 PCM frame。
- 实时计算音量和 VAD。
- 缓冲到一句话边界后送 Gemma。
- UI 显示实时波形和“正在听”。
- 优点：体验接近 live conversation。
- 缺点：需要音频格式、队列、打断、背压处理。

### Phase 3：双向实时语音

- AI 文字回复后接 TTS，形成语音回复。
- 支持打断：用户开始说话时停止 TTS 和当前生成。
- 支持半双工/全双工策略。
- 当前不做，避免影响本地 Gemma 推理稳定性。

## 方案对比

| 方案 | 优点 | 缺点 | 适用阶段 |
| --- | --- | --- | --- |
| Flutter 插件 record/file_picker/just_audio | 跨平台快 | 依赖 pub、平台差异、插件注册风险 | 可选后续 |
| 项目自有 MethodChannel | 可控、少依赖、方便原生格式转换 | Android/iOS 都要写原生 | 当前采用 |
| 直接发 m4a/mp3 bytes 给 Gemma | 实现最快，UI 可先闭环 | 模型可能更偏好 PCM/WAV | 当前第一阶段 |
| 统一转 16k mono PCM | 对齐 Gallery，模型输入更稳定 | 需要解码/重采样实现 | 下一阶段 P0 |
| Live 分段伪实时 | 稳定、实现快 | 延迟比真正 live 高 | 推荐先做 |
| 真流式 PCM + VAD | 体验最好 | 工程复杂，需处理背压/打断 | 后续 P1 |

## 后续待办

P0：

- Android：真机验证语音文件、实时录音、点击播放、Gemma 语音理解；重点覆盖应用内录音、标准 wav、m4a、mp3、第三方 App 导出音频。
- iOS：真机验证完整 WAV bytes FFI 路径；若仍 code 13 或不识别，记录 Gemma/iOS FFI audio blocker，不用非 Gemma ASR 方案替代验收。

P1：

- Live 语音通话 Phase 1：继续真机验证分段录音 + 静音切段 + 队列串行推理 + 文字回复。
- UI 增加 Live 语音页/弹层：正在听、波形、停止、当前段处理状态。
- 增加失败重试和“重新发送语音”按钮。
- 当前已补单段失败隔离：普通片段失败显示错误后继续，audio runtime 不可用则停止 Live，避免后台循环刷失败。

P2：

- Live Phase 2：原生 PCM streaming + VAD。
- AI 文字回复接 TTS，形成完整语音对话。
- 多平台桌面音频文件支持。


## 2026-05-14 语音识别修复记录

本轮针对“iOS 语音不识别，Android 也不识别”做了代码级收口：

1. iOS FFI 音频输入格式修复：
   - 文件：`lib/src/core/runtime/platform_gemma_runtime.dart`
   - `_readGemmaPcm16FromWav` 改为 `_readGemmaWavBytes`。
   - 保留完整 16k mono 16-bit WAV bytes 传给 `LiteRtLmFfiClient.chatRaw(audioBytes: ...)`。
   - 依据：`flutter_gemma 0.14.1` 官方 example 录音后直接发送原始 WAV；Google Android Gallery 也是 raw PCM 重新加 WAV header 后传 `Content.AudioBytes`。

2. Android 录音保存稳定性修复：
   - 文件：`android/app/src/main/kotlin/com/example/gemma_local_app/MainActivity.kt`
   - `stopRecording()` 先主动 `AudioRecord.stop()` 以打断阻塞中的 `read()`，再等待录音线程完成 WAV 写入。
   - 如果线程未结束或文件仍为空，不再把未完成/空 WAV 交给模型，而是返回 `RECORD_SAVE_FAILED`。

3. 默认语音 prompt 加强：
   - 默认语音输入先要求“准确转写语音”，再总结/回答。
   - 对姓名、数字、日期、短语和不确定点做明确要求，减少模型只泛泛总结或忽略语音的概率。

验证：

- `flutter analyze`：通过。
- `tool/flutter_test_short_builddir.sh`：通过，9 tests。
- `./android/gradlew -p android :app:assembleDebug --offline`：通过。
- `flutter build ios --simulator --debug --no-pub`：通过，产物 `build/ios/iphonesimulator/Runner.app`。
- Android 真机 `adb install -r -d build/app/outputs/flutter-apk/app-debug.apk`：通过；启动后模型仍为 `已下载`，未见当前进程 FATAL。

限制：

- people iPhone 已重新 USB 连接；当前已完成 iOS code 13 输入格式/CPU backend 修复与单元测试，仍需把最新构建安装到 people iPhone 并在 UI 重新发送语音确认真实转写。
- Android 已完成安装/启动/模型文件存在验证，并通过 UI 录音发送进入 LiteRT-LM audio runtime；由于本轮音源来自电脑外放/环境噪声，转写质量仍需用户对着手机清晰复测。

## 2026-05-14 录音交互稳定性补强

- 录音中再次点击 composer「语音」按钮会直接停止录音并附加到输入框，不再先弹出 bottom sheet，避免“看起来点了停止但还在录”的误操作。
- 点击「发送」时如果仍处于录音中，Flutter 会先调用 `stopRecording()` 并把生成的 WAV 附件加入本次请求；停止失败则不发送，避免空语音或旧语音误发。
- Android 原生 `AndroidAudioInput` 增加保存日志：`recording saved`、`recording ready`、`recording save incomplete`，便于 adb/logcat 验证录音文件是否真正写完。
- Android 真机验证记录：录音中点击 composer 语音按钮可直接停止并出现附件；发送后 logcat 出现 `GemmaLiteRtRuntime: audio input ready: wavBytes=176044`，界面输出“转录：你好，这是第二四期音讯测试。请实别这句。”和总结，说明录音停止、附件发送、LiteRT-LM audio runtime 与模型转写链路已打通。

## 2026-05-14 Android 语音复测纠偏

- 复测纠偏：直接用手机麦克风录电脑外放时，Gemma 会明显幻听，不能作为语音识别质量结论；将同一个 UI 附件文件替换为清晰 16k mono WAV 后复测，logcat 显示 `audio input ready: wavBytes=246564`，UI 转写为“你好，这是一个非常清晰的语音测试。今天是5月14日，请准确地读出这句。”，说明 App audio 文件链路可用，主要风险在麦克风采集/环境声与模型 ASR 精度。

### Google AI Edge iOS 对齐结论（2026-05-14，历史记录，已被 2026-05-20 产品基线覆盖）

当时曾依据官方 `google-ai-edge/gallery/model_allowlists/ios_1_0_0.json` 尝试让 iOS 使用 Gemma 3n E2B/E4B 来验证音频路径。这个结论现在只保留为历史排查记录；2026-05-20 之后的产品基线已经改为：Android 与 iOS 都统一使用 `Gemma-4-E2B-it`，不能再把 iOS 默认切回 Gemma 3n。

限制：`google/gemma-3n-E2B-it-litert-lm` 是 Hugging Face gated repo；没有授权 token 或本地预下载文件时，iOS 下载会被 401 拒绝。

### 2026-05-14 方案切换记录

当前继续按“逐个方案验证”推进：

1. Gemma 4 + blob/base64 audio JSON：people 手测仍报 `Failed to start streaming (code: 13)`，不再作为稳定路线。
2. PhoneClaw 对齐方案：audio-only 改成临时 WAV 文件路径 JSON，并优先非流式 `sendMessage`；该实现已落地，并已在 people iPhone profile smoke 中返回真实模型输出 `AUDIO_RECEIVED`。
3. 官方 iOS allowlist 方案：曾验证 iOS `Gemma-3n-E2B-it` 路线；当前已废弃为默认产品路线，只能作为历史对照，不能覆盖 Android / iOS 统一 `Gemma-4-E2B-it` 的最新要求。
4. iOS 26 启动稳定性：当前连接的 iPhone13 上 `FlutterGemmaPlugin.register(with:)` 会在启动时 SIGSEGV，因此 iOS 暂时不注册 flutter_gemma 插件，运行时改为 raw FFI；iOS Skills/function calling 暂停，避免用不可验证路径冒充成功。

### 2026-05-14 继续测试：iOS native direct session 方案

在 PhoneClaw path JSON 与 Dart raw FFI 之后，新增第三条 iOS 运行时路径：`IOSGemmaRuntime.swift` 通过 `dlopen/dlsym` 直接调用 LiteRT-LM C API 的 `litert_lm_session_generate_content(...)`，输入为 `LiteRtLmInputData(type=audio/text)`，绕过：

- `flutter_gemma` 插件注册；
- Dart FFI `LiteRtLmFfiClient` Conversation JSON；
- `conversation_send_message_stream` 的 streaming code 13 路径。

结论：native direct session 不作为默认 iOS audio 路径，因为真机错误显示底层 `session_generate_content` 不会自动跑 LiteRT-LM `AudioPreprocessor`，会报 `Audio must be preprocessed before being used in SessionAdvanced.`；它只保留为显式实验开关 `GEMMA_IOS_USE_NATIVE_DIRECT=1`。默认稳定路径是 Dart raw FFI Conversation API：`content` 顺序固定为 text -> image -> audio，audio-only 使用 path-based JSON + 非流式 `sendMessage`，让 LiteRT-LM data processor 负责音频预处理。


### 2026-05-14 people iPhone 复测结论：为什么会提示“请提供音频”

本次用户手测“已经发了音频，但模型提示请提供音频”后，排查结论如下：

- 不是录音为空：从 people iPhone container 拉取 `tmp/voice_1778748629479.wav`，文件为 16kHz / mono / int16 WAV，约 6.53 秒、208KB，存在有效峰值与 RMS。
- 旧 iOS JSON 组包顺序是 audio -> image -> text；LiteRT-LM 官方 data processor 测试覆盖的是 text -> audio，真机表现证明 audio 放在 text 前面时，模型可能完成 prefill 但回答像“没有音频”。
- 已修复 `buildIosPathMessageJsonForTesting(...)`：默认顺序改为 text -> image -> audio，并用单元测试锁住，避免再次回退。
- 已新增 iOS profile smoke 结果文件 `Library/Application Support/gemma_ios_audio_smoke_result.json`，用于 devicectl 拉取真实模型结果，而不是只依赖 Flutter debugPrint。
- people iPhone profile smoke 验证通过：安装 `build/ios/iphoneos/Runner.app` 后启动，拉取结果为 `status=success`、`response=AUDIO_RECEIVED`，证明当前默认 path JSON + Conversation API 路径能让 LiteRT-LM 收到并处理音频。

仍需继续验证的是用户自然语音的转写质量；稳定性验收不能只看“收到音频”，还要用清晰真人语音确认不再输出“请提供音频”。
