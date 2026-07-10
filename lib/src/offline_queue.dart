/// A pluggable storage adapter for one offline queue (e.g. "check-in/out",
/// "task activities", "activity reports"). The sync engine never talks to
/// Hive/sqflite/etc. directly — it only talks to this interface, so the
/// same engine works regardless of what's underneath.
///
/// [T] is the domain item type (e.g. `CheckInOutAction`, `OfflineTaskActivity`).
/// [id] is whatever key the storage uses to address a single item.
abstract class OfflineQueueStore<T, Id> {
  /// All items currently pending sync, in the order they should be sent.
  /// (Ordering — e.g. "sort by timestamp, not insertion order" — is the
  /// adapter's responsibility, since only it knows its storage quirks.)
  Future<List<T>> getPending();

  /// Removes an item after it has been successfully synced.
  Future<void> remove(Id id);

  /// Returns the item with this [id] regardless of its status (pending or
  /// already marked failed), or `null` if it no longer exists.
  ///
  /// Needed by `SyncPass.retryOne`: retrying a specific failed item means
  /// looking it up by id, but [getPending] deliberately excludes failed
  /// items (that's what keeps them out of the normal loop), so this is a
  /// separate lookup. A straightforward implementation is a direct
  /// key-based read from whatever storage backs [getPending] — see the
  /// storage adapter example in `doc/GUIDE.md` for a Hive-backed reference.
  Future<T?> getById(Id id);

  /// Marks an item as failed without removing it, so it's visible to the
  /// user (e.g. for a retry/delete banner) instead of just vanishing.
  Future<void> markFailed(Id id, {String? errorMessage});

  Id idOf(T item);
}
