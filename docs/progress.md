# 开发进度

## 已完成

- [x] 检查来源工程位置：`/Users/sanbo/Desktop/gallery`
- [x] 确认来源工程是 Google AI Edge Gallery Android 工程
- [x] 定位 Gemma-4-E2B-it allowlist 配置
- [x] 确认 Gemma-4-E2B-it 支持：图片、声音、对话、Skills、Prompt Lab
- [x] 新建 Flutter 工程：`/Users/sanbo/Desktop/gallery/gemma_local_app`
- [x] 创建 iOS / Android / macOS / Windows / Linux 平台目录
- [x] 抽取单模型配置到 Dart
- [x] 建立 LocalGemmaRuntime 统一接口
- [x] 建立主界面骨架
- [x] 建立 Prompt Lab 模板骨架
- [x] 建立 Skills 数据结构和系统提示词骨架
- [x] 实现侧边设置 `Models` 中下载 Gemma-4-E2B-it
- [x] 实现 `.gallerytmp` 临时文件和 HTTP Range 断点续传
- [x] Android 模型下载改为 WorkManager 系统后台下载
- [x] Android 下载支持最多 4 路 HTTP Range 并发分片，并通过 `.gallerytmp.partN` 支持断点续传
- [x] 修复 Android Runtime 初始化路径与 WorkManager 下载路径不一致导致的 `Model file not found`
- [x] Android 模型文件路径调整为扁平路径：`/storage/emulated/0/Android/data/com.example.gemma_local_app/files/gemma-4-e2b-it.litertlm`
- [x] 增加旧嵌套路径已下载模型到新扁平路径的迁移逻辑
- [x] 修复发送文字后 Android 5s input dispatching ANR：LiteRT-LM 初始化/生成移到后台单线程，首轮配置降为 CPU + maxTokens 1024
- [x] 聊天气泡支持 Markdown 渲染和可选中文本，覆盖用户输入与模型输出
- [x] 参考 Google AI Edge Gallery 已上架 iOS App Store、Gallery README、LiteRT-LM iOS/macOS prebuilt 等事实，移除 iOS 死胡同式“不支持”文案，改为 iOS 下载可用、推理桥接接入中的行动状态
- [x] iOS 模型下载接入 Swift `URLSessionConfiguration.background`，并修复 `.gallerytmp` + HTTP Range 断点续传：206 追加 partial，200 覆盖重下，避免生成损坏模型
- [x] Dart 前台下载兜底同步修复 Range 被忽略时错误 append 的坏文件风险
- [x] iOS runtime channel 原生注册：Flutter iOS 不再走 Dart Placeholder/占位输出；已新增 `IOSGemmaRuntime.swift` 验证模型文件并接收 generate 调用
- [x] Xcode/Swift toolchain 已升级到 Xcode 26.4.1 / Swift 6.3.1，`MediaPipeTasksGenAI 0.10.35` Pod 已启用并成功链接
- [x] iOS 真实文字对话 runtime 已接入：`IOSGemmaRuntime.swift` 使用 `LlmInference.Options(modelPath:)` 初始化模型，创建 `LlmInference.Session`，通过 `generateResponseAsync()` 把 token 经 `runtime_events` EventChannel 流式返回 Flutter
- [x] 移除 Dart 层 iOS “还没有接通 / 不支持”旧文案；iOS 现在应进入原生 MethodChannel runtime。若安装包仍显示旧文案，说明手机上仍是旧构建或安装未成功覆盖
- [x] 通过 GitHub API 扫描 `google-ai-edge` 公开仓库，并把与 iOS 真对话相关的 `gallery`、`LiteRT-LM`、`LiteRT`、`mediapipe`、`mediapipe-samples` 参考结论同步到 `docs/google_ai_edge_ux_design.md`
- [x] iOS 模型下载确认走系统后台 `URLSessionConfiguration.background`，并增加已下载模型恢复：refresh/download 会扫描 Application Support、Documents、Caches 中已有的 `gemma-4-E2B-it.litertlm` / 小写文件名，发现完整文件后迁移到当前标准目录，避免重复下载
- [x] iOS Release 已重新编译并运行到 iPhone：`flutter run -d 00008120-000605C42244201E --release --no-resident` 安装启动成功
- [x] 修复 iOS `MissingPluginException: no implementation found for method down on channel com.example.gemma_local_app/model_download`：AppDelegate/SceneDelegate 双路径注册原生 channel，并在 iOS manager 同时兼容 `download` 与旧误调用 `down` 方法名
- [x] 图片入口升级为真实附件流程：点击图片弹出「拍照 / 从相册选择」二选项，拍照或选择后图片缩略图附着在输入框上方，可删除，可附带文字一起发送
- [x] Android 图片消息接入 LiteRT-LM：参考 Google AI Edge Gallery，启用 `supportImage` 时固定 `visionBackend = Backend.GPU()`，并将图片按 1024x1024 采样、读取 EXIF 方向并旋转后转为 PNG `Content.ImageBytes`，避免大图/错误 vision backend 触发 LiteRT-LM `Status Code: 12/13 / Failed to invoke the compiled model`
- [x] iOS 图片消息接入 flutter_gemma：`.litertlm` FFI 路径启用 `supportImage` 与 `maxNumImages: 1`，选择图片后用 `Message.withImage` 把图片 bytes 与文本一起发送；为避免第二次图片识别失败/忽略图片，每次图片请求完整重建 vision runtime/model client
- [x] 已发送图片 UX 完成：用户消息气泡展示真实图片缩略图，不再只显示 `[图片 × 1]`；点击缩略图可全屏预览、缩放，多图可翻页
- [x] 图片识别真机测试成功：Android 与 iOS 均已完成真实图片发送、模型识别与回复验证；iOS 连续多次图片识别通过，当前以稳定性优先
- [x] 补齐图片能力依赖与权限：`image_picker`、Android `CAMERA`/camera feature、iOS `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription`
- [x] 语音消息第一阶段 UI 完成：点击语音按钮可选择「实时录音 / 选择语音文件 / Live 语音通话探索」；录音或文件发送前附着到输入框；发送后用户消息气泡显示微信式语音波形卡片、播放按钮和时长，不再只显示 `[语音 × 1]`
- [x] Android 语音输入第一阶段接入：新增 `com.example.gemma_local_app/audio_input` MethodChannel，支持系统音频文件选择、`AudioRecord` 录音、`MediaPlayer` 点击播放；Android Manifest 增加 `RECORD_AUDIO`
- [x] Android 语音文件选择补齐格式兼容：对 file picker 选中的 m4a/mp3 等压缩音频，原生侧会先解码为 PCM，再统一转成 16k mono 16-bit WAV 后附着到消息，避免运行时只认 WAV 导致选择文件后无法理解
- [x] Live 语音通话 Phase 1 已具备基本可用性：可直接开启/停止，最长约 7 秒切段并支持电平静音切段后串行推理；同时补了停止递归问题和静音片段跳过，避免 Live 在安静环境中持续刷空回复
- [x] Live 语音通话前台体验改为连续通话态：新增全屏 Live overlay、持续时长、统一 AI 回复预览，并让后台分段录音与多次音频推理对用户尽量无感
- [x] Android 音频 runtime 已重新按 Gallery 路线接入：显式音频请求会启用 `audioBackend = Backend.CPU()` 并把第一条音频作为 `Content.AudioBytes` 发送；当前仍需真机专项验证多来源音频稳定性
- [x] Android audio 发送前稳健性补强：`readAudioForGemma(...)` 现在对所有 WAV 输入都解析 data chunk，并在发送给 `Content.AudioBytes` 前统一变成 16k mono 16-bit raw PCM；WAV 文件仍只用于 UI 播放/波形，不把 RIFF header 传给模型
- [x] iOS 音频 runtime 风险回退：`Info.plist` 和原生 audio input 骨架保留，但为避免 `failed to start streaming` 影响文字/图片稳定，暂不启用 `Message.withAudio(...)`；下一步完成音频格式归一化、固定 WAV harness 和真机专项验证后再决定是否开启
- [x] iOS 真机重新验证确认：当前 `flutter_gemma` + `Gemma-4-E2B-it` 音频链会在实时录音时触发 `Failed to start streaming (code: 13)`；已在 Flutter 层显式关闭 iOS 语音输入 / Live，避免继续暴露不稳定能力
- [x] iOS audio input 基础补强：`IOSAudioInput.swift` 增加 `audio_input_events`，录音电平事件，文件选择音频统一转 16k mono 16-bit PCM WAV，并对 WAV header/时长做校验；iOS audio runtime 仍保持关闭
- [x] iOS 固定 WAV harness 第一阶段：默认仍关闭 iOS 语音入口；仅在 `--dart-define=GEMMA_IOS_AUDIO_PROBE=true` 时允许 iOS 录音/文件入口，并把 16k mono PCM WAV 剥离为 raw PCM 后走 `flutter_gemma Message` audioBytes，用于真机复现/验证 Gemma 原生 audio code 13，不作为发布能力
- [x] Live 语音通话方案已整理：`docs/audio_voice_live_design.md` 记录分段伪实时、PCM streaming + VAD、TTS 双向语音三个阶段，以及方案对比和架构
- [x] 文字/Skills prompt 质量补强：Android `generate` 不再丢失 `systemPrompt` / `enabledSkillNames`；Dart runtime 会把 system instructions、enabled skills 与用户请求组合成 contextual prompt 后送入本地 Gemma，iOS 文字路径也复用同一逻辑
- [x] 图片/音频 prompt 质量补强：Android 图片请求也会注入明确视觉指令；Android audio 请求会注入明确语音理解指令；图片 + 音频混合请求会明确同时利用两类媒体证据
- [x] Android 录音 30 秒上限状态修复：原生 `audio_input_events` 在达到上限时发送 `reason=maxDuration`，Flutter 自动停止并把录音附件回填到输入框，避免 UI 卡在录音中或录音文件丢失
- [x] Android 系统音频选择兼容补强：增加 URI read permission；对 DocumentProvider 返回 UNKNOWN_LENGTH 的音频，先复制到 cache 临时文件再交给 `MediaExtractor` 解码，覆盖云盘/文件管理器等非常规来源
- [x] 图片+语音混合输入质量补强：无文字输入时使用专门的“结合图片和语音”默认 prompt，不再误用纯图片 prompt
- [x] Live 语音错误隔离补强：单段处理失败会显示错误并继续/停止，不再让后台 processor 无提示崩掉或循环刷失败
- [x] Prompt Lab 质量修复：`Rewrite tone` / `Summarize text` / `Code snippet` 模板现在真实插入用户输入，不再把 `$input` 字面量发给 Gemma
- [x] Skills prompt 质量补强：内置 skills 对齐 Gallery `assets/skills/*/SKILL.md` 的名称/说明/工具调用意图；Android 已支持部分原生工具，iOS/Dart 或待接工具不可伪装已执行
- [x] Skills Hub 第一阶段：点击 `Skills` 打开 Hub 面板；支持内置 skills 启用/禁用；支持粘贴线上 `SKILL.md` / GitHub raw/blob / 包含 `SKILL.md` 链接的页面导入；线上 skill 保存到 Application Support `online_skills.json`
- [x] SkillHub.cn 入口：Hub 面板提供 `https://skillhub.cn/` 链接复制，作为线上 skills 社区入口；当前不新增外部打开链接依赖
- [x] SkillHub.cn 目录浏览/搜索第一阶段：Hub 面板接入 `https://api.skillhub.cn/api/skills` 公开目录，可按关键词搜索并从 `/api/v1/skills/{slug}/file?path=SKILL.md` 导入 `SKILL.md`；当前只导入 instructions 给本地 Gemma，不下载或执行远端 `scripts/assets`
- [x] SkillHub.cn `SKILL.md` 完整性校验：导入前读取 `/api/v1/skills/{slug}/files` 的 `sha256`，下载后按原始 bytes 校验，不匹配或缺失 hash 直接拒绝；本地保存 `sourceSha256` / `sha256Verified` 并在 Hub 列表展示短 hash
- [x] Android Skills 工具桥接第一阶段：Skills runtime 启用 `ToolProvider` / constrained decoding；支持 `loadSkill` 返回内置/线上 skill instructions；支持 `run_intent(send_email)` 拉起邮件 Intent；已把 Gallery built-in skill assets 打包进 Android 并用本地 headless WebView 执行 bundled `run_js`，image 结果保存到 cache 后附着到 assistant 气泡
- [x] iOS/Dart Skills tool loop 第一阶段：Skills 模式下为 `flutter_gemma` 注册 `loadSkill` / `runJs` / `runIntent` tools；`loadSkill` 会把 Dart skill instructions 作为 tool response 回传模型继续生成，`runJs` / `runIntent` 仍明确返回 `pending_bridge`
- [x] iOS 图片/文本流式 Markdown 换行修复：Home 追加 assistant token 时不再对每个 streaming chunk 执行 `trimRight()`，避免 iOS flutter_gemma 在 chunk 边界输出的 `\\n` 被吞掉，导致标题/列表/段落全部粘成一行；不新增“必须分段/必须 Markdown”的提示词限制
- [x] iOS 初始化稳定性第一阶段：`initialize()` 改为只做 Gemma 文件校验/注册，不在请求前默认创建 image-capable FFI engine；文字请求按 text-only 懒加载，图片/音频 probe 请求才强制重建对应多模态 engine，减少启动/发送时双重 native load 和卡住窗口
- [x] iOS 打开即闪退修复：真机 crash report 定位到 `background_downloader` 插件注册阶段 `BDPlugin.register(with:)`，而项目模型下载已使用自己的 Android WorkManager / iOS background URLSession；新增 iOS `SafePluginRegistrant` 排除无用且会闪退的 `background_downloader` 注册，release 真机启动不再生成新 Runner crash
- [x] 模型下载进度稳定化：Android/iOS 原生后台下载事件统一在 Dart 层做单条 progress smoothing（节流、速度平滑、received bytes 单调保护），UI 显示百分比/速度/预计剩余时间，避免多线程/高频进度闪烁
- [x] iOS 图片识别质量补强：对比 Android Gallery 路线后补齐 iOS vision 输入归一化，图片在送入 `flutter_gemma` FFI 前由 UIKit 按预览方向重绘、长边限制到 1024、PNG 编码；Dart 保留 `dart:ui` fallback，并对图片请求降低采样随机性，减少“两个人识别成三个人”这类由 oversized/orientation-tagged raw 图片触发的视觉漂移
- [x] 按功能整理 Skills Hub 代码：Hub UI 抽到 `lib/src/features/skills/skills_hub_sheet.dart`，线上导入/持久化抽到 `lib/src/features/skills/skill_repository.dart`，Home 只保留状态编排和发送 Gemma 请求
- [x] 增加 `tool/check_prompt_and_skills.dart`：绕开当前 macOS native asset 测试阻断，直接验证 Prompt Lab 插值和 Skills prompt 注入
- [x] 恢复 Flutter test 本地闸口：新增 `tool/flutter_test_short_builddir.sh`，用项目内临时 Flutter config 把 tester build root 指向 `/tmp/gla_ft`，绕开 `flutter_gemma` macOS dylib headerpad 不足导致的长 install_name 重写失败；不修改用户全局 Flutter config
- [x] 语音波形/静音判断补强：Android/iOS 波形估算改为解析 WAV PCM 16-bit sample，不再把 RIFF header 当作音量数据，降低 Live 静音切段误判
- [x] Android AVD 33 smoke：debug APK 安装启动成功；首页核心 UI 可见；录音可进入“正在录音”，30 秒上限后自动回填 `播放语音 30"` 卡片；cache 中 WAV header 确认为 RIFF/WAVE、PCM、mono、16k、16-bit
- [x] 文档同步到 `docs/`

