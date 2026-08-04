import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'models.dart';

class LibraryStore {
  static const String _key = 'bookforge.library.v1';

  Future<List<BookDocument>> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <BookDocument>[];
    try {
      return (jsonDecode(raw) as List<Object?>)
          .whereType<Map<String, Object?>>()
          .map(BookDocument.fromJson)
          .toList();
    } catch (_) {
      return <BookDocument>[];
    }
  }

  Future<void> save(List<BookDocument> books) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(books.map((BookDocument book) => book.toJson()).toList()));
  }
}

class ImportService {
  Future<BookDocument?> pickAndImport({String defaultAuthor = 'Graylan Janulis'}) async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['md', 'markdown', 'txt', 'docx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final PlatformFile file = result.files.single;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) throw StateError('The selected file could not be read.');
    final String extension = (file.extension ?? '').toLowerCase();
    final String content = extension == 'docx' ? docxToMarkdown(bytes) : utf8.decode(bytes, allowMalformed: true);
    final DateTime now = DateTime.now();
    final String title = _titleFromContent(content, file.name);
    return BookDocument(
      id: '${now.microsecondsSinceEpoch}-${file.name.hashCode}',
      title: title,
      author: defaultAuthor,
      content: content,
      format: extension == 'docx' ? BookFormat.docx : extension == 'txt' ? BookFormat.plainText : BookFormat.markdown,
      origin: BookOrigin.local,
      status: BookStatus.draft,
      createdAt: now,
      updatedAt: now,
      sourcePath: file.name,
      tags: <String>['imported'],
    );
  }

  String docxToMarkdown(Uint8List bytes) {
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? document;
    for (final ArchiveFile file in archive.files) {
      if (file.name == 'word/document.xml') {
        document = file;
        break;
      }
    }
    if (document == null) throw const FormatException('DOCX is missing word/document.xml.');
    final Uint8List data = document.content is Uint8List
        ? document.content as Uint8List
        : Uint8List.fromList(document.content as List<int>);
    final XmlDocument xml = XmlDocument.parse(utf8.decode(data, allowMalformed: true));
    final StringBuffer output = StringBuffer();
    for (final XmlElement paragraph in xml.findAllElements('w:p')) {
      final String text = paragraph.findAllElements('w:t').map((XmlElement node) => node.innerText).join();
      if (text.trim().isEmpty) continue;
      final String? style = paragraph
          .findAllElements('w:pStyle')
          .map((XmlElement node) => node.getAttribute('w:val'))
          .whereType<String>()
          .firstOrNull;
      if (style != null && style.toLowerCase().startsWith('heading')) {
        final int level = int.tryParse(style.replaceAll(RegExp(r'\D'), '')) ?? 1;
        output.writeln('${'#' * level.clamp(1, 6)} ${text.trim()}\n');
      } else {
        output.writeln('${text.trim()}\n');
      }
    }
    return output.toString().trim();
  }

  String _titleFromContent(String content, String fallback) {
    final RegExpMatch? heading = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(content);
    if (heading != null) return heading.group(1)!.trim();
    return fallback.replaceFirst(RegExp(r'\.[^.]+$'), '').replaceAll('_', ' ').trim();
  }
}

class GitHubService {
  GitHubService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> _headers(String token) => <String, String>{
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
      };

  Future<List<RepositoryBook>> scanBooks(RepositoryTarget target, {String token = ''}) async {
    final Uri uri = Uri.https('api.github.com', '/repos/${target.fullName}/git/trees/${target.branch}', <String, String>{'recursive': '1'});
    final http.Response response = await _client.get(uri, headers: _headers(token));
    _ensureSuccess(response, 'scan repository');
    final Map<String, Object?> data = jsonDecode(response.body) as Map<String, Object?>;
    final List<Object?> tree = data['tree'] as List<Object?>? ?? <Object?>[];
    final List<RepositoryBook> books = <RepositoryBook>[];
    for (final Object? raw in tree) {
      if (raw is! Map<String, Object?> || raw['type'] != 'blob') continue;
      final String path = raw['path'] as String? ?? '';
      final String lower = path.toLowerCase();
      if (!(lower.endsWith('.md') || lower.endsWith('.txt') || lower.endsWith('.docx'))) continue;
      books.add(RepositoryBook(
        name: path.split('/').last,
        path: path,
        sha: raw['sha'] as String? ?? '',
        size: raw['size'] as int? ?? 0,
        downloadUrl: Uri.tryParse('https://raw.githubusercontent.com/${target.fullName}/${target.branch}/$path'),
        format: lower.endsWith('.docx') ? BookFormat.docx : lower.endsWith('.txt') ? BookFormat.plainText : BookFormat.markdown,
      ));
    }
    books.sort((RepositoryBook a, RepositoryBook b) => a.path.compareTo(b.path));
    return books;
  }

