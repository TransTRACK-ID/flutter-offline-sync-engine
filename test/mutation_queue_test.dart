import 'dart:async';

import 'package:offline_sync_engine/offline_sync_engine.dart';
import 'package:test/test.dart';

void main() {
  group('MutationQueue', () {
    test('mutations run in the order they were enqueued', () async {
      final queue = MutationQueue();
      final order = <int>[];

      final a = queue.enqueue(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        order.add(1);
      });
      final b = queue.enqueue(() async {
        order.add(2);
      });

      await Future.wait([a, b]);
      expect(order, [1, 2]);
    });

    test('enqueue returns the action\'s own result', () async {
      final queue = MutationQueue();
      final result = await queue.enqueue(() async => 42);
      expect(result, 42);
    });

    test('a failed mutation does not block the ones queued after it', () async {
      final queue = MutationQueue();

      final failed = queue.enqueue(() async => throw StateError('boom'));
      var secondRan = false;
      final second = queue.enqueue(() async => secondRan = true);

      await expectLater(failed, throwsStateError);
      await second;
      expect(secondRan, isTrue);
    });

    test('a failed mutation only surfaces its error to its own caller', () async {
      final queue = MutationQueue();

      final failed = queue.enqueue(() async => throw StateError('boom'));
      final ok = queue.enqueue(() async => 'fine');

      await expectLater(failed, throwsStateError);
      expect(await ok, 'fine');
    });
  });
}
