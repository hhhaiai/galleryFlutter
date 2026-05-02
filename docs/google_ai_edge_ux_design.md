# Google AI Edge 参考后的用户体验设计

更新时间：2026-05-02

## 参考来源

本设计基于以下公开来源与当前工程状态。用户再次强调：Google AI Edge Gallery 已经在 iOS App Store 上架（https://apps.apple.com/us/app/google-ai-edge-gallery/id6749645337?l=zh-Hans-CN），因此本工程不得把 iOS 呈现为“暂时不支持”；iOS 应被视为真实目标平台，至少要走原生下载、原生 runtime channel 和可验证的本地推理接入路径。

已扫描 `google-ai-edge` 组织当前公开仓库（GitHub API，2026-05-02）：

```text
google-ai-edge/gallery                 Gallery App，展示 on-device ML/GenAI，用于模型下载、聊天、Skills、iOS/Android 产品形态参考
google-ai-edge/LiteRT-LM               跨平台边缘 LLM runtime，包含 iOS/macOS prebuilt 方向
google-ai-edge/LiteRT                  LiteRT runtime / converter / optimization，作为跨端推理基础设施参考
google-ai-edge/mediapipe               MediaPipe cross-platform ML runtime
google-ai-edge/mediapipe-samples       iOS LLM inference sample，`OnDeviceModel.swift` / `LlmInference.Session.generateResponseAsync()` 是当前 iOS 真对话接入参考
google-ai-edge/litert-samples          LiteRT 示例工程，后续桌面/移动端 runtime 验证参考
google-ai-edge/models-samples          模型示例与端侧任务参考
google-ai-edge/google-ai-edge.github.io Google AI Edge 资源索引
google-ai-edge/ai-edge-quantizer       LiteRT post-training quantization，后续模型优化参考
google-ai-edge/litert-torch            PyTorch -> LiteRT 转换参考
google-ai-edge/model-explorer          模型图可视化/调试，非当前 P0 runtime 阻塞项
google-ai-edge/mediapipe-samples-web   Web 端 MediaPipe samples，非当前 iOS P0 阻塞项
```

本轮结论：当前 P0 与 iOS 真对话直接相关的是 `gallery`、`LiteRT-LM`、`LiteRT`、`mediapipe`、`mediapipe-samples`；其它仓库作为后续模型优化、桌面/Web、多模态和调试参考，不应阻断 iOS 文字对话闭环。

本设计基于以下公开来源与当前工程状态：

1. `google-ai-edge/gallery`
   - README 明确同时提供 Google Play 与 App Store 下载入口，说明 Google AI Edge Gallery 已面向 iOS 分发。
   - Android 源码包含 `DownloadRepository.kt`、`DownloadWorker.kt`，使用 WorkManager 承担模型后台下载、进度与通知。
   - `skills/README.md`、`skill.proto`、`customtasks/agentchat/*` 展示 Agent Skills 的产品形态：内置 skills、featured skills、本地导入、URL 导入、启用/禁用、校验与免责声明。
   - `model_allowlists/ios_1_0_0.json` 明确存在 iOS allowlist，其中 Gemma 3n E2B/E4B 在 iOS 上支持 text、vision、audio input，并要求 iOS 17+。
2. `google-ai-edge/LiteRT-LM`
   - README 描述 LiteRT-LM 是跨平台边缘 LLM runtime，目标覆盖 Android、iOS、Web、Desktop、IoT。
   - 仓库存在 `prebuilt/ios_arm64`、`prebuilt/ios_sim_arm64`、`prebuilt/macos_arm64` 等预编译组件，说明不能再把 iOS 简单标记为“暂不支持”。
3. `google-ai-edge/mediapipe-samples`
   - `examples/llm_inference/ios` 提供 iOS LLM 示例：模型选择、下载页、聊天页、`OnDeviceModel.swift`、`NetworkService.swift`。
   - iOS 示例使用 `URLSession` 下载模型、下载 progress UI、SwiftUI sheet 弹出下载流程、下载完成后初始化本地 `LlmInference`。
