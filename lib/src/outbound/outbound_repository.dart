import 'dart:async';

import '../offline_queue.dart';
import '../sync_outcome.dart';
import '../sync_pass.dart';
import '../cache/local_data_store.dart';

/// Status of an item in an outbound (push-queue) domain.
enum OutboundItemStatus {
  pending,
  failed,
}

/// Combines local persistence, UI read streams, and [SyncPass] for one
/// outbound domain (forms, check-ins, expense reports, …).
class OutboundRepository<T, Id> {
  OutboundRepository({
    required LocalDataStore<T, Id> readStore,
    required OfflineQueueStore<T, Id> queueStore,
    required Future<SyncOutcome> Function(T item) pushOne,
    required Future<bool> Function() isOnline,
    required OutboundItemStatus Function(T item) statusOf,
    required T Function(T item, OutboundItemStatus status, {String? errorMessage})
        withStatus,
    this.stopOnTransientFailure = true,
  })  : _readStore = readStore,
        _isOnline = isOnline,
        _statusOf = statusOf,
        _withStatus = withStatus,
        _syncPass = SyncPass<T, Id>(
          store: queueStore,
          pushOne: pushOne,
          stopOnTransientFailure: stopOnTransientFailure,
        );

  final LocalDataStore<T, Id> _readStore;
  final Future<bool> Function() _isOnline;
  final OutboundItemStatus Function(T item) _statusOf;
  final T Function(T item, OutboundItemStatus status, {String? errorMessage})
      _withStatus;
  final SyncPass<T, Id> _syncPass;

  final bool stopOnTransientFailure;

  /// Exposed so [SyncOrchestrator.syncAll] can include this domain.
  SyncPass<T, Id> get syncPass => _syncPass;

  Stream<List<T>> watchAll() async* {
    yield await _readStore.getAll();
    yield* _readStore.watchChanges().asyncMap((_) => _readStore.getAll());
  }

  Stream<List<T>> watchPending() async* {
    yield await pending();
    yield* _readStore.watchChanges().asyncMap((_) => pending());
  }

  Future<List<T>> getAll() => _readStore.getAll();

  Future<List<T>> pending() async {
    final all = await _readStore.getAll();
    return all
        .where((item) => _statusOf(item) == OutboundItemStatus.pending)
        .toList();
  }

  Future<List<T>> failed() async {
    final all = await _readStore.getAll();
    return all
        .where((item) => _statusOf(item) == OutboundItemStatus.failed)
        .toList();
  }

  Future<T?> getById(Id id) => _readStore.getById(id);

  /// Save locally (pending) and optionally trigger sync when online.
  Future<void> save(T item, {bool syncIfOnline = true}) async {
    final toSave = _withStatus(item, OutboundItemStatus.pending);
    await _readStore.upsert(toSave);
    if (syncIfOnline && await _isOnline()) {
      await _syncPass.run();
    }
  }

  Future<SyncPassResult> sync() => _syncPass.run();

  Future<SyncOutcome?> retryOne(Id id) => _syncPass.retryOne(id);

  Future<void> deleteLocal(Id id) => _readStore.deleteById(id);

  Stream<SyncItemEvent<T, Id>> get onItemResult => _syncPass.onItemResult;

  void dispose() {
    _syncPass.dispose();
    _readStore.dispose();
  }
}
