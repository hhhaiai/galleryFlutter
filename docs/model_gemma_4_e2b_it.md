# 单模型配置：Gemma-4-E2B-it

抽取来源：`model_allowlists/1_0_12.json`

```json
{
  "name": "Gemma-4-E2B-it",
  "modelId": "litert-community/gemma-4-E2B-it-litert-lm",
  "modelFile": "gemma-4-E2B-it.litertlm",
  "commitHash": "7fa1d78473894f7e736a21d920c3aa80f950c0db",
  "sizeInBytes": 2583085056,
  "minDeviceMemoryInGb": 8,
  "llmSupportImage": true,
  "llmSupportAudio": true,
  "llmSupportThinking": true,
  "defaultConfig": {
    "topK": 64,
    "topP": 0.95,
    "temperature": 1.0,
    "maxContextLength": 32000,
    "maxTokens": 4000,
    "accelerators": "gpu,cpu",
    "visionAccelerator": "gpu"
  },
  "taskTypes": [
    "llm_chat",
    "llm_prompt_lab",
    "llm_agent_chat",
    "llm_ask_image",
    "llm_ask_audio"
  ]
}
```

Flutter 固化位置：

- `lib/src/core/model/gemma_model_config.dart`

下载地址：

```text
https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm?download=true
```

Android 原路径规则：

```text
{externalFilesDir}/{normalizedName}/{version}/{downloadFileName}
```

本模型对应：

```text
{externalFilesDir}/Gemma_4_E2B_it/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm
```