4. App Store 页面
   - Google AI Edge Gallery 已上架 iOS；因此本工程 iOS 体验要从“不可用提示”改为“可下载、可管理、可推理/可降级、清楚解释能力边界”。

## 产品原则

1. 不再出现笼统的“iOS 暂不支持”。
   - 未完成的能力必须显示为“正在接入 / 当前设备暂不可用 / 需要先下载模型 / 当前模型暂未开启图片或语音”，并给出下一步按钮。
2. 单模型不等于简陋体验。
   - 只保留 `Gemma-4-E2B-it`，但 UI 仍采用 Gallery 风格：模型卡片、下载状态、能力标签、Prompt Lab、Skills、附件输入。
3. 大模型下载必须让用户放心。
   - Android：系统前台通知 + WorkManager + 多 Range 分片 + 断点续传。
   - iOS：系统 background URLSession + resumeData/临时文件 + App 内稳定进度；多连接在前台可启用，后台按 iOS 系统限制回落为系统托管下载。
   - 桌面：先用文件选择/普通下载，明确路径与进度，后续补并发下载。
4. 聊天优先稳定，其次多模态。
   - 文字对话是第一闭环；图片/语音入口先做到选择、预览、权限、错误提示不崩溃，再接真实多模态推理。
5. 能力边界透明。
   - 每个平台展示能力矩阵：文本、图片、音频、后台下载、Skills。不可用时解释原因与下一步。

## 核心信息架构

### 首页 / Chat

顶部：
- 左侧菜单按钮。
- 中间显示 `Gemma-4-E2B-it` 与状态：未下载 / 下载中 / 可用 / 初始化中 / 生成中。
- 右侧“能力”按钮，弹出当前平台能力矩阵。

消息区：
- 用户和助手消息均使用 Markdown 渲染。
- 支持代码块、列表、引用、链接、复制。
- 模型初始化或下载状态以系统消息卡片显示，不遮挡输入。

底部 composer：
- `+` 附件按钮：相机、相册/图片文件、音频文件、Skills。
- 麦克风按钮：按住/点击录音，iOS/Android 走系统权限；桌面先降级文件选择。
- 多行 Markdown 输入框。
- 发送按钮只在模型可用且没有生成中时激活。

未下载状态：
- 不显示“暂不支持”。显示卡片：
  “需要先下载 Gemma-4-E2B-it（约 2.4GB）。下载后可离线聊天。”
- 主按钮：“下载并开始”。次按钮：“查看模型详情”。

### Models 页面

采用 Gallery 风格模型卡片，即使只有一个模型也完整展示：
- 模型名：Gemma-4-E2B-it。
- 大小、来源、commit hash、保存路径。
- 能力标签：Text、Vision、Audio、Skills-ready。
- 平台标签：Android 已验证；iOS 原生下载 + MediaPipe GenAI runtime 已接入、需真机安装最新包后验证 token 输出；macOS/Windows/Linux 待验证。
- 下载进度条：百分比、已下载/总大小、速度、剩余时间。
- 下载状态按钮：下载 / 暂停 / 继续 / 取消 / 删除 / 重新校验。
- 后台说明：Android 通知栏可见；iOS 可切后台继续，系统可能调度速率。

### Skills 页面

参考 Gallery Agent Skills：
- 内置 Skills：计算、Wikipedia 查询、二维码、地图、文本处理等，先以本地 manifest + Prompt 注入实现。
- Featured/Hub：读取本地 JSON 或远端 URL 列表，展示名称、说明、来源、权限需求。
- 导入方式：从 URL 导入、从本地文件夹导入。
- 安全体验：首次启用外部 skill 弹免责声明；显示需要网络/脚本/文件权限。
- 聊天中已启用 skills 以 chips 展示，可快速关闭。

