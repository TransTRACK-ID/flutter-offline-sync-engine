import 'dart:async';

import 'package:hive/hive.dart';

import '../../cache/local_data_store.dart';
import '../../offline_queue.dart';
import '../../outbound/outbound_repository.dart';

/// Hive-backed [LocalDataStore]. Register your type adapter in the app before
/// opening the box.
class HiveLocalDataStore<T, Id> implements LocalDataStore<T, Id> {
  HiveLocalDataStore({
    required Box<T> box,
    required Id Function(T item) idOf,
    this.sort,
  })  : _box = box,
        _idOf = idOf;

  final Box<T> _box;
  final Id Function(T item) _idOf;
  final int Function(T a, T b)? sort;

  @override
  Id idOf(T item) => _idOf(item);

  StreamSubscription<BoxEvent>? _subscription;
  final _changes = StreamController<int>.broadcast();
  var _changeTick = 0;

  Box<T> get box => _box;

  void _ensureWatching() {
    _subscription ??= _box.watch().listen((_) => _notify());
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(++_changeTick);
  }

  List<T> _sortedValues() {
    final list = _box.values.toList();
    if (sort != null) list.sort(sort);
    return list;
  }

  @override
  Future<List<T>> getAll() async {
    _ensureWatching();
    return _sortedValues();
  }

  @override
  Future<T?> getById(Id id) async {
    _ensureWatching();
    return _box.get(id);
  }

  @override
  Future<void> replaceAll(List<T> items) async {
    _ensureWatching();
    await _box.clear();
    for (final item in items) {
      await _box.put(_idOf(item), item);
    }
    _notify();
  }

  @override
  Future<void> upsert(T item) async {
    _ensureWatching();
    await _box.put(idOf(item), item);
    _notify();
  }

  @override
  Future<void> deleteById(Id id) async {
    _ensureWatching();
    await _box.delete(id);
    _notify();
  }

  @override
  Stream<void> watchChanges() {
    _ensureWatching();
    return _changes.stream.map((_) {});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _changes.close();
  }
}

/// Hive-backed [OfflineQueueStore] wired to the same box as [HiveLocalDataStore].
class HiveOutboundQueueStore<T, Id> implements OfflineQueueStore<T, Id> {
  HiveOutboundQueueStore({
    required Box<T> box,
    required Id Function(T item) idOf,
    required this.statusOf,
    required this.withStatus,
    this.sort,
  })  : _box = box,
        _idOf = idOf;

  final Box<T> _box;
  final Id Function(T item) _idOf;
  final OutboundItemStatus Function(T item) statusOf;
  final T Function(T item, OutboundItemStatus status, {String? errorMessage})
      withStatus;
  final int Function(T a, T b)? sort;

  List<T> _sortedValues() {
    final list = _box.values.toList();
    if (sort != null) list.sort(sort);
    return list;
  }

  @override
  Future<List<T>> getPending() async {
    return _sortedValues()
        .where((e) => statusOf(e) == OutboundItemStatus.pending)
        .toList();
  }

  @override
  Future<void> remove(Id id) async {
    await _box.delete(id);
  }

  @override
  Future<T?> getById(Id id) async => _box.get(id);

  @override
  Future<void> markFailed(Id id, {String? errorMessage}) async {
    final existing = _box.get(id);
    if (existing == null) return;
    await _box.put(
      id,
      withStatus(
        existing,
        OutboundItemStatus.failed,
        errorMessage: errorMessage,
      ),
    );
  }

  @override
  Id idOf(T item) => _idOf(item);
}
