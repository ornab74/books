import 'dart:async';

import 'package:flutter/material.dart';

import 'src/models.dart';
import 'src/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BookForgeApp());
}

class BookForgeApp extends StatelessWidget {
  const BookForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color seed = Color(0xFF7C5CFC);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BookForge Studio',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0B0D12),
        cardTheme: const CardThemeData(
          color: Color(0xFF141821),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF10141C),
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide(color: Color(0xFF242A36))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide(color: seed, width: 1.5)),
        ),
      ),
      home: const StudioShell(),
    );
  }
}

class StudioShell extends StatefulWidget {
  const StudioShell({super.key});

  @override
  State<StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends State<StudioShell> {
  final LibraryStore _store = LibraryStore();
  final ImportService _importer = ImportService();
  final GitHubService _github = GitHubService();
  final GenerationService _generator = GenerationService();

  final TextEditingController _search = TextEditingController();
  final TextEditingController _editor = TextEditingController();
  final TextEditingController _githubToken = TextEditingController();
  final TextEditingController _aiKey = TextEditingController();
  final TextEditingController _endpoint = TextEditingController(text: 'https://api.openai.com/v1/chat/completions');
  final TextEditingController _model = TextEditingController(text: 'gpt-5-mini');
  final TextEditingController _repoOwner = TextEditingController(text: 'ornab74');
  final TextEditingController _repoName = TextEditingController(text: 'books');
  final TextEditingController _repoBranch = TextEditingController(text: 'main');
  final TextEditingController _repoDirectory = TextEditingController(text: 'generated');

  List<BookDocument> _books = <BookDocument>[];
  List<RepositoryBook> _repositoryBooks = <RepositoryBook>[];
  BookDocument? _selected;
  int _section = 0;
  bool _loading = true;
  bool _saving = false;
  bool _scanning = false;
  bool _generating = false;
  GenerationProgress? _progress;
  Timer? _saveDebounce;

  RepositoryTarget get _target => RepositoryTarget(
        owner: _repoOwner.text.trim(),
        name: _repoName.text.trim(),
        branch: _repoBranch.text.trim().isEmpty ? 'main' : _repoBranch.text.trim(),
        directory: _repoDirectory.text.trim(),
      );

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    _search.addListener(() => setState(() {}));
    _editor.addListener(_onEditorChanged);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    for (final TextEditingController controller in <TextEditingController>[
      _search,
      _editor,
      _githubToken,
      _aiKey,
      _endpoint,
      _model,
      _repoOwner,
      _repoName,
      _repoBranch,
      _repoDirectory,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    final List<BookDocument> loaded = await _store.load();
    if (!mounted) return;
    setState(() {
      _books = loaded;
      _loading = false;
      if (_books.isNotEmpty) _select(_books.first);
    });
  }

  void _select(BookDocument book) {
    setState(() {
      _selected = book;
      _editor.text = book.content;
      _editor.selection = TextSelection.collapsed(offset: _editor.text.length.clamp(0, _editor.text.length));
    });
  }

  void _onEditorChanged() {
    final BookDocument? selected = _selected;
    if (selected == null || selected.content == _editor.text) return;
    final BookDocument updated = selected.copyWith(content: _editor.text, updatedAt: DateTime.now(), status: BookStatus.draft);
    final int index = _books.indexWhere((BookDocument book) => book.id == selected.id);
    if (index < 0) return;
    setState(() {
      _books[index] = updated;
      _selected = updated;
      _saving = true;
    });
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 650), () async {
      await _store.save(_books);
      if (mounted) setState(() => _saving = false);
    });
  }

  Future<void> _importBook() async {
    try {
      final BookDocument? book = await _importer.pickAndImport();
      if (book == null) return;
      setState(() {
        _books.insert(0, book);
        _select(book);
        _section = 0;
      });
      await _store.save(_books);
    } catch (error) {
      _showError(error);
    }
  }

  void _newBook() {
    final DateTime now = DateTime.now();
    final BookDocument book = BookDocument(
      id: now.microsecondsSinceEpoch.toString(),
      title: 'Untitled Book',
      author: 'Graylan Janulis',
      content: '# Untitled Book\n\nBegin writing here.\n',
      format: BookFormat.markdown,
      origin: BookOrigin.local,
      status: BookStatus.draft,
      createdAt: now,
      updatedAt: now,
    );
    setState(() {
      _books.insert(0, book);
      _select(book);
      _section = 0;
    });
    _store.save(_books);
  }

