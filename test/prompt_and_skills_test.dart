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

    expect(prompt, contains('Android supports native ToolProvider'));
    expect(
      prompt,
      contains('iOS/Dart tool-result dispatch is still in progress'),
    );
    expect(prompt, contains('calculate-hash'));
    expect(prompt, contains('run_js'));
    expect(prompt, contains('send_email'));
    expect(prompt, contains('kitchen-adventure'));
    expect(prompt, contains('schedule-notification'));
    expect(prompt, contains('schedule_notification'));
  });

  test(
    'Built-in Skills default selection mirrors Android Gallery latest defaults',
    () {
      final enabled = defaultEnabledBuiltInSkillNames();

      expect(enabled, contains('interactive-map'));
      expect(enabled, contains('schedule-notification'));
      expect(enabled, contains('mood-tracker'));
      expect(enabled, contains('query-wikipedia'));
      expect(enabled, contains('qr-code'));
      expect(enabled, isNot(contains('calculate-hash')));
      expect(enabled, isNot(contains('kitchen-adventure')));
      expect(enabled, isNot(contains('text-spinner')));
      expect(enabled, isNot(contains('send-email')));
    },
  );
}
