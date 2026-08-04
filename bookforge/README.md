# BookForge Studio

BookForge Studio is a local-first Flutter/Dart application for reading, importing, generating, editing, cataloging, and publishing books.

It was designed around the `ornab74/books` repository: a growing corpus of DOCX books and a roadmap for a much larger generative library. The app lives in its own `bookforge/` workspace so the existing book archive remains untouched.

## Core capabilities

- Import `.md`, `.markdown`, `.txt`, and `.docx` files.
- Convert DOCX paragraph structure and heading styles into editable Markdown.
- Store a local manuscript library with title, author, origin, status, tags, word count, and reading-time estimates.
- Read manuscripts in a focused rendered view or edit the underlying Markdown.
- Recursively scan any accessible GitHub repository for book files.
- Download repository books into the local studio.
- Generate a complete book through an outline-first, chapter-by-chapter pipeline.
- Connect to OpenAI-compatible chat-completions endpoints, including local model servers.
- Publish or update Markdown books in a selected GitHub repository, branch, and directory.
- Add machine-readable front matter during publication.
- Keep API keys and GitHub tokens in memory only for the current session.

## Architecture

```text
bookforge/
├── lib/
│   ├── main.dart
│   └── src/
│       ├── app.dart          # Material 3 desktop studio
│       ├── models.dart       # book, repository, and generation models
│       └── services.dart     # import, persistence, generation, GitHub API
├── test/
│   └── models_test.dart
├── analysis_options.yaml
└── pubspec.yaml
```

The application separates four concerns:

1. **Library layer** — local persistence and manuscript metadata.
2. **Document layer** — import, DOCX extraction, Markdown editing, and reading.
3. **Generation layer** — architecture-first outline generation followed by isolated chapter calls.
4. **Repository layer** — recursive Git tree scanning, file import, and GitHub Contents API publishing.

## Run

Use a current stable Flutter SDK with desktop support enabled.

```bash
cd bookforge
flutter pub get
flutter run -d linux
```

Other supported Flutter targets can be generated or enabled normally:

```bash
flutter config --enable-windows-desktop
flutter config --enable-macos-desktop
flutter config --enable-linux-desktop
flutter devices
```

## GitHub access

Public repositories can be scanned without a token. Private repositories and publishing require a fine-grained GitHub token.

Grant the token only the minimum required access:

- Repository access: selected repositories
- Contents: read and write
- Metadata: read

Enter the token in **Settings → GitHub publishing**. It is not persisted by BookForge.

## Model access

The generation service uses the common chat-completions request shape. Configure:

- Endpoint, such as `https://api.openai.com/v1/chat/completions`
- Model name
- API key when required

A local server can be used by replacing the endpoint and model. The generation pipeline first creates a coherent outline, then writes each chapter independently while preserving the full outline as context. This reduces uncontrolled repetition and makes partial drafts recoverable.

## Publishing behavior

Publishing writes Markdown into the configured directory using a slug derived from the book title. Existing files with the same path are updated rather than duplicated.

Each publication begins with front matter:

```yaml
---
title: "Example Book"
author: "Graylan Janulis"
status: published
updated: 2026-08-04T00:00:00.000Z
tags: ["generated", "advanced"]
---
```

## Validation

```bash
flutter pub get
flutter analyze
flutter test
```

## Next engineering stages

The current foundation is intentionally extensible. Strong next additions include EPUB/PDF export, Git commit history browsing, image and diagram asset management, citation graphs, semantic search across the book corpus, branch-per-edition publishing, collaborative review queues, and resumable multi-agent generation jobs.
