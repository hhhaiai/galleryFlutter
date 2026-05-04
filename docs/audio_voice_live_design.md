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
- 发送给模型时读取第一条 `audioPaths.take(1)`，解析 WAV `data` chunk，送入 `Content.AudioBytes` 的是 16k / mono / 16-bit raw PCM，不包含 RIFF/WAVE header。
- `EngineConfig.audioBackend = Backend.CPU()`。

注意：当前 Android runtime 对 UI/播放保留 16k mono PCM WAV 文件，但模型输入会剥离 WAV header，仅把 raw PCM 交给 `Content.AudioBytes`，以对齐 Google AI Edge Gallery 的 Ask Audio 路径。

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
- flutter_gemma API 已存在 `Message.withAudio(...)`、`supportAudio`、`enableAudioModality`、`addAudio(...)` 能力，但当前真机验证显示 `Gemma-4-E2B-it` 音频链路会触发 `Failed to start streaming (code: 13)`。
- 因此 iOS 运行时默认继续拦截 `audioPaths`，暂不暴露 audio 给普通用户；已增加固定 WAV harness：仅在 `--dart-define=GEMMA_IOS_AUDIO_PROBE=true` 时打开 iOS 语音入口，并把 16k mono PCM WAV 的 `data` chunk 剥离为 raw PCM 后送 `Message` audioBytes，用于真机专项复现/验证。目标发送方式仍是：
- iOS audio input 的波形估算也已改为解析 WAV PCM 16-bit sample，保持和 Android 一致。

```dart
fg.Message.withAudio(
  text: _audioPrompt(prompt),
  audioBytes: rawPcm16Bytes,
  isUser: true,
)
```

当前稳定策略：

- 与图片一致，音频属于多模态请求；如果未来重新打开 iOS audio runtime，每次音频请求先 `forceReload` 重建 flutter_gemma model/client/session，优先保证稳定。
- 普通文字请求不做完整重启。

已补基础能力：iOS 原生 `audio_input` channel 已接入文件选择/录音/播放，`audio_input_events` 已能输出录音状态和电平事件，文件选择音频会统一转换为 16k mono 16-bit PCM WAV，并做 WAV header/时长校验；Dart probe 会再次校验并只取 raw PCM bytes。

待补：使用 `GEMMA_IOS_AUDIO_PROBE=true` 在真机跑固定 WAV / 录音专项验证。验证前默认 UI 继续关闭 iOS 语音理解入口，避免影响文字/图片稳定。

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
- iOS：固定 WAV harness 验证 `flutter_gemma Message.withAudio(...)`；若仍 code 13，记录 Gemma iOS audio blocker 并暂停本项目内 iOS audio 深测，不用非 Gemma ASR 方案替代验收。

P1：

- Live 语音通话 Phase 1：继续真机验证分段录音 + 静音切段 + 队列串行推理 + 文字回复。
- UI 增加 Live 语音页/弹层：正在听、波形、停止、当前段处理状态。
- 增加失败重试和“重新发送语音”按钮。
- 当前已补单段失败隔离：普通片段失败显示错误后继续，audio runtime 不可用则停止 Live，避免后台循环刷失败。

P2：

- Live Phase 2：原生 PCM streaming + VAD。
- AI 文字回复接 TTS，形成完整语音对话。
- 多平台桌面音频文件支持。
