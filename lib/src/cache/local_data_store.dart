import 'dart:async';

/// Read/write interface for a local mirror of server data (pull-cache) or
/// for displaying outbound queue items. Backends (Hive, Drift, in-memory)
/// implement this; repositories never touch storage directly.
abstract class LocalDataStore<T, Id> {
  /// All cached items, in display order (sorting is the adapter's job).
  Future<List<T>> getAll();

  Future<T?> getById(Id id);

  /// Replace the entire local snapshot (typical list refresh).
  Future<void> replaceAll(List<T> items);

  Future<void> upsert(T item);

  Future<void> deleteById(Id id);

  Id idOf(T item);

  /// Emits whenever local data changes. Implementations may emit on every
  /// write or debounce — callers should treat this as "something changed."
  Stream<void> watchChanges();

  /// Optional disposal hook for stream controllers, box closes, etc.
  void dispose() {}
}
