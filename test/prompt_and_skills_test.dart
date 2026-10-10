import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as fg;
import 'package:gemma_local_app/src/core/runtime/local_gemma_runtime.dart';
import 'package:gemma_local_app/src/core/runtime/platform_gemma_runtime.dart';
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
    expect(prompt, contains('iOS/Dart executes the bundled `calculate-hash`'));
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

  test('iOS/Dart calculate-hash executes the enabled SHA-1 skill', () {
    final result = MethodChannelGemmaRuntime().executeDartSkillToolForTesting(
      const fg.FunctionCallResponse(
        name: 'runJs',
        args: {
          'skillName': 'calculate-hash',
          'scriptName': 'index.html',
          'data': '{"text":"abc"}',
        },
      ),
      const GemmaRequest(
        prompt: 'Hash abc',
        enabledSkillNames: ['calculate-hash'],
      ),
    );

    expect(result['status'], 'succeeded');
    expect(result['algorithm'], 'SHA-1');
    expect(result['result'], 'a9993e364706816aba3e25717850c26c9cd0d89d');
  });

  test('iOS raw Skills tools use complete JSON Schema parameters', () {
    final tools = MethodChannelGemmaRuntime().iosSkillToolsForTesting(
      const GemmaRequest(
        prompt: 'Hash abc',
        enabledSkillNames: ['calculate-hash'],
      ),
    );

    expect(tools, isNotEmpty);
    for (final tool in tools) {
      expect(tool.parameters['type'], 'object', reason: tool.name);
      expect(tool.parameters['properties'], isA<Map>(), reason: tool.name);
      expect(tool.parameters['required'], isA<List>(), reason: tool.name);
    }
  });

  test('iOS text tool protocol parses a Gemma JSON tool selection', () {
    final call = MethodChannelGemmaRuntime.parseIosTextToolCallForTesting('''
```json
{"name":"runJs","arguments":{"skillName":"calculate-hash","scriptName":"index.html","data":"{\\"text\\":\\"abc\\"}"}}
```
''');

    expect(call, isNotNull);
    expect(call!.name, 'runJs');
    expect(call.args['skillName'], 'calculate-hash');
    expect(call.args['data'], '{"text":"abc"}');
  });
}
