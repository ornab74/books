import 'dart:convert';

enum BookFormat { markdown, plainText, docx }

enum BookOrigin { local, generated, repository }

enum BookStatus { draft, review, published }

class BookDocument {
  const BookDocument({
    required this.id,
    required this.title,
    required this.author,
    required this.content,
    required this.format,
    required this.origin,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.sourcePath,
    this.repository,
    this.tags = const <String>[],
  });

  final String id;
  final String title;
  final String author;
  final String content;
  final BookFormat format;
  final BookOrigin origin;
  final BookStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? sourcePath;
  final String? repository;
  final List<String> tags;

  int get wordCount => RegExp(r'\b[\w’\-]+\b').allMatches(content).length;
  int get estimatedMinutes => wordCount == 0 ? 0 : (wordCount / 220).ceil();

  BookDocument copyWith({
    String? title,
    String? author,
    String? content,
    BookFormat? format,
    BookOrigin? origin,
    BookStatus? status,
    DateTime? updatedAt,
    String? sourcePath,
    String? repository,
    List<String>? tags,
  }) {
    return BookDocument(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      content: content ?? this.content,
      format: format ?? this.format,
      origin: origin ?? this.origin,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sourcePath: sourcePath ?? this.sourcePath,
      repository: repository ?? this.repository,
      tags: tags ?? this.tags,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'author': author,
        'content': content,
        'format': format.name,
        'origin': origin.name,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'sourcePath': sourcePath,
        'repository': repository,
        'tags': tags,
      };

  factory BookDocument.fromJson(Map<String, Object?> json) {
    T parseEnum<T extends Enum>(List<T> values, Object? value, T fallback) {
      return values.where((T item) => item.name == value).firstOrNull ?? fallback;
    }

    return BookDocument(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      author: json['author'] as String? ?? 'Unknown',
      content: json['content'] as String? ?? '',
      format: parseEnum(BookFormat.values, json['format'], BookFormat.markdown),
      origin: parseEnum(BookOrigin.values, json['origin'], BookOrigin.local),
      status: parseEnum(BookStatus.values, json['status'], BookStatus.draft),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      sourcePath: json['sourcePath'] as String?,
      repository: json['repository'] as String?,
      tags: (json['tags'] as List<Object?>? ?? const <Object?>[]).whereType<String>().toList(),
    );
  }

  String encode() => jsonEncode(toJson());
}

class RepositoryBook {
  const RepositoryBook({
    required this.name,
    required this.path,
    required this.sha,
    required this.size,
    required this.downloadUrl,
    required this.format,
  });

  final String name;
  final String path;
  final String sha;
  final int size;
  final Uri? downloadUrl;
  final BookFormat format;
}

class RepositoryTarget {
  const RepositoryTarget({
    required this.owner,
    required this.name,
    this.branch = 'main',
    this.directory = 'generated',
  });

  final String owner;
  final String name;
  final String branch;
  final String directory;

  String get fullName => '$owner/$name';

  RepositoryTarget copyWith({String? owner, String? name, String? branch, String? directory}) {
    return RepositoryTarget(
      owner: owner ?? this.owner,
      name: name ?? this.name,
      branch: branch ?? this.branch,
      directory: directory ?? this.directory,
    );
  }
}

class GenerationRequest {
  const GenerationRequest({
    required this.title,
    required this.premise,
    required this.audience,
    required this.voice,
    required this.chapterCount,
    required this.depth,
    required this.includeExercises,
    required this.includeSources,
  });

  final String title;
  final String premise;
  final String audience;
  final String voice;
  final int chapterCount;
  final String depth;
  final bool includeExercises;
  final bool includeSources;
}

class GenerationProgress {
  const GenerationProgress({required this.completed, required this.total, required this.phase});

  final int completed;
  final int total;
  final String phase;

  double get fraction => total == 0 ? 0 : completed / total;
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
