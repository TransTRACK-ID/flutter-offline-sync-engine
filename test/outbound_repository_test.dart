import 'package:offline_sync_engine/offline_sync_engine.dart';
import 'package:test/test.dart';

class _Draft {
  _Draft(this.id, this.status, [this.error]);
  final String id;
  OutboundItemStatus status;
  String? error;
}

void main() {
  group('OutboundRepository', () {
    late MemoryLocalDataStore<_Draft, String> store;
    late OutboundRepository<_Draft, String> repo;
    var online = false;
    var pushCount = 0;

    setUp(() {
      store = MemoryLocalDataStore(idOf: (d) => d.id);
      repo = OutboundRepository(
        readStore: store,
        queueStore: _QueueStore(store),
        pushOne: (_) async {
          pushCount++;
          return const SyncOutcome.success();
        },
        isOnline: () async => online,
        statusOf: (d) => d.status,
        withStatus: (d, status, {errorMessage}) {
          d.status = status;
          d.error = errorMessage;
          return d;
        },
      );
    });

    tearDown(() => repo.dispose());

    test('save keeps item locally when offline', () async {
      await repo.save(_Draft('1', OutboundItemStatus.pending));

      final all = await repo.getAll();
      expect(all, hasLength(1));
      expect(pushCount, 0);
    });

    test('save triggers sync when online', () async {
      online = true;
      await repo.save(_Draft('1', OutboundItemStatus.pending));

      expect(pushCount, 1);
      expect(await repo.getAll(), isEmpty);
    });
  });
}

class _QueueStore implements OfflineQueueStore<_Draft, String> {
  _QueueStore(this._store);
  final MemoryLocalDataStore<_Draft, String> _store;

  @override
  Future<List<_Draft>> getPending() async {
    final all = await _store.getAll();
    return all.where((d) => d.status == OutboundItemStatus.pending).toList();
  }

  @override
  Future<_Draft?> getById(String id) => _store.getById(id);

  @override
  Future<void> remove(String id) => _store.deleteById(id);

  @override
  Future<void> markFailed(String id, {String? errorMessage}) async {
    final item = await _store.getById(id);
    if (item == null) return;
    item.status = OutboundItemStatus.failed;
    item.error = errorMessage;
    await _store.upsert(item);
  }

  @override
  String idOf(_Draft item) => item.id;
}
