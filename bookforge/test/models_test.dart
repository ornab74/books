import 'package:bookforge_studio/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BookDocument calculates metrics and round-trips', () {
    final DateTime now = DateTime.utc(2026, 8, 4);
    final BookDocument original = BookDocument(
      id: '1',
      title: 'Test Book',
      author: 'Graylan Janulis',
      content: '# Test\n\n${List<String>.filled(441, 'word').join(' ')}',
      format: BookFormat.markdown,
      origin: BookOrigin.generated,
      status: BookStatus.review,
      createdAt: now,
      updatedAt: now,
      tags: const <String>['systems'],
    );

    final BookDocument restored = BookDocument.fromJson(original.toJson());
    expect(restored.title, original.title);
    expect(restored.wordCount, greaterThanOrEqualTo(441));
    expect(restored.estimatedMinutes, 3);
    expect(restored.tags, contains('systems'));
  });

  test('GenerationProgress reports a fraction', () {
    const GenerationProgress progress = GenerationProgress(completed: 3, total: 6, phase: 'Writing');
    expect(progress.fraction, 0.5);
  });
}
