import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_local_app/src/features/prompt_lab/prompt_templates.dart';
import 'package:gemma_local_app/src/features/skills/skill.dart';

void main() {
  test('Prompt Lab templates interpolate the user input', () {
    const input = '请把这句话处理掉';

    for (final template in promptLabTemplates) {
      final prompt = template.buildPrompt(input);
      expect(prompt, contains(input), reason: template.label);
      expect(prompt, isNot(contains(r'$input')), reason: template.label);
    }
  });

  test('Skills prompt includes selected Gallery skill instructions', () {
    final prompt = buildAgentSkillsSystemPrompt(builtInSkills);

    expect(prompt, contains('native ToolProvider dispatch is not connected'));
    expect(prompt, contains('calculate-hash'));
    expect(prompt, contains('run_js'));
    expect(prompt, contains('send_email'));
    expect(prompt, contains('kitchen-adventure'));
  });
}
