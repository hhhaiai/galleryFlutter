class GemmaSkill {
  const GemmaSkill({
    required this.name,
    required this.description,
    required this.instructions,
    this.selected = true,
    this.requireSecret = false,
  });

  final String name;
  final String description;
  final String instructions;
  final bool selected;
  final bool requireSecret;
}

const agentSkillsSystemPrompt = '''
You are an AI assistant that helps users by answering questions and completing tasks using skills.
For every new request:
1. Find the most relevant skill from the enabled skill list.
2. If a relevant skill exists, load and follow its instructions.
3. Output only the final result when successful.
''';

const builtInSkills = <GemmaSkill>[
  GemmaSkill(
    name: 'calculate-hash',
    description: '计算文本哈希。',
    instructions:
        'When asked to calculate a hash, identify algorithm and input, then return the hash.',
  ),
  GemmaSkill(
    name: 'query-wikipedia',
    description: '查询 Wikipedia 并总结。',
    instructions:
        'Search Wikipedia for the requested topic and summarize the relevant facts.',
  ),
  GemmaSkill(
    name: 'qr-code',
    description: '生成 QR code。',
    instructions: 'Create a QR code for the requested text or URL.',
  ),
  GemmaSkill(
    name: 'send-email',
    description: '发送邮件。',
    instructions:
        'Collect recipient, subject, and body, then ask the platform email adapter to send it.',
  ),
];
