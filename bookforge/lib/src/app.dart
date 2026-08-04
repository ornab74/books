import 'dart:async';

import 'package:flutter/material.dart';

import 'models.dart';
import 'services.dart';

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
        scaffoldBackgroundColor: const Color(0xFF0A0D12),
        cardTheme: const CardThemeData(
          color: Color(0xFF141922),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF10151D),
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide(color: Color(0xFF252C38))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide(color: seed, width: 1.4)),
        ),
      ),
      home: const StudioScreen(),
    );
  }
}

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  final LibraryStore _store = LibraryStore();
  final ImportService _importer = ImportService();
  final GitHubService _github = GitHubService();
  final GenerationService _generation = GenerationService();

  final TextEditingController _search = TextEditingController();
  final TextEditingController _editor = TextEditingController();
  final TextEditingController _githubToken = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();
  final TextEditingController _endpoint = TextEditingController(text: 'https://api.openai.com/v1/chat/completions');
  final TextEditingController _model = TextEditingController(text: 'gpt-5-mini');
  final TextEditingController _owner = TextEditingController(text: 'ornab74');
  final TextEditingController _repo = TextEditingController(text: 'books');
  final TextEditingController _branch = TextEditingController(text: 'main');
  final TextEditingController _directory = TextEditingController(text: 'generated');

  List<BookDocument> _books = <BookDocument>[];
  List<RepositoryBook> _remoteBooks = <RepositoryBook>[];
  BookDocument? _selected;
  Timer? _saveTimer;
  int _page = 0;
  bool _loading = true;
  bool _saving = false;
  bool _busy = false;
  bool _preview = true;
  GenerationProgress? _progress;

  RepositoryTarget get _target => RepositoryTarget(
        owner: _owner.text.trim(),
        name: _repo.text.trim(),
        branch: _branch.text.trim().isEmpty ? 'main' : _branch.text.trim(),
        directory: _directory.text.trim(),
      );

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
    _editor.addListener(_editorChanged);
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final TextEditingController controller in <TextEditingController>[
      _search,
      _editor,
      _githubToken,
      _apiKey,
      _endpoint,
      _model,
      _owner,
      _repo,
      _branch,
      _directory,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final List<BookDocument> books = await _store.load();
    if (!mounted) return;
    setState(() {
      _books = books;
      _loading = false;
      _selected = books.isEmpty ? null : books.first;
      _editor.text = _selected?.content ?? '';
    });
  }

  void _select(BookDocument book) {
    _editor.removeListener(_editorChanged);
    _editor.text = book.content;
    _editor.addListener(_editorChanged);
    setState(() => _selected = book);
  }

  void _editorChanged() {
    final BookDocument? current = _selected;
    if (current == null || current.content == _editor.text) return;
    final int index = _books.indexWhere((BookDocument book) => book.id == current.id);
    if (index < 0) return;
    final BookDocument updated = current.copyWith(
      content: _editor.text,
      status: BookStatus.draft,
      updatedAt: DateTime.now(),
    );
    setState(() {
      _books[index] = updated;
      _selected = updated;
      _saving = true;
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () async {
      await _store.save(_books);
      if (mounted) setState(() => _saving = false);
    });
  }

  Future<void> _import() async {
    try {
      final BookDocument? book = await _importer.pickAndImport();
      if (book == null) return;
      setState(() {
        _books.insert(0, book);
        _page = 0;
      });
      _select(book);
      await _store.save(_books);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _newBook() async {
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
      _page = 0;
    });
    _select(book);
    await _store.save(_books);
  }

  Future<void> _editMetadata() async {
    final BookDocument? current = _selected;
    if (current == null) return;
    final TextEditingController title = TextEditingController(text: current.title);
    final TextEditingController author = TextEditingController(text: current.author);
    final bool? save = await showDialog<bool>(
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
    if (save != true || !mounted) return;
    final int index = _books.indexWhere((BookDocument book) => book.id == current.id);
    final BookDocument updated = current.copyWith(
      title: title.text.trim().isEmpty ? current.title : title.text.trim(),
      author: author.text.trim().isEmpty ? current.author : author.text.trim(),
      updatedAt: DateTime.now(),
    );
    setState(() {
      _books[index] = updated;
      _selected = updated;
    });
    await _store.save(_books);
  }

  Future<void> _delete() async {
    final BookDocument? current = _selected;
    if (current == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete local copy?'),
        content: Text('Remove “${current.title}” from the local BookForge library?'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _books.removeWhere((BookDocument book) => book.id == current.id);
      _selected = _books.isEmpty ? null : _books.first;
    });
    _editor.removeListener(_editorChanged);
    _editor.text = _selected?.content ?? '';
    _editor.addListener(_editorChanged);
    await _store.save(_books);
  }

  Future<void> _scan() async {
    if (_target.owner.isEmpty || _target.name.isEmpty) {
      _error('Repository owner and name are required.');
      return;
    }
    setState(() => _busy = true);
    try {
      final List<RepositoryBook> books = await _github.scanBooks(_target, token: _githubToken.text);
      if (!mounted) return;
      setState(() => _remoteBooks = books);
      _message('Found ${books.length} readable files.');
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(RepositoryBook remote) async {
    setState(() => _busy = true);
    try {
      final BookDocument book = await _github.downloadBook(_target, remote, token: _githubToken.text);
      final int index = _books.indexWhere((BookDocument item) => item.repository == book.repository && item.sourcePath == book.sourcePath);
      if (index >= 0) {
        _books[index] = book;
      } else {
        _books.insert(0, book);
      }
      setState(() => _page = 0);
      _select(index >= 0 ? _books[index] : _books.first);
      await _store.save(_books);
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    final BookDocument? current = _selected;
    if (current == null) return;
    setState(() => _busy = true);
    try {
      final Uri uri = await _github.publishMarkdown(target: _target, book: current, token: _githubToken.text);
      final int index = _books.indexWhere((BookDocument book) => book.id == current.id);
      final BookDocument published = current.copyWith(
        status: BookStatus.published,
        repository: _target.fullName,
        updatedAt: DateTime.now(),
      );
      setState(() {
        _books[index] = published;
        _selected = published;
      });
      await _store.save(_books);
      _message('Published: $uri');
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate(GenerationRequest request) async {
    if (_apiKey.text.trim().isEmpty && _endpoint.text.contains('api.openai.com')) {
      _error('Add an API key in Settings before generating.');
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
      _page = 0;
      _busy = true;
      _progress = const GenerationProgress(completed: 0, total: 1, phase: 'Starting');
    });
    _select(draft);
    try {
      final Stream<GenerationProgress> stream = _generation.generate(
        request: request,
        endpoint: _endpoint.text,
        model: _model.text,
        apiKey: _apiKey.text,
        onDraft: (String markdown) {
          final int index = _books.indexWhere((BookDocument book) => book.id == draft.id);
          if (index < 0 || !mounted) return;
          draft = draft.copyWith(content: markdown, updatedAt: DateTime.now());
          _editor.removeListener(_editorChanged);
          _editor.text = markdown;
          _editor.addListener(_editorChanged);
          setState(() {
            _books[index] = draft;
            _selected = draft;
          });
        },
      );
      await for (final GenerationProgress progress in stream) {
        if (mounted) setState(() => _progress = progress);
      }
      await _store.save(_books);
      _message('Generated draft complete.');
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString()), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<BookDocument> get _visibleBooks {
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
        child: Row(children: <Widget>[
          NavigationRail(
            selectedIndex: _page,
            onDestinationSelected: (int value) => setState(() => _page = value),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: <Color>[Color(0xFF9A7CFF), Color(0xFF4D7DFF)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.menu_book_rounded, color: Colors.white),
              ),
            ),
            destinations: const <NavigationRailDestination>[
              NavigationRailDestination(icon: Icon(Icons.auto_stories_outlined), selectedIcon: Icon(Icons.auto_stories), label: Text('Library')),
              NavigationRailDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: Text('Generate')),
              NavigationRailDestination(icon: Icon(Icons.cloud_outlined), selectedIcon: Icon(Icons.cloud), label: Text('Repository')),
              NavigationRailDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: Text('Settings')),
            ],
          ),
          const VerticalDivider(width: 1, color: Color(0xFF202632)),
          Expanded(child: _pageBody()),
        ]),
      ),
    );
  }

  Widget _pageBody() {
    return switch (_page) {
      0 => _library(),
      1 => GeneratorPanel(onGenerate: _generate, busy: _busy),
      2 => RepositoryPanel(
          owner: _owner,
          repo: _repo,
          branch: _branch,
          directory: _directory,
          books: _remoteBooks,
          busy: _busy,
          onScan: _scan,
          onOpen: _download,
        ),
      _ => SettingsPanel(
          githubToken: _githubToken,
          apiKey: _apiKey,
          endpoint: _endpoint,
          model: _model,
        ),
    };
  }

  Widget _library() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Row(children: <Widget>[
      SizedBox(
        width: 330,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              const Expanded(child: Text('BookForge', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900))),
              IconButton(onPressed: _newBook, tooltip: 'New book', icon: const Icon(Icons.add_rounded)),
              IconButton(onPressed: _import, tooltip: 'Import', icon: const Icon(Icons.upload_file_rounded)),
            ]),
            Text('${_visibleBooks.length} books', style: const TextStyle(color: Color(0xFF8993A6))),
            const SizedBox(height: 16),
            TextField(controller: _search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search library')),
            const SizedBox(height: 14),
            Expanded(
              child: _visibleBooks.isEmpty
                  ? const EmptyPanel(icon: Icons.library_books_outlined, title: 'No books yet', body: 'Import Markdown, text, or DOCX books, or generate a new manuscript.')
                  : ListView.separated(
                      itemCount: _visibleBooks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final BookDocument book = _visibleBooks[index];
                        final bool active = _selected?.id == book.id;
                        return Material(
                          color: active ? const Color(0xFF28213F) : const Color(0xFF12171F),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _select(book),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(children: <Widget>[
                                Container(
                                  width: 42,
                                  height: 54,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: active
                                          ? const <Color>[Color(0xFF7C5CFC), Color(0xFF4D7DFF)]
                                          : const <Color>[Color(0xFF2A3140), Color(0xFF1A202B)],
                                    ),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(book.title.isEmpty ? '?' : book.title[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                                  Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 5),
                                  Text('${book.wordCount} words · ${book.status.name}', style: const TextStyle(color: Color(0xFF7D8799), fontSize: 12)),
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
        child: _selected == null
            ? const EmptyPanel(icon: Icons.chrome_reader_mode_outlined, title: 'Choose a book', body: 'Select a manuscript to read or edit it.')
            : Column(children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 18, 12),
                  child: Row(children: <Widget>[
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(_selected!.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text('${_selected!.author} · ${_selected!.wordCount} words · ${_selected!.estimatedMinutes} min${_saving ? ' · saving…' : ''}', style: const TextStyle(color: Color(0xFF848EA1))),
                    ])),
                    SegmentedButton<bool>(
                      segments: const <ButtonSegment<bool>>[
                        ButtonSegment<bool>(value: true, icon: Icon(Icons.visibility_outlined), label: Text('Read')),
                        ButtonSegment<bool>(value: false, icon: Icon(Icons.edit_outlined), label: Text('Edit')),
                      ],
                      selected: <bool>{_preview},
                      onSelectionChanged: (Set<bool> value) => setState(() => _preview = value.first),
                    ),
                    const SizedBox(width: 8),
                    IconButton(onPressed: _editMetadata, tooltip: 'Metadata', icon: const Icon(Icons.badge_outlined)),
                    IconButton(onPressed: _delete, tooltip: 'Delete local copy', icon: const Icon(Icons.delete_outline)),
                    FilledButton.icon(onPressed: _busy ? null : _publish, icon: const Icon(Icons.publish_rounded), label: const Text('Publish')),
                  ]),
                ),
                if (_busy && _progress != null)
                  Column(children: <Widget>[
                    LinearProgressIndicator(value: _progress!.fraction, minHeight: 3),
                    Padding(padding: const EdgeInsets.all(6), child: Text(_progress!.phase, style: const TextStyle(fontSize: 12, color: Color(0xFF8993A6)))),
                  ]),
                Expanded(
                  child: _preview
                      ? ReadingPane(book: _selected!)
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
                          child: TextField(
                            controller: _editor,
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.55),
                            decoration: const InputDecoration(contentPadding: EdgeInsets.all(22), hintText: 'Write Markdown…'),
                          ),
                        ),
                ),
              ]),
      ),
    ]);
  }
}

