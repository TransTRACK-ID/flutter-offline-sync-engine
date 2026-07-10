import 'dart:async';

import 'sync_outcome.dart';
import 'sync_pass.dart';

/// Runs several [SyncPass]es together as one logical "sync everything" run,
/// with the same single-flight guarantee `SyncRepository._inFlightSync` had:
/// if a run is already in progress, callers get back that SAME future
/// instead of starting a second, overlapping run.
class SyncOrchestrator {
  SyncOrchestrator({required this.isOnline});

  /// Reachability check. Pass a real network probe here, not just an
  /// OS-level connectivity flag — see the note on `hasInternetConnection()`
  /// in the proposal doc for why that distinction matters.
  final Future<bool> Function() isOnline;

  Future<Map<String, SyncPassResult>>? _inFlight;

  final StreamController<bool> _syncStateController =
      StreamController<bool>.broadcast();

  /// Whether a `syncAll()` run is currently in progress. Synchronous, so
  /// it's correct immediately — e.g. for the initial value passed into a
  /// widget — without waiting for a stream event.
  bool get isSyncing => _inFlight != null;

  /// Emits `true` right before a run starts and `false` right after it
  /// finishes (success or error). Broadcast, so any number of listeners
  /// (a loading spinner, a flash-message presenter, ...) can subscribe
  /// independently. Plain `Stream<bool>` from `dart:async` — no Flutter
  /// import needed to consume it, same "pure Dart" rule as the rest of
  /// the kit.
  ///
  /// A second overlapping `syncAll()` call does NOT emit another `true`
  /// — it's still the same run, per the single-flight guarantee below.
  Stream<bool> get syncStateChanges => _syncStateController.stream;

  /// [passes] is a name -> SyncPass map so results can be reported per
  /// domain (e.g. `{'checkInOut': ..., 'taskActivities': ..., 'reports': ...}`)
  /// the same way the original unified sync message did.
  Future<Map<String, SyncPassResult>> syncAll(
    Map<String, SyncPass> passes,
  ) {
    final existing = _inFlight;
    if (existing != null) return existing;

    _syncStateController.add(true);
    final future = _runAll(passes).whenComplete(() {
      _inFlight = null;
      _syncStateController.add(false);
    });
    _inFlight = future;
    return future;
  }

  Future<Map<String, SyncPassResult>> _runAll(
    Map<String, SyncPass> passes,
  ) async {
    if (!await isOnline()) {
      return {
        for (final name in passes.keys)
          name: SyncPassResult(
            successCount: 0,
            failureCount: 0,
            stoppedEarly: true,
            failures: [
              SyncItemFailure(itemId: '-', reason: 'no internet connection'),
            ],
          ),
      };
    }

    final results = <String, SyncPassResult>{};
    for (final entry in passes.entries) {
      results[entry.key] = await entry.value.run();
      // Matches the original behavior: once one domain's pass stops early
      // on a transient failure, don't bother trying the next domain in
      // this same run — the network is presumably still not ready.
      if (results[entry.key]!.stoppedEarly) break;
    }
    return results;
  }

  /// Closes the internal stream controller. Call this when whatever owns
  /// the orchestrator (a service, a cubit, ...) is disposed — same as
  /// you would for any other `StreamController`-backed API.
  void dispose() {
    _syncStateController.close();
  }
}
