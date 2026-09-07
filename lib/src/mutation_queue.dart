/// Serializes local-storage writes onto a single chain so overlapping
/// pulls (a background refresh and a foreground reconcile landing at the
/// same time, say) don't race each other writing to the same store.
///
/// Each enqueued mutation waits for the previous one to finish before it
/// starts, regardless of success or failure — one failed write doesn't
/// jam the queue for everything queued after it, and the caller of that
/// specific [enqueue] call still sees its own error.
///
/// ```dart
/// final _writes = MutationQueue();
///
/// Future<void> upsertCompleted(Transaction transaction) {
///   return _writes.enqueue(() async {
///     await _db.upsert(transaction);
///     _notifyChanges();
///   });
/// }
/// ```
class MutationQueue {
  Future<void> _chain = Future<void>.value();

  /// Runs [action] after every mutation already queued has finished, and
  /// returns [action]'s own result (or throws its own error) — only the
  /// *ordering* is shared, not the outcome.
  Future<T> enqueue<T>(Future<T> Function() action) {
    final run = _chain.then((_) => action());
    _chain = run.then<void>((_) {}, onError: (_) {});
    return run;
  }
}
