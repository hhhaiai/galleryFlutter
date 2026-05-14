class GemmaSkill {
  const GemmaSkill({
    required this.name,
    required this.description,
    required this.instructions,
    this.selectedByDefault = true,
    this.requireSecret = false,
    this.sourceUrl,
    this.sourceSha256,
    this.sha256Verified = false,
    this.online = false,
  });

  final String name;
  final String description;
  final String instructions;
  final bool selectedByDefault;
  final bool requireSecret;
  final String? sourceUrl;
  final String? sourceSha256;
  final bool sha256Verified;
  final bool online;

  Map<String, String> toRuntimeMap() => {
    'name': name,
    'description': description,
    'instructions': instructions,
    if (sourceUrl != null && sourceUrl!.isNotEmpty) 'sourceUrl': sourceUrl!,
    if (sourceSha256 != null && sourceSha256!.isNotEmpty)
      'sourceSha256': sourceSha256!,
    'sha256Verified': sha256Verified.toString(),
    'online': online.toString(),
  };
}

const agentSkillsSystemPrompt = '''
You are an AI assistant that helps users by answering questions and completing tasks using skills.
For every new request:
1. Find the most relevant skill from the enabled skill list below.
2. Follow that skill's instructions exactly.
3. Current bridge status: Android supports native ToolProvider for `loadSkill`, bundled `run_js` scripts, and platform `run_intent` actions such as send_email, get_current_date_and_time, create_calendar_event, read_calendar_events, and schedule_notification. If a tool result says `failed`, `pending`, or display output is pending, report that honestly and do not pretend execution or UI rendering succeeded.
4. iOS/Dart tool-result dispatch is still in progress; if a FunctionCall/tool bridge is unavailable, output the intended tool call payload and clearly say it is waiting for the native Skills bridge.
5. Pure text skills can be completed directly by the local Gemma model.
''';

const defaultDisabledBuiltInSkillNames = <String>{
  'calculate-hash',
  'kitchen-adventure',
  'text-spinner',
  'send-email',
};

Set<String> defaultEnabledBuiltInSkillNames() => {
  for (final skill in builtInSkills)
    if (skill.selectedByDefault) skill.name,
};

const builtInSkills = <GemmaSkill>[
  GemmaSkill(
    name: 'calculate-hash',
    selectedByDefault: false,
    description: '计算文本哈希。',
    instructions:
        'Gallery skill source: Call the `run_js` tool with script name `index.html` and data JSON containing `text`, the text to calculate hash for.',
  ),
  GemmaSkill(
    name: 'query-wikipedia',
    description: '查询 Wikipedia 并总结。',
    instructions:
        'Gallery skill source: Call the `run_js` tool using `index.html` and data JSON containing `topic` and `lang`. Extract only the primary entity/person/event as topic. Reply in the same language as the user.',
  ),
  GemmaSkill(
    name: 'qr-code',
    description: '生成 QR code。',
    instructions:
        'Gallery skill source: Call the `run_js` tool with data JSON containing `url`, the URL or text to encode as a QR code.',
  ),
  GemmaSkill(
    name: 'send-email',
    selectedByDefault: false,
    description: '发送邮件。',
    instructions:
        'Gallery skill source: Call the `run_intent` tool with intent `send_email` and parameters JSON containing `extra_email`, `extra_subject`, and `extra_text`.',
  ),
  GemmaSkill(
    name: 'text-spinner',
    selectedByDefault: false,
    description: '让文本在头顶旋转展示。',
    instructions:
        'Gallery skill source: Call the `run_js` tool with data JSON containing `label`, the text string to spin.',
  ),
  GemmaSkill(
    name: 'interactive-map',
    description: '展示指定地点的交互地图。',
    instructions:
        'Gallery skill source: Call the `run_js` tool with data JSON containing `location`, the location to show on the map.',
  ),
  GemmaSkill(
    name: 'mood-tracker',
    description: '本地记录、查询和分析每日心情。',
    instructions:
        'Gallery skill source: Call the `run_js` tool with data JSON. Supported actions include `log_mood`, `get_mood`, `get_history`, `delete_mood`, `export_data`, and `wipe_data`. Extract date, score, comment, and days from the user request when needed.',
  ),
  GemmaSkill(
    name: 'kitchen-adventure',
    selectedByDefault: false,
    description: '以厨房电器世界为背景的文字冒险 DM。',
    instructions:
        'Pure text skill. When the user starts kitchen adventure, act as the Head Chef DM. Use kitchen-scale world building, serious-whimsical tone, never write the player action, and format each turn with location, situation, and "What do you do?".',
  ),
  GemmaSkill(
    name: 'schedule-notification',
    description: '按指定日期或每日重复创建 Android 本地提醒。',
    instructions:
        'Gallery skill source: If the reminder is not daily, first call the `run_intent` tool with intent `get_current_date_and_time` and parameters `{}`. Then call `run_intent` with intent `schedule_notification` and parameters JSON containing `title`, `message`, `hour`, `minute`, optional `year`, `month`, `day`, `repeat_daily`, `task_id`, `model_name`, or `deeplink`.',
  ),
  GemmaSkill(
    name: 'create-calendar-event',
    description: '创建系统日历事件。',
    instructions:
        'Gallery skill source: First call `run_intent` with intent `get_current_date_and_time` and parameters `{}` to calculate the exact date. Then call `run_intent` with intent `create_calendar_event` and parameters JSON containing `title`, `description`, `begin_time`, and `end_time` in YYYY-MM-DDTHH:MM:SS format.',
  ),
  GemmaSkill(
    name: 'read-calendar-events',
    description: '读取指定日期的系统日历事件。',
    instructions:
        'Gallery skill source: First call `run_intent` with intent `get_current_date_and_time` and parameters `{}` to calculate the target date. Then call `run_intent` with intent `read_calendar_events` and parameters JSON containing `date` in YYYY-MM-DD format.',
  ),
];

String buildAgentSkillsSystemPrompt(Iterable<GemmaSkill> skills) {
  final selectedSkills = skills.toList();
  final buffer = StringBuffer(agentSkillsSystemPrompt.trim());
  if (selectedSkills.isEmpty) {
    buffer.writeln('\n\nEnabled skills: none.');
    return buffer.toString();
  }
  buffer.writeln('\n\nEnabled skills:');
  for (final skill in selectedSkills) {
    buffer
      ..writeln('- ${skill.name}')
      ..writeln('  Description: ${skill.description}')
      ..writeln('  Instructions: ${skill.instructions}');
  }
  return buffer.toString();
}
