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
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((dynamic item) => BookDocument.fromJson(Map<String, Object?>.from(item as Map<dynamic, dynamic>)))
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
  Future<BookDocument?> pickAndImport({String author = 'Graylan Janulis'}) async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['md', 'markdown', 'txt', 'docx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final PlatformFile file = result.files.single;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) throw StateError('The selected file could not be read.');
    final String ext = (file.extension ?? '').toLowerCase();
    final String content = ext == 'docx' ? docxToMarkdown(bytes) : utf8.decode(bytes, allowMalformed: true);
    final DateTime now = DateTime.now();
    return BookDocument(
      id: '${now.microsecondsSinceEpoch}-${file.name.hashCode}',
      title: titleFrom(content, file.name),
      author: author,
      content: content,
      format: ext == 'docx' ? BookFormat.docx : ext == 'txt' ? BookFormat.plainText : BookFormat.markdown,
      origin: BookOrigin.local,
      status: BookStatus.draft,
      createdAt: now,
      updatedAt: now,
      sourcePath: file.name,
      tags: const <String>['imported'],
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
        : Uint8List.fromList((document.content as List<dynamic>).cast<int>());
    final XmlDocument xml = XmlDocument.parse(utf8.decode(data, allowMalformed: true));
    final StringBuffer out = StringBuffer();
    for (final XmlElement paragraph in xml.findAllElements('w:p')) {
      final String text = paragraph.findAllElements('w:t').map((XmlElement node) => node.innerText).join().trim();
      if (text.isEmpty) continue;
      final String? style = paragraph
          .findAllElements('w:pStyle')
          .map((XmlElement node) => node.getAttribute('w:val'))
          .whereType<String>()
          .firstOrNull;
      if (style != null && style.toLowerCase().startsWith('heading')) {
        final int parsed = int.tryParse(style.replaceAll(RegExp(r'\D'), '')) ?? 1;
        final int level = parsed < 1 ? 1 : parsed > 6 ? 6 : parsed;
        out.writeln('${List<String>.filled(level, '#').join()} $text\n');
      } else {
        out.writeln('$text\n');
      }
    }
    return out.toString().trim();
  }

  String titleFrom(String content, String fallback) {
    final RegExpMatch? heading = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(content);
    if (heading != null) return heading.group(1)!.trim();
    return fallback.replaceFirst(RegExp(r'\.[^.]+$'), '').replaceAll('_', ' ').trim();
  }
}

class GitHubService {
  GitHubService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Map<String, String> headers(String token) => <String, String>{
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
      };

  Future<List<RepositoryBook>> scanBooks(RepositoryTarget target, {String token = ''}) async {
    final Uri uri = Uri.https(
      'api.github.com',
      '/repos/${target.fullName}/git/trees/${target.branch}',
      <String, String>{'recursive': '1'},
    );
    final http.Response response = await _client.get(uri, headers: headers(token));
    _check(response, 'scan repository');
    final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
    final List<dynamic> tree = data['tree'] as List<dynamic>? ?? <dynamic>[];
    final List<RepositoryBook> books = <RepositoryBook>[];
    for (final dynamic item in tree) {
      final Map<String, dynamic> node = item as Map<String, dynamic>;
      if (node['type'] != 'blob') continue;
      final String path = node['path'] as String? ?? '';
      final String lower = path.toLowerCase();
      if (!lower.endsWith('.md') && !lower.endsWith('.txt') && !lower.endsWith('.docx')) continue;
      books.add(RepositoryBook(
        name: path.split('/').last,
        path: path,
        sha: node['sha'] as String? ?? '',
        size: node['size'] as int? ?? 0,
        downloadUrl: Uri.tryParse('https://raw.githubusercontent.com/${target.fullName}/${target.branch}/$path'),
        format: lower.endsWith('.docx') ? BookFormat.docx : lower.endsWith('.txt') ? BookFormat.plainText : BookFormat.markdown,
      ));
    }
    books.sort((RepositoryBook a, RepositoryBook b) => a.path.compareTo(b.path));
    return books;
  }

  Future<BookDocument> downloadBook(RepositoryTarget target, RepositoryBook book, {String token = ''}) async {
    final Uri uri = Uri.https(
      'api.github.com',
      '/repos/${target.fullName}/contents/${book.path}',
      <String, String>{'ref': target.branch},
    );
    final http.Response response = await _client.get(uri, headers: headers(token));
    _check(response, 'download ${book.path}');
    final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
    final Uint8List bytes = base64Decode((data['content'] as String? ?? '').replaceAll('\n', ''));
    final ImportService importer = ImportService();
    final String content = book.format == BookFormat.docx
        ? importer.docxToMarkdown(bytes)
        : utf8.decode(bytes, allowMalformed: true);
    final DateTime now = DateTime.now();
    return BookDocument(
      id: '${now.microsecondsSinceEpoch}-${book.sha}',
      title: importer.titleFrom(content, book.name),
      author: 'Graylan Janulis',
      content: content,
      format: book.format,
      origin: BookOrigin.repository,
      status: BookStatus.published,
      createdAt: now,
      updatedAt: now,
      sourcePath: book.path,
      repository: target.fullName,
      tags: const <String>['repository'],
    );
  }

  Future<Uri> publishMarkdown({
    required RepositoryTarget target,
    required BookDocument book,
    required String token,
  }) async {
    if (token.trim().isEmpty) throw ArgumentError('A GitHub token is required to publish.');
    final String directory = target.directory.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final String path = '${directory.isEmpty ? '' : '$directory/'}${_slug(book.title)}.md';
    final Uri uri = Uri.https('api.github.com', '/repos/${target.fullName}/contents/$path');
    String? existingSha;
    final http.Response existing = await _client.get(
      uri.replace(queryParameters: <String, String>{'ref': target.branch}),
      headers: headers(token),
    );
    if (existing.statusCode == 200) {
      existingSha = (jsonDecode(existing.body) as Map<String, dynamic>)['sha'] as String?;
    } else if (existing.statusCode != 404) {
      _check(existing, 'check existing file');
    }

    final String escapedTitle = book.title.replaceAll('"', '\\"');
    final String escapedAuthor = book.author.replaceAll('"', '\\"');
    final String frontMatter = '''---
title: "$escapedTitle"
author: "$escapedAuthor"
status: published
updated: ${DateTime.now().toUtc().toIso8601String()}
tags: [${book.tags.map((String tag) => '"${tag.replaceAll('"', '\\"')}"').join(', ')}]
---

''';
    final Map<String, Object?> payload = <String, Object?>{
      'message': 'Publish ${book.title}',
      'content': base64Encode(utf8.encode('$frontMatter${book.content.trim()}\n')),
      'branch': target.branch,
      if (existingSha != null) 'sha': existingSha,
    };
    final http.Response response = await _client.put(
      uri,
      headers: <String, String>{...headers(token), 'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    _check(response, 'publish $path');
    final Map<String, dynamic> body = jsonDecode(response.body) as Map<String, dynamic>;
    final Map<String, dynamic> content = body['content'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return Uri.parse(content['html_url'] as String? ?? 'https://github.com/${target.fullName}/blob/${target.branch}/$path');
  }

  void _check(http.Response response, String action) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String message = response.body;
    try {
      message = (jsonDecode(response.body) as Map<String, dynamic>)['message'] as String? ?? message;
    } catch (_) {}
    throw StateError('Could not $action (${response.statusCode}): $message');
  }

  String _slug(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '')
      .replaceAll(RegExp(r'-{2,}'), '-');
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
    final int total = request.chapterCount + 1;
    yield GenerationProgress(completed: 0, total: total, phase: 'Designing the book');
    final String outline = await _complete(
      endpoint: endpoint,
      model: model,
      apiKey: apiKey,
      system: 'You are a rigorous book architect. Return only a numbered chapter outline with concise chapter purposes.',
      prompt: '''Create ${request.chapterCount} chapters for "${request.title}".
Premise: ${request.premise}
Audience: ${request.audience}
Voice: ${request.voice}
Depth: ${request.depth}
Every chapter must make a distinct intellectual contribution.''',
    );
    final List<String> titles = _parseOutline(outline, request.chapterCount);
    final List<String> chapters = <String>[];
    onDraft(_assemble(request.title, titles, chapters));

    for (int index = 0; index < titles.length; index++) {
      final String chapter = await _complete(
        endpoint: endpoint,
        model: model,
        apiKey: apiKey,
        system: 'Write advanced, original nonfiction in Markdown. Explain how and why. Avoid filler and fabricated citations.',
        prompt: '''Book: ${request.title}
Premise: ${request.premise}
Audience: ${request.audience}
Voice: ${request.voice}
Depth: ${request.depth}
Outline:
${titles.asMap().entries.map((MapEntry<int, String> entry) => '${entry.key + 1}. ${entry.value}').join('\n')}

Write chapter ${index + 1}: ${titles[index]}.
Use a chapter heading, clear subsections, concrete examples, technical details, and a practical synthesis.${request.includeExercises ? '\nInclude three exercises.' : ''}${request.includeSources ? '\nAdd a Sources to Verify section with search targets, never invented citations.' : ''}''',
      );
      chapters.add(chapter.trim());
      onDraft(_assemble(request.title, titles, chapters));
      yield GenerationProgress(completed: index + 1, total: total, phase: 'Writing chapter ${index + 1} of ${titles.length}');
    }
    yield GenerationProgress(completed: total, total: total, phase: 'Draft complete');
  }

  String _assemble(String title, List<String> outline, List<String> chapters) {
    final String toc = outline.asMap().entries.map((MapEntry<int, String> entry) => '${entry.key + 1}. ${entry.value}').join('\n');
    return '# $title\n\n## Table of Contents\n\n$toc\n\n${chapters.join('\n\n---\n\n')}';
  }

  Future<String> _complete({
    required String endpoint,
    required String model,
    required String apiKey,
    required String system,
    required String prompt,
  }) async {
    final Uri uri = Uri.parse(endpoint.trim().isEmpty ? 'https://api.openai.com/v1/chat/completions' : endpoint.trim());
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
      },
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
    final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
    final List<dynamic> choices = data['choices'] as List<dynamic>? ?? <dynamic>[];
    if (choices.isEmpty) throw const FormatException('The model returned no choices.');
    final Map<String, dynamic> choice = choices.first as Map<String, dynamic>;
    final Map<String, dynamic> message = choice['message'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return message['content'] as String? ?? '';
  }

  List<String> _parseOutline(String outline, int count) {
    final List<String> titles = outline
        .split('\n')
        .map((String line) => line.replaceFirst(RegExp(r'^\s*(?:chapter\s*)?\d+[.):\-]\s*', caseSensitive: false), '').trim())
        .where((String line) => line.isNotEmpty)
        .take(count)
        .toList();
    while (titles.length < count) {
      titles.add('Chapter ${titles.length + 1}');
    }
    return titles;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
