import 'dart:async';

import '../cache/local_data_store.dart';

/// In-memory [LocalDataStore] for unit tests and quick prototypes.
class MemoryLocalDataStore<T, Id> implements LocalDataStore<T, Id> {
  MemoryLocalDataStore({
    required Id Function(T item) idOf,
    this.sort,
  }) : _idOf = idOf;

  final Id Function(T item) _idOf;
  final int Function(T a, T b)? sort;

  @override
  Id idOf(T item) => _idOf(item);

  final _items = <Id, T>{};
  final _changes = StreamController<int>.broadcast();
  var _changeTick = 0;

  @override
  Future<List<T>> getAll() async {
    final list = _items.values.toList();
    if (sort != null) {
      list.sort(sort);
    }
    return list;
  }

  @override
  Future<T?> getById(Id id) async => _items[id];

  @override
  Future<void> replaceAll(List<T> items) async {
    _items
      ..clear()
      ..addEntries(items.map((e) => MapEntry(_idOf(e), e)));
    _notify();
  }

  @override
  Future<void> upsert(T item) async {
    _items[_idOf(item)] = item;
    _notify();
  }

  @override
  Future<void> deleteById(Id id) async {
    _items.remove(id);
    _notify();
  }

  @override
  Stream<void> watchChanges() => _changes.stream.map((_) {});

  void _notify() {
    if (!_changes.isClosed) _changes.add(++_changeTick);
  }

  @override
  void dispose() {
    _changes.close();
  }
}