  Future<void> _renameSelected() async {
    final BookDocument? selected = _selected;
    if (selected == null) return;
    final TextEditingController title = TextEditingController(text: selected.title);
    final TextEditingController author = TextEditingController(text: selected.author);
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Book metadata'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            TextField(controller: author, decoration: const InputDecoration(labelText: 'Author')),
          ]),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (accepted != true) return;
    final BookDocument updated = selected.copyWith(title: title.text.trim(), author: author.text.trim(), updatedAt: DateTime.now());
    final int index = _books.indexWhere((BookDocument book) => book.id == selected.id);
    setState(() {
      _books[index] = updated;
      _selected = updated;
    });
    await _store.save(_books);
  }

  Future<void> _deleteSelected() async {
    final BookDocument? selected = _selected;
    if (selected == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete local book?'),
        content: Text('Remove “${selected.title}” from this local library? The repository copy is not changed.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _books.removeWhere((BookDocument book) => book.id == selected.id);
      _selected = _books.firstOrNull;
      _editor.text = _selected?.content ?? '';
    });
    await _store.save(_books);
  }

  Future<void> _scanRepository() async {
    if (_target.owner.isEmpty || _target.name.isEmpty) {
      _showError('Repository owner and name are required.');
      return;
    }
    setState(() => _scanning = true);
    try {
      final List<RepositoryBook> books = await _github.scanBooks(_target, token: _githubToken.text);
      if (!mounted) return;
      setState(() => _repositoryBooks = books);
      _showMessage('Found ${books.length} readable book files.');
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _openRepositoryBook(RepositoryBook repositoryBook) async {
    setState(() => _scanning = true);
    try {
      final BookDocument book = await _github.downloadBook(_target, repositoryBook, token: _githubToken.text);
      final int existing = _books.indexWhere((BookDocument item) => item.repository == book.repository && item.sourcePath == book.sourcePath);
      setState(() {
        if (existing >= 0) {
          _books[existing] = book.copyWith(status: _books[existing].status);
          _select(_books[existing]);
        } else {
          _books.insert(0, book);
          _select(book);
        }
        _section = 0;
      });
      await _store.save(_books);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _publishSelected() async {
    final BookDocument? selected = _selected;
    if (selected == null) return;
    try {
      final Uri uri = await _github.publishMarkdown(
        target: _target,
        book: selected.copyWith(status: BookStatus.published, updatedAt: DateTime.now()),
        token: _githubToken.text,
      );
      final BookDocument published = selected.copyWith(status: BookStatus.published, repository: _target.fullName, updatedAt: DateTime.now());
      final int index = _books.indexWhere((BookDocument book) => book.id == selected.id);
      setState(() {
        _books[index] = published;
        _selected = published;
      });
      await _store.save(_books);
      _showMessage('Published to $uri');
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _startGeneration(GenerationRequest request) async {
    if (_aiKey.text.trim().isEmpty && _endpoint.text.contains('api.openai.com')) {
      _showError('Enter an API key in Settings before generating.');
      return;
    }
    final DateTime now = DateTime.now();
    BookDocument draft = BookDocument(
      id: 'generated-${now.microsecondsSinceEpoch}',
      title: request.title,
      author: 'Graylan Janulis',
      content: '# ${request.title}\n\nDesigning the manuscript…',
      format: BookFormat.markdown,
      origin: BookOrigin.generated,
      status: BookStatus.draft,
      createdAt: now,
      updatedAt: now,
      tags: <String>['generated', request.depth.toLowerCase()],
    );
    setState(() {
      _books.insert(0, draft);
      _select(draft);
      _section = 0;
      _generating = true;
    });
    try {
      await for (final GenerationProgress progress in _generator.generate(
        request: request,
        endpoint: _endpoint.text,
        model: _model.text,
        apiKey: _aiKey.text,
        onDraft: (String markdown) {
          final int index = _books.indexWhere((BookDocument book) => book.id == draft.id);
          if (index < 0 || !mounted) return;
          draft = draft.copyWith(content: markdown, updatedAt: DateTime.now());
          setState(() {
            _books[index] = draft;
            _selected = draft;
            _editor.text = markdown;
            _progress = progress;
          });
        },
      )) {
        if (mounted) setState(() => _progress = progress);
      }
      await _store.save(_books);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()), backgroundColor: Theme.of(context).colorScheme.error));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<BookDocument> get _filteredBooks {
    final String query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _books;
    return _books.where((BookDocument book) {
      return book.title.toLowerCase().contains(query) ||
          book.author.toLowerCase().contains(query) ||
          book.tags.any((String tag) => tag.toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: <Widget>[
            _NavigationRail(section: _section, onChanged: (int value) => setState(() => _section = value)),
            const VerticalDivider(width: 1, color: Color(0xFF202632)),
            Expanded(child: _buildSection()),
          ],
        ),
      ),
    );
  }

  Widget _buildSection() {
    return switch (_section) {
      0 => _LibraryView(
          loading: _loading,
          books: _filteredBooks,
          selected: _selected,
          search: _search,
          editor: _editor,
          saving: _saving,
          generating: _generating,
          progress: _progress,
          onSelect: _select,
          onImport: _importBook,
          onNew: _newBook,
          onMetadata: _renameSelected,
          onDelete: _deleteSelected,
          onPublish: _publishSelected,
        ),
      1 => GenerateView(onGenerate: _startGeneration, busy: _generating),
      2 => RepositoryView(
          owner: _repoOwner,
          name: _repoName,
          branch: _repoBranch,
          directory: _repoDirectory,
          books: _repositoryBooks,
          scanning: _scanning,
          onScan: _scanRepository,
          onOpen: _openRepositoryBook,
        ),
      _ => SettingsView(
          githubToken: _githubToken,
          aiKey: _aiKey,
          endpoint: _endpoint,
          model: _model,
        ),
    };
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({required this.section, required this.onChanged});

  final int section;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const List<(IconData, String)> destinations = <(IconData, String)>[
      (Icons.auto_stories_rounded, 'Library'),
      (Icons.auto_awesome_rounded, 'Generate'),
      (Icons.cloud_sync_rounded, 'Repository'),
      (Icons.tune_rounded, 'Settings'),
    ];
    return SizedBox(
      width: 88,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 18),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: <Color>[Color(0xFF9A7CFF), Color(0xFF5B8CFF)]),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.menu_book_rounded, color: Colors.white),
          ),
          const SizedBox(height: 28),
          for (int index = 0; index < destinations.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Tooltip(
                message: destinations[index].$2,
                child: IconButton.filledTonal(
                  isSelected: index == section,
                  onPressed: () => onChanged(index),
                  icon: Icon(destinations[index].$1),
                ),
              ),
            ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.only(bottom: 18),
            child: Text('BF', style: TextStyle(color: Color(0xFF697386), fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _LibraryView extends StatefulWidget {
  const _LibraryView({
    required this.loading,
    required this.books,
    required this.selected,
    required this.search,
    required this.editor,
    required this.saving,
    required this.generating,
    required this.progress,
    required this.onSelect,
    required this.onImport,
    required this.onNew,
    required this.onMetadata,
    required this.onDelete,
    required this.onPublish,
  });

  final bool loading;
  final List<BookDocument> books;
  final BookDocument? selected;
  final TextEditingController search;
  final TextEditingController editor;
  final bool saving;
  final bool generating;
  final GenerationProgress? progress;
  final ValueChanged<BookDocument> onSelect;
  final VoidCallback onImport;
  final VoidCallback onNew;
  final VoidCallback onMetadata;
  final VoidCallback onDelete;
  final VoidCallback onPublish;

  @override
  State<_LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<_LibraryView> {
  bool _preview = true;

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const Center(child: CircularProgressIndicator());
    return Row(
      children: <Widget>[
        SizedBox(
          width: 330,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                const Expanded(child: Text('BookForge', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900))),
                IconButton(onPressed: widget.onNew, tooltip: 'New book', icon: const Icon(Icons.add_rounded)),
                IconButton(onPressed: widget.onImport, tooltip: 'Import book', icon: const Icon(Icons.upload_file_rounded)),
              ]),
              const SizedBox(height: 4),
              Text('${widget.books.length} books in this view', style: const TextStyle(color: Color(0xFF8791A4))),
              const SizedBox(height: 18),
              TextField(controller: widget.search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search title, author, or tag')),
              const SizedBox(height: 14),
              Expanded(
                child: widget.books.isEmpty
                    ? const _EmptyState(icon: Icons.library_books_outlined, title: 'No books yet', body: 'Import Markdown, text, or DOCX files, or generate a new manuscript.')
                    : ListView.separated(
                        itemCount: widget.books.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (BuildContext context, int index) {
                          final BookDocument book = widget.books[index];
                          final bool active = widget.selected?.id == book.id;
                          return Material(
                            color: active ? const Color(0xFF25203D) : const Color(0xFF12161E),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => widget.onSelect(book),
                              child: Padding(
                                padding: const EdgeInsets.all(13),
                                child: Row(children: <Widget>[
                                  Container(
                                    width: 42,
                                    height: 54,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: active ? const <Color>[Color(0xFF7C5CFC), Color(0xFF496FF2)] : const <Color>[Color(0xFF2B3140), Color(0xFF1B202B)]),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Text(book.title.isEmpty ? '?' : book.title[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                                    Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 5),
                                    Text('${book.wordCount} words · ${book.status.name}', style: const TextStyle(color: Color(0xFF7D879A), fontSize: 12)),
                                  ])),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
        ),
        const VerticalDivider(width: 1, color: Color(0xFF202632)),
        Expanded(
          child: widget.selected == null
              ? const _EmptyState(icon: Icons.chrome_reader_mode_outlined, title: 'Choose a book', body: 'Select a manuscript from the library to read or edit it.')
              : Column(children: <Widget>[
                  _BookToolbar(
                    book: widget.selected!,
                    preview: _preview,
                    saving: widget.saving,
                    onTogglePreview: () => setState(() => _preview = !_preview),
                    onMetadata: widget.onMetadata,
                    onDelete: widget.onDelete,
                    onPublish: widget.onPublish,
                  ),
                  if (widget.generating && widget.progress != null)
                    LinearProgressIndicator(value: widget.progress!.fraction, minHeight: 3),
                  Expanded(
                    child: _preview
                        ? _ReadingPane(book: widget.selected!)
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
                            child: TextField(
                              controller: widget.editor,
                              expands: true,
                              maxLines: null,
                              minLines: null,
                              textAlignVertical: TextAlignVertical.top,
                              style: const TextStyle(fontFamily: 'monospace', height: 1.55, fontSize: 14),
                              decoration: const InputDecoration(hintText: 'Write your manuscript in Markdown…', contentPadding: EdgeInsets.all(22)),
                            ),
                          ),
                  ),
                ]),
        ),
      ],
    );
  }
}

class _BookToolbar extends StatelessWidget {
  const _BookToolbar({required this.book, required this.preview, required this.saving, required this.onTogglePreview, required this.onMetadata, required this.onDelete, required this.onPublish});

  final BookDocument book;
  final bool preview;
  final bool saving;
  final VoidCallback onTogglePreview;
  final VoidCallback onMetadata;
  final VoidCallback onDelete;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 18, 12),
      child: Row(children: <Widget>[
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text('${book.author} · ${book.wordCount} words · ${book.estimatedMinutes} min read${saving ? ' · saving…' : ''}', style: const TextStyle(color: Color(0xFF838DA0))),
        ])),
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: true, icon: Icon(Icons.visibility_outlined), label: Text('Read')),
            ButtonSegment<bool>(value: false, icon: Icon(Icons.edit_outlined), label: Text('Edit')),
          ],
          selected: <bool>{preview},
          onSelectionChanged: (_) => onTogglePreview(),
        ),
        const SizedBox(width: 10),
        IconButton(onPressed: onMetadata, tooltip: 'Metadata', icon: const Icon(Icons.badge_outlined)),
        IconButton(onPressed: onDelete, tooltip: 'Delete local copy', icon: const Icon(Icons.delete_outline)),
        const SizedBox(width: 6),
        FilledButton.icon(onPressed: onPublish, icon: const Icon(Icons.publish_rounded), label: const Text('Publish')),
      ]),
    );
  }
}

