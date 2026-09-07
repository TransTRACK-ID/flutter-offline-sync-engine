import '../../cache/local_data_store.dart';
import '../../offline_queue.dart';
import '../../outbound/outbound_repository.dart';

/// App implements this against generated Drift tables. Codegen scaffolds a
/// stub when you run `dart run offline_sync_engine:generate_domain`.
abstract class DriftCacheAdapter<T, Id> {
  Future<List<T>> getAll();

  Future<T?> getById(Id id);

  Future<void> replaceAll(List<T> items);

  Future<void> upsert(T item);

  Future<void> deleteById(Id id);

  Id idOf(T item);

  /// Typically `table.watch()` mapped to void, or a broadcast controller fed
  /// from your DAO after writes.
  Stream<void> watchChanges();
}

/// Drift-backed [LocalDataStore] — thin wrapper over [DriftCacheAdapter].
class DriftLocalDataStore<T, Id> implements LocalDataStore<T, Id> {
  DriftLocalDataStore(this._adapter);

  final DriftCacheAdapter<T, Id> _adapter;

  @override
  Future<List<T>> getAll() => _adapter.getAll();

  @override
  Future<T?> getById(Id id) => _adapter.getById(id);

  @override
  Future<void> replaceAll(List<T> items) => _adapter.replaceAll(items);

  @override
  Future<void> upsert(T item) => _adapter.upsert(item);

  @override
  Future<void> deleteById(Id id) => _adapter.deleteById(id);

  @override
  Id idOf(T item) => _adapter.idOf(item);

  @override
  Stream<void> watchChanges() => _adapter.watchChanges();

  @override
  void dispose() {}
}

/// App implements this for outbound queue columns (status, error_message, …).
abstract class DriftOutboundAdapter<T, Id> {
  Future<List<T>> getAll();

  Future<T?> getById(Id id);

  Future<void> deleteById(Id id);

  Future<void> save(T item);

  Id idOf(T item);

  OutboundItemStatus statusOf(T item);

  T withStatus(T item, OutboundItemStatus status, {String? errorMessage});
}

/// Drift-backed [OfflineQueueStore].
class DriftOutboundQueueStore<T, Id> implements OfflineQueueStore<T, Id> {
  DriftOutboundQueueStore(this._adapter);

  final DriftOutboundAdapter<T, Id> _adapter;

  @override
  Future<List<T>> getPending() async {
    final all = await _adapter.getAll();
    return all
        .where((e) => _adapter.statusOf(e) == OutboundItemStatus.pending)
        .toList();
  }

  @override
  Future<void> remove(Id id) => _adapter.deleteById(id);

  @override
  Future<T?> getById(Id id) => _adapter.getById(id);

  @override
  Future<void> markFailed(Id id, {String? errorMessage}) async {
    final existing = await _adapter.getById(id);
    if (existing == null) return;
    await _adapter.save(
      _adapter.withStatus(
        existing,
        OutboundItemStatus.failed,
        errorMessage: errorMessage,
      ),
    );
  }

  @override
  Id idOf(T item) => _adapter.idOf(item);
}
