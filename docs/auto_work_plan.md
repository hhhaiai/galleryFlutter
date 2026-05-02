# 自动工作模式实施方案

本文件记录当前用户授权后的自动工作计划、优先级、验收标准和提交策略。所有重大进展也必须同步到 `CLAUDE.md`。

## Google AI Edge 参考后的 UX 约束

已新增详细设计文档：`docs/google_ai_edge_ux_design.md`。后续实现必须遵守：

1. Google AI Edge Gallery 已有 App Store iOS 版本，工程内不得再用笼统“iOS 暂不支持”阻断用户。
2. iOS 下载以原生 `URLSessionConfiguration.background` 为主路径；前台可做 Range 多分片加速，后台优先系统托管可靠性。
3. Models 页面采用 Gallery 风格模型卡片，显示大小、路径、能力、进度、速度、暂停/继续/删除/校验。
4. Chat 首页在未下载或能力未接入时显示行动卡片和降级说明，而不是死胡同提示。
5. Skills 参考 Gallery 的 built-in / featured / URL 导入 / 本地导入 / 安全免责声明形态。

## 总体原则

1. Android 已可文字对话，后续仍保持 Android 物理机优先验证，不破坏已可用链路。
2. 每完成一个可验证功能块，立即执行：
   - `dart format` 相关 Dart 文件
   - `flutter analyze`
   - `flutter test`
   - 相关平台 build
   - 真机安装/启动验证（具备设备时）
   - 更新 `CLAUDE.md` 与 docs
   - git commit + push GitHub
3. 对多平台功能采用“可用优先 + 平台降级”策略：Android/iOS 优先原生能力，桌面平台先提供文件选择/占位提示，不阻塞移动端。
4. 单模型策略不变：只支持 `Gemma-4-E2B-it`。

## 任务拆解

### P0：iOS 后台下载

目标：iOS 从 Dart 前台下载升级为原生后台下载。

实施方案：

- iOS 原生新增 `IOSModelDownloadManager.swift`。
- 使用 `URLSessionConfiguration.background(withIdentifier:)`。
- Flutter 侧复用现有 `com.example.gemma_local_app/model_download` MethodChannel 与 `model_download_events` EventChannel。
- 方法：`refreshStatus` / `download` / `cancel` / `delete`。
- 存储路径保持跨平台 Gallery 风格：
  `{ApplicationSupportDirectory}/{normalizedName}/{commitHash}/{modelFile}`。
- 临时文件：`{modelFile}.gallerytmp`。
- 基础断点续传：如果 `.gallerytmp` 存在，设置 `Range: bytes={tmpSize}-` 继续下载。
- 后台下载：系统接管 URLSession background task；App 被切后台后尽量继续下载。

限制与后续：

- iOS background URLSession 对多连接 Range 分片控制有限；第一阶段先保证后台下载与基础 Range 续传。
- 多线程/多连接 Range 分片可作为第二阶段：前台多分片，后台回落单任务 background URLSession，避免与 iOS 系统调度冲突。

验收：

- iOS Profile build 通过。
- 安装到 iPhone。
- 点击 Models 下载时进入原生 iOS download channel。
- App 切后台后下载任务不被 Dart isolate 生命周期直接中断。

### P1：图片输入

目标：支持图片理解入口的真实文件选择。

实施方案：

- 添加跨平台图片选择依赖，优先 `image_picker`。
- 移动端：相机拍摄 + 系统相册选择。
- 桌面端：若相机不可用，提供文件选择或明确提示；后续可接 `file_selector`。
- `GemmaRequest.imagePaths` 传入真实路径。
- Android 原生 Runtime 后续把路径转 Bitmap/Content 输入 LiteRT-LM。

验收：

- Android/iOS 可打开相机或相册。
- 选择后的图片路径显示在 composer/消息中。
- 未接多模态推理前，模型请求中包含路径，UI 不崩溃。

### P2：语音输入

目标：支持录音文件选择和实时录音入口。

实施方案：

- 添加录音依赖（候选：`record`）和文件选择能力。
- 移动端：麦克风录音开始/停止，保存临时音频文件路径。
- 桌面端：先支持选择音频文件，录音能力按平台逐步启用。
- `GemmaRequest.audioPaths` 传入真实路径。
- Android 原生 Runtime 后续把音频读取为 ByteArray/模型可接受结构。

验收：

- Android/iOS 可录音并生成本地文件路径。
- 可选择已有音频文件（若平台支持）。
- UI 状态清晰，不阻塞文字对话。

### P3：Skills / Skills Hub

目标：参考 Google AI Edge Gallery skills，实现可扩展 skills 体系。

实施方案：

- 从来源工程 assets/skills 整理 SKILL.md 到 Flutter assets 或应用支持目录。
- Dart 定义 Skill manifest：name、description、enabled、source、requiresSecret。
- Models/Settings 或 Skills 面板展示可启用 skills。
- Skills Hub 雏形：本地/远端 skill 列表接口预留，先支持本地导入/内置目录。
- Prompt 注入：生成 `___SKILLS___` 内容进入 system prompt。
- Android ToolProvider 真实工具调用后续分阶段接入。

验收：

- UI 可查看、启用/禁用 skills。
- system prompt 中体现已启用 skills。
- 不破坏普通聊天。

### P4：Markdown 输入/输出

目标：文字输入和模型输出都支持 Markdown 合理渲染。

当前状态：已添加 `flutter_markdown`，聊天气泡使用 `MarkdownBody(selectable: true)`。

后续补强：

- 优化 code block 样式。
- 用户消息与助手消息颜色兼容亮/暗主题。
- 长代码块可横向/纵向滚动。
- 保持文本可选择复制。

验收：

- `# 标题`、列表、引用、代码块、行内代码可正确显示。
- analyze/test/build 通过。

## GitHub 提交策略

- 每个功能块一个 commit。
- commit message 使用 Conventional Commits，例如：
  - `feat(ios): add background model downloads`
  - `feat(input): add image picker flow`
  - `feat(input): add audio recording flow`
  - `feat(skills): add local skills hub scaffold`
  - `feat(chat): render markdown messages`
- 每个 commit 前运行质量门禁。
- 每个 commit 后 push 当前 `ios` 分支。