class _ReadingPane extends StatelessWidget {
  const _ReadingPane({required this.book});

  final BookDocument book;

  @override
  Widget build(BuildContext context) {
    final List<String> lines = book.content.split('\n');
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(48, 26, 48, 80),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                for (final String line in lines) _MarkdownLine(line: line),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkdownLine extends StatelessWidget {
  const _MarkdownLine({required this.line});
  final String line;

  @override
  Widget build(BuildContext context) {
    if (line.trim().isEmpty) return const SizedBox(height: 13);
    if (line.startsWith('# ')) return Padding(padding: const EdgeInsets.only(top: 16, bottom: 18), child: Text(line.substring(2), style: const TextStyle(fontSize: 36, height: 1.12, fontWeight: FontWeight.w900)));
    if (line.startsWith('## ')) return Padding(padding: const EdgeInsets.only(top: 28, bottom: 10), child: Text(line.substring(3), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)));
    if (line.startsWith('### ')) return Padding(padding: const EdgeInsets.only(top: 22, bottom: 8), child: Text(line.substring(4), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)));
    if (line.startsWith('> ')) return Container(margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Color(0xFF171D29), border: Border(left: BorderSide(color: Color(0xFF7C5CFC), width: 4))), child: Text(line.substring(2), style: const TextStyle(fontStyle: FontStyle.italic, height: 1.65)));
    if (line.trim() == '---') return const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Divider());
    if (RegExp(r'^\s*[-*]\s+').hasMatch(line)) return Padding(padding: const EdgeInsets.only(left: 8, bottom: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[const Text('•  ', style: TextStyle(fontSize: 18)), Expanded(child: Text(line.replaceFirst(RegExp(r'^\s*[-*]\s+'), ''), style: const TextStyle(fontSize: 16, height: 1.65)))]));
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(line, style: const TextStyle(fontSize: 16, height: 1.72, color: Color(0xFFD7DCE6))));
  }
}