class ReadingPane extends StatelessWidget {
  const ReadingPane({super.key, required this.book});
  final BookDocument book;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(48, 24, 48, 80),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: book.content.split('\n').map((String line) => MarkdownLine(line: line)).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MarkdownLine extends StatelessWidget {
  const MarkdownLine({super.key, required this.line});
  final String line;

  @override
  Widget build(BuildContext context) {
    if (line.trim().isEmpty) return const SizedBox(height: 12);
    if (line.startsWith('# ')) {
      return Padding(padding: const EdgeInsets.only(top: 14, bottom: 18), child: Text(line.substring(2), style: const TextStyle(fontSize: 36, height: 1.12, fontWeight: FontWeight.w900)));
    }
    if (line.startsWith('## ')) {
      return Padding(padding: const EdgeInsets.only(top: 28, bottom: 10), child: Text(line.substring(3), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)));
    }
    if (line.startsWith('### ')) {
      return Padding(padding: const EdgeInsets.only(top: 22, bottom: 8), child: Text(line.substring(4), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)));
    }
    if (line.startsWith('> ')) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: Color(0xFF171D29), border: Border(left: BorderSide(color: Color(0xFF7C5CFC), width: 4))),
        child: Text(line.substring(2), style: const TextStyle(fontStyle: FontStyle.italic, height: 1.65)),
      );
    }
    if (line.trim() == '---') return const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Divider());
    if (RegExp(r'^\s*[-*]\s+').hasMatch(line)) {
      return Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const Text('•  ', style: TextStyle(fontSize: 18)),
          Expanded(child: Text(line.replaceFirst(RegExp(r'^\s*[-*]\s+'), ''), style: const TextStyle(fontSize: 16, height: 1.65))),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(line, style: const TextStyle(fontSize: 16, height: 1.72, color: Color(0xFFD7DCE6))),
    );
  }
}

