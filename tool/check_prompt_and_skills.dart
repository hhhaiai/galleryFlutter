import 'dart:io';

import 'package:gemma_local_app/src/features/prompt_lab/prompt_templates.dart';
import 'package:gemma_local_app/src/features/skills/skill.dart';

void main() {
  const input = '请把这句话处理掉';
  for (final template in promptLabTemplates) {
    final prompt = template.buildPrompt(input);
    if (!prompt.contains(input) || prompt.contains(r'$input')) {
      throw StateError('Prompt Lab template failed: ${template.label}');
    }
  }

  final skillsPrompt = buildAgentSkillsSystemPrompt(builtInSkills);
  for (final expected in [
    'Android supports native ToolProvider',
    'iOS/Dart tool-result dispatch is still in progress',
    'calculate-hash',
    'run_js',
    'send_email',
    'kitchen-adventure',
  ]) {
    if (!skillsPrompt.contains(expected)) {
      throw StateError('Skills prompt missing: $expected');
    }
  }

  stdout.writeln('prompt_and_skills checks passed');
}
