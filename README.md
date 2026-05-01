# Gemma Local App

从 Google AI Edge Gallery Android 工程中抽取的跨平台本地化 Flutter 工程骨架。

目标：只使用 `Gemma-4-E2B-it` / `gemma-4-e2b-it` 模型，并统一支持 iOS、Android、macOS、Windows、Linux。

当前状态：

- 已创建 Flutter 跨平台工程：iOS / Android / macOS / Windows / Linux。
- 已抽取并固化单模型配置：`litert-community/gemma-4-E2B-it-litert-lm`。
- 已梳理任务入口：对话、图片、声音、Skills、Prompt Lab。
- 已实现左侧设置 `Models` 中下载 Gemma-4-E2B-it，采用 `.gallerytmp` 临时文件和 HTTP Range 续传。
- 已创建本地运行时抽象接口，Android LiteRT-LM 原生桥接待接入。

运行：

```bash
cd gemma_local_app
flutter run -d macos
```

模型下载地址：

```text
https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm?download=true
```
