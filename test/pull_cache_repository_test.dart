import 'dart:async';

import 'package:offline_sync_engine/offline_sync_engine.dart';
import 'package:test/test.dart';

class _Report {
  _Report(this.id, this.title);
  final String id;
  final String title;
}

void main() {
  group('PullCacheRepository', () {
    late MemoryLocalDataStore<_Report, String> store;
    late PullCacheRepository<_Report, String> repo;
    var online = true;
    var fetchCount = 0;

    setUp(() {
      store = MemoryLocalDataStore(idOf: (r) => r.id);
      repo = PullCacheRepository(
        store: store,
        fetchAll: () async {
          fetchCount++;
          return [_Report('1', 'from-server')];
        },
        isOnline: () async => online,
      );
    });

    tearDown(() => repo.dispose());

    test('load returns local data when offline', () async {
      await store.replaceAll([_Report('local', 'cached')]);
      online = false;

      final result = await repo.load();

      expect(result.source, CacheDataSource.localOnly);
      expect(result.items.single.title, 'cached');
      expect(fetchCount, 0);
    });

    test('load refreshes when online', () async {
      online = true;
      final result = await repo.load();

      expect(result.source, CacheDataSource.refreshed);
      expect(result.items.single.title, 'from-server');
      expect(fetchCount, 1);
    });

    test('invalidateSession drops stale refresh', () async {
      online = true;
      final gate = Completer<void>();
      repo = PullCacheRepository(
        store: store,
        fetchAll: () async {
          await gate.future;
          return [_Report('stale', 'stale')];
        },
        isOnline: () async => online,
      );

      final refreshFuture = repo.refresh();
      repo.invalidateSession();
      gate.complete();
      await refreshFuture;

      expect(await store.getAll(), isEmpty);
      repo.dispose();
    });
  });
}