  Future<BookDocument> downloadBook(RepositoryTarget target, RepositoryBook book, {String token = ''}) async {
    final Uri uri = Uri.https('api.github.com', '/repos/${target.fullName}/contents/${book.path}', <String, String>{'ref': target.branch});
    final http.Response response = await _client.get(uri, headers: _headers(token));
    _ensureSuccess(response, 'download ${book.path}');
    final Map<String, Object?> data = jsonDecode(response.body) as Map<String, Object?>;
    final String encoded = (data['content'] as String? ?? '').replaceAll('\n', '');
    final Uint8List bytes = base64Decode(encoded);
    final ImportService importer = ImportService();
    final String content = book.format == BookFormat.docx
        ? importer.docxToMarkdown(bytes)
        : utf8.decode(bytes, allowMalformed: true);
    final DateTime now = DateTime.now();
    return BookDocument(
      id: '${now.microsecondsSinceEpoch}-${book.sha}',
      title: _friendlyName(book.name),
      author: 'Graylan Janulis',
      content: content,
      format: book.format,
      origin: BookOrigin.repository,
      status: BookStatus.published,
      createdAt: now,
      updatedAt: now,
      sourcePath: book.path,
      repository: target.fullName,
      tags: <String>['repository'],
    );
  }

  Future<Uri> publishMarkdown({
    required RepositoryTarget target,
    required BookDocument book,
    required String token,
    String? commitMessage,
  }) async {
    if (token.trim().isEmpty) throw ArgumentError('A GitHub token is required to publish.');
    final String slug = _slug(book.title);
    final String directory = target.directory.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final String path = '${directory.isEmpty ? '' : '$directory/'}$slug.md';
    final Uri uri = Uri.https('api.github.com', '/repos/${target.fullName}/contents/$path');
    String? existingSha;
    final http.Response existing = await _client.get(uri.replace(queryParameters: <String, String>{'ref': target.branch}), headers: _headers(token));
    if (existing.statusCode == 200) {
      existingSha = (jsonDecode(existing.body) as Map<String, Object?>)['sha'] as String?;
    } else if (existing.statusCode != 404) {
      _ensureSuccess(existing, 'check existing file');
    }
    final String frontMatter = '''---
title: "${book.title.replaceAll('"', '\\"')}"
author: "${book.author.replaceAll('"', '\\"')}"
status: ${book.status.name}
updated: ${book.updatedAt.toUtc().toIso8601String()}
tags: [${book.tags.map((String tag) => '"${tag.replaceAll('"', '\\"')}"').join(', ')}]
---

''';
    final Map<String, Object?> payload = <String, Object?>{
      'message': commitMessage ?? 'Publish ${book.title}',
      'content': base64Encode(utf8.encode('$frontMatter${book.content.trim()}\n')),
      'branch': target.branch,
      if (existingSha != null) 'sha': existingSha,
    };
    final http.Response response = await _client.put(uri, headers: <String, String>{..._headers(token), 'Content-Type': 'application/json'}, body: jsonEncode(payload));
    _ensureSuccess(response, 'publish $path');
    final Map<String, Object?> body = jsonDecode(response.body) as Map<String, Object?>;
    final Map<String, Object?> content = body['content'] as Map<String, Object?>? ?? <String, Object?>{};
    return Uri.parse(content['html_url'] as String? ?? 'https://github.com/${target.fullName}/blob/${target.branch}/$path');
  }

  void _ensureSuccess(http.Response response, String action) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String message = response.body;
    try {
      message = (jsonDecode(response.body) as Map<String, Object?>)['message'] as String? ?? message;
    } catch (_) {}
    throw StateError('Could not $action (${response.statusCode}): $message');
  }

  String _slug(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '')
      .replaceAll(RegExp(r'-{2,}'), '-');

  String _friendlyName(String value) => value.replaceFirst(RegExp(r'\.[^.]+$'), '').replaceAll('_', ' ');
}