class GeneratorPanel extends StatefulWidget {
  const GeneratorPanel({super.key, required this.onGenerate, required this.busy});
  final ValueChanged<GenerationRequest> onGenerate;
  final bool busy;

  @override
  State<GeneratorPanel> createState() => _GeneratorPanelState();
}

class _GeneratorPanelState extends State<GeneratorPanel> {
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
        const Text('Design the architecture first, then generate one chapter at a time into an editable manuscript.', style: TextStyle(color: Color(0xFF8A94A6))),
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
                    DropdownMenu<String>(
                      initialSelection: _depth,
                      label: const Text('Depth'),
                      dropdownMenuEntries: const <DropdownMenuEntry<String>>[
                        DropdownMenuEntry<String>(value: 'Accessible', label: 'Accessible'),
                        DropdownMenuEntry<String>(value: 'Advanced', label: 'Advanced'),
                        DropdownMenuEntry<String>(value: 'Research-grade', label: 'Research-grade'),
                      ],
                      onSelected: (String? value) => setState(() => _depth = value ?? _depth),
                    ),
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

class RepositoryPanel extends StatelessWidget {
  const RepositoryPanel({
    super.key,
    required this.owner,
    required this.repo,
    required this.branch,
    required this.directory,
    required this.books,
    required this.busy,
    required this.onScan,
    required this.onOpen,
  });

