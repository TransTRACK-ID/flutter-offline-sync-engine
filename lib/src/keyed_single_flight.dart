import 'dart:async';

/// Collapses concurrent calls that share the same [K] key into one
/// in-flight operation.
class KeyedSingleFlight<K> {
  final _inFlight = <K, Future<void>>{};

  /// Runs [action] for [key], or — if [key] already has a run in progress
  /// — returns that same in-flight [Future] instead of starting a second,
  /// overlapping one.
  Future<void> run(K key, Future<void> Function() action) {
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final wrapped = () async {
      try {
        await action();
      } finally {
        _inFlight.remove(key);
      }
    }();

    _inFlight[key] = wrapped;
    return wrapped;
  }

  /// Whether [key] currently has a run in progress.
  bool isRunning(K key) => _inFlight.containsKey(key);
}
