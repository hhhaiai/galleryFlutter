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
- [x] 文档同步到 `docs/`

## 待完成

- [ ] Android MethodChannel 接入 LiteRT-LM `Engine` / `Conversation`
- [ ] 下载文件完整性校验/sha256 校验
- [ ] 图片选择与平台侧 Bitmap 转换
- [ ] 音频选择/录音与 ByteArray 转换
- [ ] Skills 的 `load_skill` / `run_intent` 工具桥接
- [ ] iOS/macOS/Windows/Linux 本地后端选型和接入
- [ ] 真机 Release/Profile 包验证

## 校验命令

```bash
cd /Users/sanbo/Desktop/gallery/gemma_local_app
flutter analyze
flutter test
```