  final TextEditingController owner;
  final TextEditingController repo;
  final TextEditingController branch;
  final TextEditingController directory;
  final List<RepositoryBook> books;
  final bool busy;
  final VoidCallback onScan;
  final ValueChanged<RepositoryBook> onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(30),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const Text('Repository library', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Recursively scan a GitHub repository, import its books, and publish edited Markdown editions.', style: TextStyle(color: Color(0xFF8A94A6))),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: <Widget>[
              Expanded(child: TextField(controller: owner, decoration: const InputDecoration(labelText: 'Owner'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: repo, decoration: const InputDecoration(labelText: 'Repository'))),
              const SizedBox(width: 12),
              SizedBox(width: 140, child: TextField(controller: branch, decoration: const InputDecoration(labelText: 'Branch'))),
              const SizedBox(width: 12),
              SizedBox(width: 165, child: TextField(controller: directory, decoration: const InputDecoration(labelText: 'Publish folder'))),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: busy ? null : onScan,
                icon: busy ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.radar),
                label: const Text('Scan'),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: books.isEmpty
              ? const EmptyPanel(icon: Icons.account_tree_outlined, title: 'Repository not scanned', body: 'Scan ornab74/books or another repository to catalog Markdown, text, and DOCX files.')
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
                        subtitle: Text('${book.path} · ${formatBytes(book.size)}'),
                        trailing: const Icon(Icons.download_rounded),
                        onTap: busy ? null : () => onOpen(book),
                      );
                    },
                  ),
                ),
        ),
      ]),
    );
  }

  String formatBytes(int bytes) {
    if (bytes > 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes > 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.githubToken, required this.apiKey, required this.endpoint, required this.model});

  final TextEditingController githubToken;
  final TextEditingController apiKey;
  final TextEditingController endpoint;
  final TextEditingController model;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(34),
      children: <Widget>[
        const Text('Connections', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Secrets stay in memory for this session and are never written into the book library.', style: TextStyle(color: Color(0xFF8A94A6))),
        const SizedBox(height: 26),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Column(children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.code),
                      title: Text('GitHub publishing', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('Use a fine-grained token with Contents read/write permission only for target repositories.'),
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: githubToken, obscureText: true, decoration: const InputDecoration(labelText: 'GitHub token', prefixIcon: Icon(Icons.key))),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.psychology_alt_outlined),
                      title: Text('OpenAI-compatible generation', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('Works with hosted APIs or local servers exposing the chat-completions shape.'),
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: endpoint, decoration: const InputDecoration(labelText: 'Chat completions endpoint', prefixIcon: Icon(Icons.link))),
                    const SizedBox(height: 12),
                    Row(children: <Widget>[
                      Expanded(child: TextField(controller: model, decoration: const InputDecoration(labelText: 'Model'))),
                      const SizedBox(width: 12),
                      Expanded(child: TextField(controller: apiKey, obscureText: true, decoration: const InputDecoration(labelText: 'API key', prefixIcon: Icon(Icons.key)))),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({super.key, required this.icon, required this.title, required this.body});
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
