/// Tracks a monotonically increasing "generation" so an in-flight pull can
/// tell, once it finally resolves, whether it's still the most recent
/// request for whatever it's guarding (a session, a specific fetch) or
/// whether it's been superseded and its result should be discarded.
///
/// This is the inbound-sync counterpart to [OfflineQueueStore]/[SyncPass]
/// on the outbound side: outbound sync deals with "did this push reach the
/// server," inbound sync deals with "is this pull's result still wanted."
/// Both are mechanics, not policy, so both live in the engine.
///
/// Typical uses, often as two separate instances on the same repository:
/// - a **session** guard, bumped on logout/user-switch, so a REST response
///   that lands after the user logged out doesn't get written into the
///   next user's cache
/// - a **fetch** guard, bumped on every new pull request, so an older,
///   slower request that resolves after a newer one doesn't clobber it
///   with stale data
///
/// ```dart
/// final _sessionGuard = GenerationGuard();
/// final _fetchGuard = GenerationGuard();
///
/// void invalidateSession() {
///   _sessionGuard.bump();
///   _fetchGuard.bump();
/// }
///
/// Future<void> refresh() async {
///   final sessionToken = _sessionGuard.generation;
///   final fetchToken = _fetchGuard.bump();
///
///   final fetched = await _fetchFromApi();
///
///   if (!_sessionGuard.isCurrent(sessionToken)) return; // logged out mid-fetch
///   if (!_fetchGuard.isCurrent(fetchToken)) return; // a newer refresh won
///
///   await _store.replaceAll(fetched);
/// }
/// ```
class GenerationGuard {
  int _generation = 0;

  /// The current generation. Read this *before* starting an async
  /// operation to capture the token that operation should later check
  /// itself against.
  int get generation => _generation;

  /// Advances to a new generation and returns it. Call this either when
  /// something invalidates all prior work (e.g. logout) or when starting a
  /// new request that should supersede any still in flight.
  int bump() => ++_generation;

  /// Whether [token] (captured earlier via [generation] or [bump]) is still
  /// the current generation — i.e. nothing has superseded it since.
  bool isCurrent(int token) => token == _generation;
}
