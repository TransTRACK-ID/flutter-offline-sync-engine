import 'dart:async';

import '../generation_guard.dart';
import '../keyed_single_flight.dart';
import '../mutation_queue.dart';
import 'cache_state.dart';
import 'local_data_store.dart';

/// Full pull-cache repository: local-first reads for offline screens, guarded
/// refresh from the server, and change streams for UI rebuilds.
class PullCacheRepository<T, Id> {
  PullCacheRepository({
    required LocalDataStore<T, Id> store,
    required Future<List<T>> Function() fetchAll,
    required Future<bool> Function() isOnline,
    this.refreshKey = 'refresh',
    Future<void> Function(List<T> items)? onRefreshed,
  })  : _store = store,
        _fetchAll = fetchAll,
        _isOnline = isOnline,
        _onRefreshed = onRefreshed;

  final LocalDataStore<T, Id> _store;
  final Future<List<T>> Function() _fetchAll;
  final Future<bool> Function() _isOnline;
  final Future<void> Function(List<T> items)? _onRefreshed;
  final String refreshKey;

  final _sessionGuard = GenerationGuard();
  final _fetchGuard = GenerationGuard();
  final _refreshGuard = KeyedSingleFlight<String>();
  final _writes = MutationQueue();

  DateTime? _lastUpdatedAt;
  bool _refreshing = false;
  final _snapshotController = StreamController<int>.broadcast();
  var _snapshotTick = 0;

  Stream<CacheSnapshot<T>> watchSnapshot() async* {
    yield await _currentSnapshot();
    await for (final _ in _snapshotController.stream) {
      yield await _currentSnapshot();
    }
  }

  Stream<void> watchChanges() => _store.watchChanges();

  Future<List<T>> getAll() => _store.getAll();

  Future<T?> getById(Id id) => _store.getById(id);

  DateTime? get lastUpdatedAt => _lastUpdatedAt;

  bool get isRefreshing => _refreshing;

  Future<CacheLoadResult<T>> load({bool refreshIfOnline = true}) async {
    final local = await _store.getAll();

    if (!refreshIfOnline || !await _isOnline()) {
      return CacheLoadResult(
        items: local,
        source: CacheDataSource.localOnly,
      );
    }

    try {
      await refresh();
      return CacheLoadResult(
        items: await _store.getAll(),
        source: CacheDataSource.refreshed,
      );
    } catch (e) {
      return CacheLoadResult(
        items: local,
        source: CacheDataSource.refreshFailed,
        refreshError: e,
      );
    }
  }

  Future<void> refresh() {
    return _refreshGuard.run(refreshKey, _refreshInternal);
  }

  Future<void> _refreshInternal() async {
    final sessionToken = _sessionGuard.generation;
    final fetchToken = _fetchGuard.bump();

    _refreshing = true;
    _emitSnapshot();

    try {
      final fetched = await _fetchAll();

      if (!_sessionGuard.isCurrent(sessionToken)) return;
      if (!_fetchGuard.isCurrent(fetchToken)) return;

      await _writes.enqueue(() async {
        if (!_sessionGuard.isCurrent(sessionToken)) return;
        if (!_fetchGuard.isCurrent(fetchToken)) return;

        await _store.replaceAll(fetched);
        _lastUpdatedAt = DateTime.now();
        final hook = _onRefreshed;
        if (hook != null) {
          await hook(fetched);
        }
        _emitSnapshot();
      });
    } finally {
      _refreshing = false;
      _emitSnapshot();
    }
  }

  Future<void> reconcile(
    Id id,
    Future<List<T>> Function(Id id) fetchForId,
  ) {
    return _reconcileGuard.run(id, () => _reconcileInternal(id, fetchForId));
  }

  final _reconcileGuard = KeyedSingleFlight<Id>();

  Future<void> _reconcileInternal(
    Id id,
    Future<List<T>> Function(Id id) fetchForId,
  ) async {
    final sessionToken = _sessionGuard.generation;
    final fetchToken = _fetchGuard.bump();

    final fetched = await fetchForId(id);

    if (!_sessionGuard.isCurrent(sessionToken)) return;
    if (!_fetchGuard.isCurrent(fetchToken)) return;

    await _writes.enqueue(() async {
      if (!_sessionGuard.isCurrent(sessionToken)) return;
      if (!_fetchGuard.isCurrent(fetchToken)) return;

      for (final item in fetched) {
        await _store.upsert(item);
      }
      _lastUpdatedAt = DateTime.now();
      _emitSnapshot();
    });
  }

  void invalidateSession() {
    _sessionGuard.bump();
    _fetchGuard.bump();
  }

  Future<CacheSnapshot<T>> _currentSnapshot() async {
    return CacheSnapshot(
      items: await _store.getAll(),
      lastUpdatedAt: _lastUpdatedAt,
      isRefreshing: _refreshing,
    );
  }

  void _emitSnapshot() {
    if (!_snapshotController.isClosed) {
      _snapshotController.add(++_snapshotTick);
    }
  }

  void dispose() {
    _snapshotController.close();
    _store.dispose();
  }
}
