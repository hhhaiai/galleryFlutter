class PromptTemplate {
  const PromptTemplate({
    required this.label,
    required this.description,
    required this.buildPrompt,
    required this.examples,
  });

  final String label;
  final String description;
  final String Function(String input) buildPrompt;
  final List<String> examples;
}

final promptLabTemplates = <PromptTemplate>[
  PromptTemplate(
    label: 'Free form',
    description: '直接把用户输入发送给模型。',
    buildPrompt: (input) => input,
    examples: ['用两句话解释 AI 和机器学习的区别。', '给一个识别植物的 App 起 3 个名字。'],
  ),
  PromptTemplate(
    label: 'Rewrite tone',
    description: '改写语气。',
    buildPrompt: (input) =>
        'Rewrite the following text using a formal tone: \$input',
    examples: ['Hey team, meeting tomorrow @ 10. Be there!'],
  ),
  PromptTemplate(
    label: 'Summarize text',
    description: '摘要文本。',
    buildPrompt: (input) =>
        'Please summarize the following in key bullet points: \$input',
    examples: ['把一段新闻或产品介绍总结成要点。'],
  ),
  PromptTemplate(
    label: 'Code snippet',
    description: '生成代码片段。',
    buildPrompt: (input) => 'Write a JavaScript code snippet to \$input',
    examples: ['Create an alert box that says "Hello, World!"'],
  ),
];