### Prompt Lab

参考 Gallery 单轮 Prompt Lab：
- 模板列表：总结、翻译、代码解释、写作、结构化输出。
- 模板可插入 composer，不打断聊天。
- 可保存自定义模板到本地。

### 图片输入体验

移动端：
- `+` -> “拍照” / “从相册选择”。
- 选择后在 composer 上方显示缩略图，可移除。
- 如果当前 runtime 暂未开启 vision，发送前提示：“图片已附加，但当前平台多模态推理仍在接入；本次可转为文字备注或取消发送。”

桌面端：
- `+` -> “选择图片文件”。
- 相机按钮隐藏或显示“当前平台暂未接入相机，选择图片文件”。

### 语音输入体验

移动端：
- 麦克风按钮首次点击请求权限。
- 录音时显示波形/计时/取消/完成。
- 可从文件导入音频。
- 未接真实 audio inference 前，音频作为附件显示并给出能力提示。

桌面端：
- 优先支持选择音频文件。
- 实时录音按平台逐步接入。

## iOS 下载设计

### 必须达到的体验

- iOS 不再走 Dart 前台 HTTP 下载作为主路径。
- Flutter 调用同一套 `model_download` MethodChannel。
- Swift 侧 `IOSModelDownloadManager` 负责：
  - `refreshStatus`
  - `download`
  - `cancel`
  - `delete`
  - EventChannel 推送状态
- 使用 `URLSessionConfiguration.background(withIdentifier:)` 作为后台下载主路径。
- 使用 `.gallerytmp` / `.resume` 保存中间态。
- App 重启后可恢复状态；下载完成后返回 `localPath`，runtime 使用同一路径。

### 多线程/多连接策略

iOS 与 Android 不完全相同。为保证用户体验：

1. 前台加速模式：
   - 当 App 在前台且服务器支持 Range，启动 2-4 个 Range 任务写入 `.partN`。
   - 每个 part 可断点续传。
   - 全部完成后合并为 `.gallerytmp`，再 rename 成正式模型文件。
2. 后台可靠模式：
   - App 进入后台时，不强行维持自管多线程。
   - 使用 background URLSession 单任务或少量系统托管任务继续下载，优先保证不断、不丢、不崩。
3. UI 文案：
   - “前台加速下载，切到后台后由 iOS 系统托管继续下载。”
   - 不承诺后台一定满速，因为 iOS 会根据电量、网络和系统策略调度。

## 实施优先级

P0：修复当前 iOS 原生下载编译接入
- 完整把 `IOSModelDownloadManager.swift` 加入 Xcode target。
- AppDelegate 使用 FlutterViewController binaryMessenger 注册 channel，避免错误 embedding API。
- 通过 `flutter build ios --profile`。
- 安装到 iPhone 并验证启动。

P1：iOS background URLSession 下载闭环
- refresh/download/cancel/delete/status event 全链路。
- localPath 与 runtime 读取路径一致。
- 切后台/重启后状态不丢。

P2：iOS 前台 Range 多分片
- HEAD/Range 探测。
- `.partN` 续传与合并。
- 后台切换系统托管策略。

P3：统一 UX
- Models 页面展示平台能力、下载速度、路径、错误恢复。
- Chat 未下载卡片、附件 composer、Markdown 样式完善。

P4：图片、语音、Skills Hub
- 先实现 UI/权限/附件状态，再逐步接入 runtime 多模态和工具调用。

## 验收标准

1. 文档：每个阶段同步 `CLAUDE.md` 与 `docs/`。
2. 构建：`flutter analyze`、`flutter test`、Android build、iOS profile build 通过。
3. Android：不破坏已验证文字对话与系统通知下载。
4. iOS：不出现“暂不支持”死胡同；至少具备可下载、可管理、可启动的真实路径。
5. 用户体验：任何不可用能力都必须有明确原因、下一步动作和降级方案。

