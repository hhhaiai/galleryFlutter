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
- [x] 文档同步到 `docs/`

## 待完成

- [ ] Android MethodChannel 接入 LiteRT-LM `Engine` / `Conversation`
- [ ] 下载文件完整性校验/sha256 校验
- [ ] 图片选择与平台侧 Bitmap 转换
- [ ] 音频选择/录音与 ByteArray 转换
- [ ] Skills 的 `load_skill` / `run_intent` 工具桥接
- [ ] iOS 真机模型下载后真实首轮对话验证：当前 Release 构建已通过，但 `devicectl` 安装到 iPhone 仍被签名完整性校验阻断，需要用 Xcode/签名设置修复后在设备上验证 token 输出
- [ ] iOS 后台下载真机长时间验证：前台下载、切后台、取消、重启、断网恢复、续传后 size 校验
- [ ] macOS/Windows/Linux 本地后端选型和接入
- [ ] 真机 Release/Profile 包验证

## 校验命令

```bash
cd /Users/sanbo/Desktop/gallery/gemma_local_app
flutter analyze
flutter test
flutter build ios --no-codesign
flutter build ios --release
```

