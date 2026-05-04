import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'skill.dart';

class SkillRepository {
  static const skillHubHomeUrl = 'https://skillhub.cn/';
  static const _storageFileName = 'online_skills.json';
  static const _maxSkillBytes = 512 * 1024;

  Future<List<GemmaSkill>> loadOnlineSkills() async {
    final file = await _storageFile();
    if (!await file.exists()) return const [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(_skillFromJson)
        .where((skill) => skill.name.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<List<GemmaSkill>> saveOnlineSkill(GemmaSkill skill) async {
    final skills = await loadOnlineSkills();
    final merged = <GemmaSkill>[
      for (final item in skills)
        if (item.name != skill.name) item,
      skill,
    ]..sort((a, b) => a.name.compareTo(b.name));
    await _saveOnlineSkills(merged);
    return merged;
  }

  Future<List<GemmaSkill>> deleteOnlineSkill(String name) async {
    final skills = await loadOnlineSkills();
    final remaining = skills
        .where((skill) => skill.name != name)
        .toList(growable: false);
    await _saveOnlineSkills(remaining);
    return remaining;
  }

  Future<GemmaSkill> importOnlineSkill(String inputUrl) async {
    final normalized = _normalizeSkillUrl(inputUrl);
    final response = await _get(normalized);
    var body = response.body;
    var sourceUrl = normalized.toString();

    if (_looksLikeHtml(response, body)) {
      final linkedSkill = _findSkillMarkdownLink(normalized, body);
      if (linkedSkill == null) {
        throw const SkillImportException(
          '这个页面不像 SKILL.md，也没有找到指向 SKILL.md 的链接。请粘贴具体的 SKILL.md / raw GitHub URL。',
        );
      }
      final linkedResponse = await _get(linkedSkill);
      body = linkedResponse.body;
      sourceUrl = linkedSkill.toString();
    }

    if (utf8.encode(body).length > _maxSkillBytes) {
      throw const SkillImportException('Skill 文件超过 512KB，上线导入已拒绝。');
    }
    return _parseSkillMarkdown(body, sourceUrl: sourceUrl);
  }

  Future<File> _storageFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_storageFileName');
  }

  Future<void> _saveOnlineSkills(List<GemmaSkill> skills) async {
    final file = await _storageFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(skills.map(_skillToJson).toList(growable: false)),
    );
  }

  Future<http.Response> _get(Uri uri) async {
    final response = await http
        .get(
          uri,
          headers: const {
            'accept': 'text/markdown,text/plain,text/html;q=0.8,*/*;q=0.5',
            'user-agent': 'galleryFlutter Gemma Skills Hub importer',
          },
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SkillImportException(
        '下载 Skill 失败：HTTP ${response.statusCode} ${response.reasonPhrase ?? ''}',
      );
    }
    return response;
  }

  Uri _normalizeSkillUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const SkillImportException('请输入线上 Skill URL。');
    }
    var uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      uri = Uri.tryParse('https://$trimmed');
    }
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      throw const SkillImportException('只支持 http/https URL。');
    }
    if (uri.host == 'github.com' && uri.path.contains('/blob/')) {
      final parts = uri.pathSegments;
      final blobIndex = parts.indexOf('blob');
      if (parts.length > blobIndex + 2) {
        final owner = parts[0];
        final repo = parts[1];
        final ref = parts[blobIndex + 1];
        final rest = parts.sublist(blobIndex + 2).join('/');
        return Uri.https(
          'raw.githubusercontent.com',
          '/$owner/$repo/$ref/$rest',
        );
      }
    }
    return uri;
  }

  bool _looksLikeHtml(http.Response response, String body) {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final prefix = body.trimLeft().toLowerCase();
    return contentType.contains('text/html') ||
        prefix.startsWith('<!doctype html') ||
        prefix.startsWith('<html');
  }

  Uri? _findSkillMarkdownLink(Uri base, String html) {
    final linkPattern = RegExp(
      r'''href=["']([^"']*(?:SKILL\.md|skill\.md)[^"']*)["']''',
      caseSensitive: false,
    );
    final match = linkPattern.firstMatch(html);
    if (match == null) return null;
    return base.resolve(match.group(1)!);
  }

  GemmaSkill _parseSkillMarkdown(String markdown, {required String sourceUrl}) {
    final normalized = markdown.replaceAll('\r\n', '\n');
    final frontMatterMatch = RegExp(
      r'^---\s*\n([\s\S]*?)\n---\s*\n?',
    ).firstMatch(normalized);
    final frontMatter = frontMatterMatch?.group(1) ?? '';
    final body = frontMatterMatch == null
        ? normalized.trim()
        : normalized.substring(frontMatterMatch.end).trim();
    final meta = <String, String>{};
    for (final line in frontMatter.split('\n')) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      meta[key] = value.replaceAll(RegExp(r'''^["']|["']$'''), '');
    }
    final uri = Uri.tryParse(sourceUrl);
    final fallbackName = uri == null || uri.pathSegments.isEmpty
        ? 'online-skill'
        : uri.pathSegments.reversed.firstWhere(
            (segment) => segment.toLowerCase() != 'skill.md',
            orElse: () => 'online-skill',
          );
    final name = (meta['name'] ?? fallbackName).trim();
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{1,63}$').hasMatch(name)) {
      throw SkillImportException('Skill name 不合法：$name');
    }
    final description = (meta['description'] ?? 'Online skill from $sourceUrl')
        .trim();
    if (body.isEmpty) {
      throw const SkillImportException('Skill instructions 为空。');
    }
    return GemmaSkill(
      name: name,
      description: description,
      instructions: body.length > 20000 ? body.substring(0, 20000) : body,
      sourceUrl: sourceUrl,
      online: true,
    );
  }

  Map<String, dynamic> _skillToJson(GemmaSkill skill) => {
    'name': skill.name,
    'description': skill.description,
    'instructions': skill.instructions,
    'sourceUrl': skill.sourceUrl,
    'online': skill.online,
  };

  GemmaSkill _skillFromJson(Map<String, dynamic> json) => GemmaSkill(
    name: json['name']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    instructions: json['instructions']?.toString() ?? '',
    sourceUrl: json['sourceUrl']?.toString(),
    online: json['online'] == true,
  );
}

class SkillImportException implements Exception {
  const SkillImportException(this.message);
  final String message;

  @override
  String toString() => message;
}