class GenerateView extends StatefulWidget {
  const GenerateView({super.key, required this.onGenerate, required this.busy});

  final ValueChanged<GenerationRequest> onGenerate;
  final bool busy;

  @override
  State<GenerateView> createState() => _GenerateViewState();
}

class _GenerateViewState extends State<GenerateView> {
  final TextEditingController _title = TextEditingController(text: 'The Library That Writes Back');
  final TextEditingController _premise = TextEditingController(text: 'A rigorous account of libraries evolving from passive archives into systems that synthesize, question, explain, and revise knowledge.');
  final TextEditingController _audience = TextEditingController(text: 'Technical readers, builders, researchers, and ambitious generalists');
  final TextEditingController _voice = TextEditingController(text: 'Clear, visionary, evidence-aware, technically precise');
  int _chapters = 8;
  String _depth = 'Advanced';
  bool _exercises = true;
  bool _sources = true;

  @override
  void dispose() {
    _title.dispose();
    _premise.dispose();
    _audience.dispose();
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(34),
      children: <Widget>[
        const Text('Generate a book', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Plan the intellectual architecture first, then generate one chapter at a time into an editable local manuscript.', style: TextStyle(color: Color(0xFF8A94A6))),
        const SizedBox(height: 28),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(children: <Widget>[
                  TextField(controller: _title, decoration: const InputDecoration(labelText: 'Book title', prefixIcon: Icon(Icons.title))),
                  const SizedBox(height: 16),
                  TextField(controller: _premise, maxLines: 5, decoration: const InputDecoration(labelText: 'Premise and intellectual mission', alignLabelWithHint: true)),
                  const SizedBox(height: 16),
                  Row(children: <Widget>[
                    Expanded(child: TextField(controller: _audience, decoration: const InputDecoration(labelText: 'Audience'))),
                    const SizedBox(width: 16),
                    Expanded(child: TextField(controller: _voice, decoration: const InputDecoration(labelText: 'Voice'))),
                  ]),
                  const SizedBox(height: 20),
                  Row(children: <Widget>[
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text('Chapters: $_chapters', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Slider(value: _chapters.toDouble(), min: 3, max: 24, divisions: 21, onChanged: (double value) => setState(() => _chapters = value.round())),
                    ])),
                    const SizedBox(width: 24),
                    DropdownMenu<String>(initialSelection: _depth, label: const Text('Depth'), dropdownMenuEntries: const <DropdownMenuEntry<String>>[
                      DropdownMenuEntry(value: 'Accessible', label: 'Accessible'),
                      DropdownMenuEntry(value: 'Advanced', label: 'Advanced'),
                      DropdownMenuEntry(value: 'Research-grade', label: 'Research-grade'),
                    ], onSelected: (String? value) => setState(() => _depth = value ?? _depth)),
                  ]),
                  CheckboxListTile(value: _exercises, onChanged: (bool? value) => setState(() => _exercises = value ?? false), title: const Text('Include exercises and reflection prompts'), contentPadding: EdgeInsets.zero),
                  CheckboxListTile(value: _sources, onChanged: (bool? value) => setState(() => _sources = value ?? false), title: const Text('Include source-verification targets without fabricated citations'), contentPadding: EdgeInsets.zero),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: widget.busy
                          ? null
                          : () => widget.onGenerate(GenerationRequest(
                                title: _title.text.trim(),
                                premise: _premise.text.trim(),
                                audience: _audience.text.trim(),
                                voice: _voice.text.trim(),
                                chapterCount: _chapters,
                                depth: _depth,
                                includeExercises: _exercises,
                                includeSources: _sources,
                              )),
                      icon: widget.busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
                      label: Text(widget.busy ? 'Generating…' : 'Build manuscript'),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class RepositoryView extends StatelessWidget {
  const RepositoryView({super.key, required this.owner, required this.name, required this.branch, required this.directory, required this.books, required this.scanning, required this.onScan, required this.onOpen});

  final TextEditingController owner;
  final TextEditingController name;
  final TextEditingController branch;
  final TextEditingController directory;
  final List<RepositoryBook> books;
  final bool scanning;
  final VoidCallback onScan;
  final ValueChanged<RepositoryBook> onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(30),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const Text('Repository library', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Scan a GitHub repository recursively, import books into the local studio, and publish edited Markdown editions.', style: TextStyle(color: Color(0xFF8A94A6))),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: <Widget>[
              Expanded(child: TextField(controller: owner, decoration: const InputDecoration(labelText: 'Owner'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: name, decoration: const InputDecoration(labelText: 'Repository'))),
              const SizedBox(width: 12),
              SizedBox(width: 150, child: TextField(controller: branch, decoration: const InputDecoration(labelText: 'Branch'))),
              const SizedBox(width: 12),
              SizedBox(width: 170, child: TextField(controller: directory, decoration: const InputDecoration(labelText: 'Publish folder'))),
              const SizedBox(width: 12),
              FilledButton.icon(onPressed: scanning ? null : onScan, icon: scanning ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.radar), label: const Text('Scan')),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: books.isEmpty
              ? const _EmptyState(icon: Icons.account_tree_outlined, title: 'Repository not scanned', body: 'Scan ornab74/books or another repository to build a live catalog of Markdown, text, and DOCX books.')
              : Card(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: books.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final RepositoryBook book = books[index];
                      return ListTile(
                        leading: Icon(book.format == BookFormat.docx ? Icons.description_outlined : Icons.article_outlined),
                        title: Text(book.name),
                        subtitle: Text('${book.path} · ${_formatBytes(book.size)}'),
                        trailing: const Icon(Icons.download_rounded),
                        onTap: () => onOpen(book),
                      );
                    },
                  ),
                ),
        ),
      ]),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes > 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes > 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.githubToken, required this.aiKey, required this.endpoint, required this.model});

  final TextEditingController githubToken;
  final TextEditingController aiKey;
  final TextEditingController endpoint;
  final TextEditingController model;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(34),
      children: <Widget>[
        const Text('Connections', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Secrets remain in memory for this session and are never written to the local library.', style: TextStyle(color: Color(0xFF8A94A6))),
        const SizedBox(height: 26),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Column(children: <Widget>[
              Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.code), title: Text('GitHub publishing', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('Use a fine-grained token with Contents read/write access only to the target repositories.')),
                const SizedBox(height: 10),
                TextField(controller: githubToken, obscureText: true, decoration: const InputDecoration(labelText: 'GitHub token', prefixIcon: Icon(Icons.key))),
              ]))),
              const SizedBox(height: 18),
              Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.psychology_alt_outlined), title: Text('OpenAI-compatible generation', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('Works with hosted APIs or a local server exposing the chat-completions shape.')),
                const SizedBox(height: 10),
                TextField(controller: endpoint, decoration: const InputDecoration(labelText: 'Chat completions endpoint', prefixIcon: Icon(Icons.link))),
                const SizedBox(height: 12),
                Row(children: <Widget>[
                  Expanded(child: TextField(controller: model, decoration: const InputDecoration(labelText: 'Model'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: aiKey, obscureText: true, decoration: const InputDecoration(labelText: 'API key', prefixIcon: Icon(Icons.key)))),
                ]),
              ]))),
            ]),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(icon, size: 58, color: const Color(0xFF667085)),
          const SizedBox(height: 18),
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF8791A4), height: 1.5)),
        ]),
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
