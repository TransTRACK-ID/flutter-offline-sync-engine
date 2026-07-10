import 'dart:async';

import 'offline_queue.dart';
import 'sync_outcome.dart';

/// Runs one queue through to completion (or until a transient failure
/// stops it), applying the exact same loop shape that used to be
/// hand-written per domain in SyncRepository:
///
///   for each pending item:
///     if pushOne fails transiently -> stop the whole pass, leave it pending
///     if pushOne fails permanently -> markFailed, keep going
///     if pushOne succeeds -> remove from queue, keep going
///
/// [pushOne] is the only thing that differs between domains (check-in/out
/// vs. task activity vs. activity report) — everything else is identical,
/// so it's written once here instead of three times.
class SyncPass<T, Id> {
  SyncPass({
    required this.store,
    required this.pushOne,
    this.stopOnTransientFailure = true,
  });

  final OfflineQueueStore<T, Id> store;

  /// Attempts to push a single item to the server and classifies the
  /// result. Should not throw for expected failure modes — return a
  /// [SyncOutcome.transientFailure] / [SyncOutcome.permanentFailure]
  /// instead. Unexpected exceptions are still caught and treated as
  /// permanent failures so one bad item can't crash the whole pass.
  final Future<SyncOutcome> Function(T item) pushOne;

  /// Whether a transient failure aborts the remaining queue (matches the
  /// original app's behavior for all three domains) or just skips that
  /// item and continues.
  final bool stopOnTransientFailure;

  final _itemEventController =
      StreamController<SyncItemEvent<T, Id>>.broadcast();

  /// Emitted once per item, from both `run()`'s loop and `retryOne()` —
  /// see [SyncItemEvent]. Broadcast, so multiple listeners (a list screen,
  /// a detail screen for one specific item) can subscribe independently.
  Stream<SyncItemEvent<T, Id>> get onItemResult => _itemEventController.stream;

  Future<SyncPassResult> run() async {
    final items = await store.getPending();

    var successCount = 0;
    var failureCount = 0;
    var stoppedEarly = false;
    final failures = <SyncItemFailure>[];

    for (final item in items) {
      final id = store.idOf(item);
      final outcome = await _attempt(item, id);

      switch (outcome.kind) {
        case SyncOutcomeKind.success:
          successCount++;
          break;

        case SyncOutcomeKind.transientFailure:
          failures.add(SyncItemFailure(
            itemId: id.toString(),
            reason: outcome.reason ?? 'transient failure',
          ));
          if (stopOnTransientFailure) {
            stoppedEarly = true;
          }
          break;

        case SyncOutcomeKind.permanentFailure:
          failureCount++;
          failures.add(SyncItemFailure(
            itemId: id.toString(),
            reason: outcome.reason ?? 'permanent failure',
          ));
          break;
      }

      if (stoppedEarly) break;
    }

    return SyncPassResult(
      successCount: successCount,
      failureCount: failureCount,
      stoppedEarly: stoppedEarly,
      failures: failures,
    );
  }

  /// Re-attempts exactly one item by id — including one that a previous
  /// `run()` already marked failed, which `getPending()` deliberately
  /// excludes from the normal loop. This is the same shape as the
  /// original app's per-item "retry this one" entry point
  /// (`syncFailedActivityForm`), now generic instead of hand-written per
  /// domain.
  ///
  /// Returns `null` if no item with this [id] exists anymore (e.g. it was
  /// deleted). Unlike `run()`, this never consults
  /// [stopOnTransientFailure] and never touches any other item in the
  /// queue — it's a standalone, single-item operation.
  Future<SyncOutcome?> retryOne(Id id) async {
    final item = await store.getById(id);
    if (item == null) return null;
    return _attempt(item, id);
  }

  /// Shared by [run] and [retryOne]: push one item, apply the resulting
  /// store update (remove on success, markFailed on permanent failure,
  /// leave untouched on transient failure), and emit the item event.
  /// This is the one place that logic lives, so `run()` and `retryOne()`
  /// can never drift out of sync with each other.
  Future<SyncOutcome> _attempt(T item, Id id) async {
    SyncOutcome outcome;
    try {
      outcome = await pushOne(item);
    } catch (e) {
      outcome = SyncOutcome.permanentFailure(e.toString());
    }

    switch (outcome.kind) {
      case SyncOutcomeKind.success:
        await store.remove(id);
        break;
      case SyncOutcomeKind.transientFailure:
        break; // left pending as-is; caller decides what stopping means
      case SyncOutcomeKind.permanentFailure:
        await store.markFailed(id, errorMessage: outcome.reason);
        break;
    }

    _itemEventController.add(
      SyncItemEvent(id: id, item: item, outcome: outcome),
    );
    return outcome;
  }

  /// Closes the internal stream controller. Call this when whatever owns
  /// this pass is torn down, same as `SyncOrchestrator.dispose()`.
  void dispose() {
    _itemEventController.close();
  }
}
