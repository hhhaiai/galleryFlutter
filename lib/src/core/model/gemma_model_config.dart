enum GemmaTaskId {
  chat('llm_chat', '对话'),
  promptLab('llm_prompt_lab', 'Prompt Lab'),
  agentSkills('llm_agent_chat', 'Skills'),
  askImage('llm_ask_image', '图片理解'),
  askAudio('llm_ask_audio', '声音理解');

  const GemmaTaskId(this.id, this.label);
  final String id;
  final String label;
}

enum GemmaAccelerator {
  gpu('gpu'),
  cpu('cpu');

  const GemmaAccelerator(this.id);
  final String id;
}

class GemmaModelConfig {
  const GemmaModelConfig({
    required this.name,
    required this.modelId,
    required this.modelFile,
    required this.commitHash,
    required this.description,
    required this.sizeInBytes,
    required this.minDeviceMemoryInGb,
    required this.supportImage,
    required this.supportAudio,
    required this.supportThinking,
    required this.topK,
    required this.topP,
    required this.temperature,
    required this.maxContextLength,
    required this.maxTokens,
    required this.accelerators,
    required this.visionAccelerator,
    required this.taskIds,
    required this.bestForTaskIds,
    this.modelTypeName = 'gemma4',
  });

  final String name;
  final String modelId;
  final String modelFile;
  final String commitHash;
  final String description;
  final int sizeInBytes;
  final int minDeviceMemoryInGb;
  final bool supportImage;
  final bool supportAudio;
  final bool supportThinking;
  final int topK;
  final double topP;
  final double temperature;
  final int maxContextLength;
  final int maxTokens;
  final List<GemmaAccelerator> accelerators;
  final GemmaAccelerator visionAccelerator;
  final List<GemmaTaskId> taskIds;
  final List<GemmaTaskId> bestForTaskIds;
  final String modelTypeName;

  String get huggingFaceDownloadUrl =>
      'https://huggingface.co/$modelId/resolve/$commitHash/$modelFile?download=true';

  String get normalizedName => name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

  String localModelPath(String appFilesDir) =>
      '$appFilesDir/$normalizedName/$commitHash/$modelFile';

  String androidFlatModelPath(String externalFilesDir) =>
      '$externalFilesDir/${modelFile.toLowerCase()}';
}

const gemma4E2bIt = GemmaModelConfig(
  name: 'Gemma-4-E2B-it',
  modelId: 'litert-community/gemma-4-E2B-it-litert-lm',
  modelFile: 'gemma-4-E2B-it.litertlm',
  commitHash: '7fa1d78473894f7e736a21d920c3aa80f950c0db',
  description:
      'Gemma 4 E2B LiteRT-LM 本地模型；支持图片、声音、对话、Skills 和 Prompt Lab；上下文长度 32K。',
  sizeInBytes: 2583085056,
  minDeviceMemoryInGb: 8,
  supportImage: true,
  supportAudio: true,
  supportThinking: true,
  topK: 64,
  topP: 0.95,
  temperature: 1.0,
  maxContextLength: 32000,
  maxTokens: 4000,
  accelerators: [GemmaAccelerator.gpu, GemmaAccelerator.cpu],
  visionAccelerator: GemmaAccelerator.gpu,
  taskIds: [
    GemmaTaskId.chat,
    GemmaTaskId.promptLab,
    GemmaTaskId.agentSkills,
    GemmaTaskId.askImage,
    GemmaTaskId.askAudio,
  ],
  bestForTaskIds: [
    GemmaTaskId.chat,
    GemmaTaskId.promptLab,
    GemmaTaskId.agentSkills,
    GemmaTaskId.askImage,
    GemmaTaskId.askAudio,
  ],
);

const gemma3nE2bItIos = GemmaModelConfig(
  name: 'Gemma-3n-E2B-it',
  modelId: 'google/gemma-3n-E2B-it-litert-lm',
  modelFile: 'gemma-3n-E2B-it-int4.litertlm',
  commitHash: '73b019b63436d346f68dd9c1dbfd117eb264d888',
  description:
      'Google AI Edge Gallery iOS allowlist model；支持 iOS 文字、图片和声音输入；上下文长度 4K。',
  sizeInBytes: 3388604416,
  minDeviceMemoryInGb: 6,
  supportImage: true,
  supportAudio: true,
  supportThinking: false,
  topK: 64,
  topP: 0.95,
  temperature: 1.0,
  maxContextLength: 4096,
  maxTokens: 4096,
  accelerators: [GemmaAccelerator.gpu],
  visionAccelerator: GemmaAccelerator.gpu,
  taskIds: [
    GemmaTaskId.chat,
    GemmaTaskId.promptLab,
    GemmaTaskId.askImage,
    GemmaTaskId.askAudio,
  ],
  bestForTaskIds: [GemmaTaskId.askImage, GemmaTaskId.askAudio],
  modelTypeName: 'gemmaIt',
);

const availableModels = [gemma4E2bIt, gemma3nE2bItIos];
