/// How a single item's sync attempt ended. The engine only needs to know
/// which bucket it falls in — the *reason* text is free-form and supplied
/// by the caller's classifier so it can stay in whatever language/format
/// the host app's UI expects.
enum SyncOutcomeKind {
  /// Synced successfully; the engine will remove it from the queue.
  success,

  /// Either the request never reached the server (timeout, DNS/VPN not
  /// ready, socket error, ...), or it did reach the server but the
  /// caller's classifier judged the response a likely-transient hiccup
  /// rather than a deliberate rejection (e.g. a bare `500` right after an
  /// offline→online transition). Not a rejection — leave the item pending
  /// and stop this pass; the caller decides how much of the batch to
  /// abort. The engine takes the classifier's word for which bucket a
  /// response falls into — it has no opinion of its own on status codes.
  transientFailure,

  /// The server actually saw and rejected the request. The engine will
  /// call `markFailed` so the item is visible to the user instead of
  /// silently retried forever.
  permanentFailure,
}

class SyncOutcome {
  const SyncOutcome.success() : kind = SyncOutcomeKind.success, reason = null;

  const SyncOutcome.transientFailure(this.reason)
      : kind = SyncOutcomeKind.transientFailure;

  const SyncOutcome.permanentFailure(this.reason)
      : kind = SyncOutcomeKind.permanentFailure;

  final SyncOutcomeKind kind;
  final String? reason;
}

/// Aggregate result of one queue's sync pass. Deliberately has no Flutter
/// dependency and no UI copy — presentation layers build their own
/// messages from these numbers.
class SyncPassResult {
  SyncPassResult({
    required this.successCount,
    required this.failureCount,
    required this.stoppedEarly,
    this.failures = const [],
  });

  final int successCount;
  final int failureCount;

  /// True if a transient failure caused the pass to stop before working
  /// through the rest of the queue.
  final bool stoppedEarly;

  final List<SyncItemFailure> failures;
}

class SyncItemFailure {
  SyncItemFailure({required this.itemId, required this.reason});

  final String itemId;
  final String reason;
}

/// Emitted once per item attempt, from both `SyncPass.run()`'s loop and
/// `SyncPass.retryOne()` — every individual push, not just the aggregate
/// pass-level result. Lets a UI showing one specific item (e.g. a detail
/// screen for that record) react immediately instead of waiting for the
/// whole pass to finish and then figuring out whether *its* item was
/// among the ones that changed.
class SyncItemEvent<T, Id> {
  const SyncItemEvent({
    required this.id,
    required this.item,
    required this.outcome,
  });

  final Id id;
  final T item;
  final SyncOutcome outcome;
}