class GenerationService {
  GenerationService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Stream<GenerationProgress> generate({
    required GenerationRequest request,
    required String endpoint,
    required String model,
    required String apiKey,
    required void Function(String markdown) onDraft,
  }) async* {
    final List<String> chapters = <String>[];
    yield GenerationProgress(completed: 0, total: request.chapterCount + 1, phase: 'Designing the book');
    final String outline = await _complete(
      endpoint: endpoint,
      model: model,
      apiKey: apiKey,
      system: 'You are a rigorous book architect. Return only a numbered chapter outline with concise chapter purposes.',
      prompt: _outlinePrompt(request),
    );
    final List<String> titles = _parseOutline(outline, request.chapterCount);
    onDraft('# ${request.title}\n\n## Table of Contents\n\n${titles.asMap().entries.map((MapEntry<int, String> e) => '${e.key + 1}. ${e.value}').join('\n')}\n');
    for (int index = 0; index < titles.length; index++) {
      final String chapter = await _complete(
        endpoint: endpoint,
        model: model,
        apiKey: apiKey,
        system: 'You write advanced, original, structurally clear nonfiction. Use Markdown. Explain both how and why. Avoid filler and invented citations.',
        prompt: _chapterPrompt(request, titles, index, chapters),
      );
      chapters.add(chapter.trim());
      onDraft('# ${request.title}\n\n## Table of Contents\n\n${titles.asMap().entries.map((MapEntry<int, String> e) => '${e.key + 1}. ${e.value}').join('\n')}\n\n${chapters.join('\n\n---\n\n')}');
      yield GenerationProgress(completed: index + 1, total: request.chapterCount + 1, phase: 'Writing chapter ${index + 1} of ${titles.length}');
    }
    yield GenerationProgress(completed: request.chapterCount + 1, total: request.chapterCount + 1, phase: 'Draft complete');
  }

  Future<String> _complete({required String endpoint, required String model, required String apiKey, required String system, required String prompt}) async {
    final Uri uri = Uri.parse(endpoint.trim().isEmpty ? 'https://api.openai.com/v1/chat/completions' : endpoint.trim());
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{'Content-Type': 'application/json', if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}'},
      body: jsonEncode(<String, Object?>{
        'model': model,
        'temperature': 0.72,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'system', 'content': system},
          <String, String>{'role': 'user', 'content': prompt},
        ],
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Generation failed (${response.statusCode}): ${response.body}');
    }
    final Map<String, Object?> data = jsonDecode(response.body) as Map<String, Object?>;
    final List<Object?> choices = data['choices'] as List<Object?>? ?? <Object?>[];
    if (choices.isEmpty) throw const FormatException('The model returned no choices.');
    final Map<String, Object?> choice = choices.first as Map<String, Object?>;
    final Map<String, Object?> message = choice['message'] as Map<String, Object?>? ?? <String, Object?>{};
    return message['content'] as String? ?? '';
  }

  String _outlinePrompt(GenerationRequest request) => '''
Create ${request.chapterCount} chapters for "${request.title}".
Premise: ${request.premise}
Audience: ${request.audience}
Voice: ${request.voice}
Depth: ${request.depth}
Each chapter must add a distinct intellectual contribution and create a coherent progression.
''';

  String _chapterPrompt(GenerationRequest request, List<String> titles, int index, List<String> completed) => '''
Book: ${request.title}
Premise: ${request.premise}
Audience: ${request.audience}
Voice: ${request.voice}
Depth: ${request.depth}
Full outline:
${titles.asMap().entries.map((MapEntry<int, String> e) => '${e.key + 1}. ${e.value}').join('\n')}

Write chapter ${index + 1}: ${titles[index]}.
Use a chapter heading, clear subsections, concrete examples, technical details where useful, and a final practical synthesis.${request.includeExercises ? '\nInclude 3 thoughtful exercises.' : ''}${request.includeSources ? '\nAdd a Sources to Verify section containing search targets, not fabricated citations.' : ''}
Already completed chapter summaries are intentionally omitted; do not repeat earlier material.
''';

  List<String> _parseOutline(String outline, int count) {
    final List<String> parsed = outline
        .split('\n')
        .map((String line) => line.replaceFirst(RegExp(r'^\s*(?:chapter\s*)?\d+[.):\-]\s*', caseSensitive: false), '').trim())
        .where((String line) => line.isNotEmpty)
        .take(count)
        .toList();
    while (parsed.length < count) {
      parsed.add('Chapter ${parsed.length + 1}');
    }
    return parsed;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
