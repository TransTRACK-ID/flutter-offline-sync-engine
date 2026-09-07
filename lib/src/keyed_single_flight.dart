import 'dart:async';

/// Collapses concurrent calls that share the same [K] key into one
/// in-flight operation, so two callers asking for the same thing at once
/// (a list screen and a detail screen both reconciling the same record,
/// a user tapping "refresh" twice) share one run instead of racing.
///
/// This is the keyed counterpart to the single-flight guard
/// [SyncOrchestrator] already does for a fixed, known-upfront set of
/// outbound passes. Inbound (pull) sync usually doesn't have a fixed set
/// of keys — the key space is dynamic (one per remote record id) — so it
/// needs a map-based guard instead of one boolean/future field.
///
/// One instance per *kind* of operation, reused across all keys of that
/// kind — e.g. one [KeyedSingleFlight] for "reconcile this transaction's
/// readings," keyed by transaction number, and (optionally) a second one
/// for "refresh the whole list," called with a single constant key since
/// there's only one list.
///
/// ```dart
/// final _reconcileGuard = KeyedSingleFlight<String>();
///
/// Future<void> reconcileTransaction(String trxNumber) {
///   return _reconcileGuard.run(trxNumber, () => _reconcileInternal(trxNumber));
/// }
/// ```
class KeyedSingleFlight<K> {
  final _inFlight = <K, Future<void>>{};

  /// Runs [action] for [key], or — if [key] already has a run in progress
  /// — returns that same in-flight [Future] instead of starting a second,
  /// overlapping one.
  Future<void> run(K key, Future<void> Function() action) {
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = action().whenComplete(() => _inFlight.remove(key));
    _inFlight[key] = future;
    return future;
  }

  /// Whether [key] currently has a run in progress.
  bool isRunning(K key) => _inFlight.containsKey(key);
}