## 待完成

- [ ] Android 真机专项验证语音文件（wav/m4a/mp3）与录音 Gemma 理解，覆盖不同来源音频
- [ ] iOS 真机运行 `GEMMA_IOS_AUDIO_PROBE=true` 固定 WAV harness 验证 `flutter_gemma Message` audioBytes；若仍 code 13，记录 Gemma iOS audio blocker 并暂停本项目内 iOS audio 深测，不用非 Gemma ASR 方案替代验收
- [ ] Live 语音通话 Phase 1 深化：继续真机验证静音切段、队列背压、手动中断后的状态恢复
- [ ] Skills Hub 深化：SkillHub.cn 分页/排序/分类、评分/来源校验、签名校验、更新检查
- [ ] Skills 的 JS/WebView sandbox 深化：线上/custom skill JS 文件下载执行、webview 结果原生展示、secret/API key 管理、Android image 结果真机验证
- [ ] iOS/Dart `FunctionCallResponse` 深化：接入真实 run_js/run_intent 执行、UI 结构化展示、多轮 tool 调用真机验证
- [ ] 上游/根治 macOS native asset `libGemmaModelConstraintProvider.dylib` headerpad 问题，使直接运行 `flutter test --no-pub` 也不依赖短 build-dir wrapper
- [ ] iOS 真机模型下载后真实首轮对话验证：当前 Release 构建已通过，但 `devicectl` 安装到 iPhone 仍被签名完整性校验阻断，需要用 Xcode/签名设置修复后在设备上验证 token 输出
- [ ] iOS 后台下载真机长时间验证：前台下载、切后台、取消、重启、断网恢复、续传后 size 校验
- [ ] iOS 同图图片识别专项：用用户反馈的“两个人”图片在 iOS / Android 同模型下 A/B 复测，确认 iOS 归一化后人数不再漂移；若仍漂移，继续查 LiteRT-LM FFI image JSON/vision encoder 行为，不用非 Gemma 视觉模型替代
- [ ] macOS/Windows/Linux 本地后端选型和接入
- [ ] 真机 Release/Profile 包验证

## 校验命令

```bash
cd /Users/sanbo/Desktop/gallery/gemma_local_app
flutter analyze
dart --disable-dart-dev --packages=.dart_tool/package_config.json tool/check_prompt_and_skills.dart
tool/flutter_test_short_builddir.sh
flutter build apk --debug
cd android && ./gradlew :app:lintDebug
cd .. && flutter build ios --no-codesign
# 直接 flutter test --no-pub 仍会撞长 install_name/headerpad 问题；使用上面的短 build-dir wrapper
```
