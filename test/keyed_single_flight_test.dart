import 'dart:async';

import 'package:offline_sync_engine/offline_sync_engine.dart';
import 'package:test/test.dart';

void main() {
  group('KeyedSingleFlight', () {
    test('a second call for the same key reuses the in-flight run', () async {
      final guard = KeyedSingleFlight<String>();
      var runCount = 0;
      final gate = Completer<void>();

      final first = guard.run('a', () async {
        runCount++;
        await gate.future;
      });
      final second = guard.run('a', () async {
        runCount++;
        await gate.future;
      });

      expect(guard.isRunning('a'), isTrue);
      gate.complete();
      await Future.wait([first, second]);

      expect(runCount, 1);
    });

    test('different keys run independently', () async {
      final guard = KeyedSingleFlight<String>();
      var runCount = 0;

      await Future.wait([
        guard.run('a', () async => runCount++),
        guard.run('b', () async => runCount++),
      ]);

      expect(runCount, 2);
    });

    test('a key is free again once its run completes', () async {
      final guard = KeyedSingleFlight<String>();
      await guard.run('a', () async {});
      expect(guard.isRunning('a'), isFalse);

      var runCount = 0;
      await guard.run('a', () async => runCount++);
      expect(runCount, 1);
    });

    test('a failed run still frees the key for the next caller', () async {
      final guard = KeyedSingleFlight<String>();

      await expectLater(
        guard.run('a', () async => throw StateError('boom')),
        throwsStateError,
      );
      expect(guard.isRunning('a'), isFalse);

      var ran = false;
      await guard.run('a', () async => ran = true);
      expect(ran, isTrue);
    });
  });
}
