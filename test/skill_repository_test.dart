import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_local_app/src/features/skills/skill_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('SkillHub search parses public directory envelope', () async {
    late Uri requestedUri;
    final repository = SkillRepository(
      skillHubApiBase: Uri.parse('https://api.example.test'),
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'total': 1,
              'skills': [
                {
                  'slug': 'skill-vetter',
                  'name': 'Skill Vetter',
                  'description': 'Security-first skill vetting.',
                  'description_zh': 'AI 智能体技能安全预审工具。',
                  'ownerName': 'spclaudehome',
                  'category': 'security-compliance',
                  'source': 'clawhub',
                  'version': '1.0.0',
                  'downloads': 228723,
                  'installs': 37273,
                  'stars': 1016,
                  'labels': {'requires_api_key': 'false'},
                },
              ],
            },
            'message': 'success',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await repository.searchSkillHub(
      keyword: 'vetter',
      page: 2,
      pageSize: 3,
    );

    expect(requestedUri.path, '/api/skills');
    expect(requestedUri.queryParameters['keyword'], 'vetter');
    expect(requestedUri.queryParameters['page'], '2');
    expect(requestedUri.queryParameters['pageSize'], '3');
    expect(result.total, 1);
    expect(result.skills.single.slug, 'skill-vetter');
    expect(result.skills.single.description, 'AI 智能体技能安全预审工具。');
    expect(result.skills.single.stars, 1016);
    expect(result.skills.single.requiresApiKey, isFalse);
  });

  test('SkillHub import downloads only SKILL.md instructions', () async {
    final requestedPaths = <String>[];
    final repository = SkillRepository(
      skillHubApiBase: Uri.parse('https://api.example.test'),
      client: MockClient((request) async {
        requestedPaths.add('${request.url.path}?${request.url.query}');
        if (request.url.path.endsWith('/files')) {
          return http.Response(
            jsonEncode({
              'count': 2,
              'version': '1.0.0',
              'files': [
                {'path': 'SKILL.md', 'sha256': 'abc', 'size': 90},
                {'path': 'scripts/index.js', 'sha256': 'def', 'size': 1200},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/file')) {
          expect(request.url.queryParameters['path'], 'SKILL.md');
          return http.Response(
            '''
---
name: skill-vetter
description: Vet skills before installing them.
---

Use local Gemma to review the skill instructions and report risk honestly.
''',
            200,
            headers: {'content-type': 'text/markdown'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    final skill = await repository.importSkillHubSkill('skill-vetter');

    expect(skill.name, 'skill-vetter');
    expect(skill.description, 'Vet skills before installing them.');
    expect(skill.instructions, contains('Use local Gemma'));
    expect(skill.online, isTrue);
    expect(skill.sourceUrl, contains('/api/v1/skills/skill-vetter/file'));
    expect(requestedPaths, contains('/api/v1/skills/skill-vetter/files?'));
    expect(
      requestedPaths,
      contains('/api/v1/skills/skill-vetter/file?path=SKILL.md'),
    );
    expect(
      requestedPaths.any((path) => path.contains('scripts/index.js')),
      isFalse,
    );
  });
}
