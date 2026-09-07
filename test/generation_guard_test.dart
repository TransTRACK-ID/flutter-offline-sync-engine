import 'package:offline_sync_engine/offline_sync_engine.dart';
import 'package:test/test.dart';

void main() {
  group('GenerationGuard', () {
    test('starts at generation 0 and is current for its own token', () {
      final guard = GenerationGuard();
      expect(guard.generation, 0);
      expect(guard.isCurrent(0), isTrue);
    });

    test('bump advances the generation and returns the new value', () {
      final guard = GenerationGuard();
      final token = guard.bump();
      expect(token, 1);
      expect(guard.generation, 1);
    });

    test('a token captured before a later bump is no longer current', () {
      final guard = GenerationGuard();
      final staleToken = guard.generation;
      guard.bump();
      expect(guard.isCurrent(staleToken), isFalse);
    });

    test('a token captured via bump stays current until the next bump', () {
      final guard = GenerationGuard();
      final token = guard.bump();
      expect(guard.isCurrent(token), isTrue);
      guard.bump();
      expect(guard.isCurrent(token), isFalse);
    });
  });
}
