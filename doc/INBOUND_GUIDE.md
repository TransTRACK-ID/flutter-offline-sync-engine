# Inbound (pull-cache) sync guide

The [main guide](GUIDE.md) covers **outbound** sync: local writes that need
to reach the server. This guide covers the opposite direction —
**inbound** sync, a.k.a. a pull-cache: server data mirrored into local
storage (SQLite, Hive, ...) for offline viewing, kept up to date by
fetching from the server and reconciling.

If your domain is "user creates something offline, it needs to reach the
server eventually," you want [GUIDE.md](GUIDE.md), not this doc. If your
domain is "show the user server data, and keep working from the local
mirror when there's no connection," you're in the right place.

---

## 0. Why this isn't just `SyncPass` again

`SyncPass` works because every outbound push is the exact same three-branch
loop (success / transient failure / permanent failure), no matter the
domain — so it's written once, in the engine.

Inbound doesn't have that luxury. "Refresh a whole list and replace the
local snapshot" and "fetch page 2 of one record's readings and merge them
in" are legitimately different shapes, and the reconciliation policy in
between (what counts as "in sync," how to detect a gap, whether a
duplicate needs pruning) is real domain logic that has to stay in your
repository — same as the outbound kit keeps the transient/permanent
classifier out of the engine.

What *is* shared across every pull-cache domain is the concurrency and
staleness bookkeeping around those fetches — and that bookkeeping is
exactly what used to get hand-rolled per repository (an `_inFlight` map
here, a pair of generation counters there, a `Future` chain for
serializing writes). This kit extracts **that** into three small,
independent, pure-Dart primitives. Compose them directly in your
repository; there's no `InboundSyncPass` wrapping them, because forcing
one would mean re-introducing the same generic loop problem `SyncPass`
avoided by only existing for the one shape that's actually universal.

---

## 1. The three primitives

### `GenerationGuard` — is this result still wanted?

A monotonic counter. Capture a token before starting an async fetch;
check it after the fetch resolves to know whether something newer
superseded it (or invalidated the whole session) while you were waiting.

Use **one instance per staleness axis** you actually have. Most
pull-caches need two:

```dart
final _sessionGuard = GenerationGuard(); // bumped on logout/user-switch
final _fetchGuard = GenerationGuard();   // bumped on every new fetch
```

### `KeyedSingleFlight<K>` — don't run the same pull twice at once

Unlike outbound's fixed, known-upfront set of queues, inbound keys are
usually dynamic — one per remote record id. `KeyedSingleFlight` collapses
concurrent calls for the same key into the one already running:

```dart
final _reconcileGuard = KeyedSingleFlight<String>();

Future<void> reconcileTransaction(String trxNumber) {
  return _reconcileGuard.run(trxNumber, () => _reconcileInternal(trxNumber));
}
```

It also works for a "whole list" operation that only ever has one logical
key — just call `run` with a constant string:

```dart
final _refreshGuard = KeyedSingleFlight<String>();
static const _refreshKey = 'refresh';

Future<void> refresh() {
  return _refreshGuard.run(_refreshKey, _refreshInternal);
}
```

### `MutationQueue` — serialize the actual local writes

Two fetches landing at once (a background refresh, a foreground
reconcile) shouldn't write to local storage in an unpredictable
interleaved order. `MutationQueue` chains writes so each one waits for the
previous to finish, success or failure, without letting one failure jam
the ones queued after it:

```dart
final _writes = MutationQueue();

Future<void> upsertCompleted(Transaction transaction) {
  return _writes.enqueue(() async {
    await _db.upsert(transaction);
    _notifyChanges();
  });
}
```

---

## 2. Putting them together

This is the shape every pull-cache repository ends up with — REST list
sync, plus per-record paginated reconciliation, plus a change-notification
stream for whoever's watching (a Cubit/Bloc, typically):

```dart
class WidgetReportRepository {
  WidgetReportRepository(this._db, this._api);

  final WidgetDatabase _db;
  final ApiClient _api;

  final _sessionGuard = GenerationGuard();
  final _fetchGuard = GenerationGuard();
  final _reconcileGuard = KeyedSingleFlight<String>();
  final _refreshGuard = KeyedSingleFlight<String>();
  final _writes = MutationQueue();
  final _changes = StreamController<void>.broadcast();

  static const _refreshKey = 'refresh';

  Stream<void> watchChanges() => _changes.stream;

  void invalidateSession() {
    _sessionGuard.bump();
    _fetchGuard.bump();
  }

  Future<void> refresh() {
    return _refreshGuard.run(_refreshKey, _refreshInternal);
  }

  Future<void> _refreshInternal() async {
    final sessionToken = _sessionGuard.generation;
    final fetchToken = _fetchGuard.bump();

    final fetched = await _api.fetchWidgetList();

    if (!_sessionGuard.isCurrent(sessionToken)) return;
    if (!_fetchGuard.isCurrent(fetchToken)) return;

    await _writes.enqueue(() async {
      if (!_sessionGuard.isCurrent(sessionToken)) return;
      if (!_fetchGuard.isCurrent(fetchToken)) return;
      await _db.replaceAll(fetched);
      if (!_changes.isClosed) _changes.add(null);
    });
  }

  Future<void> reconcileWidget(String widgetId) {
    return _reconcileGuard.run(
      widgetId,
      () => _reconcileWidgetInternal(widgetId),
    );
  }

  Future<void> _reconcileWidgetInternal(String widgetId) async {
    // Domain-specific: fetch remote detail metadata, compare against local
    // rows, fetch/merge missing pages, update your own sync-state field.
    // This is the part that stays app-specific — see the note above on
    // why there's no generic loop for it.
  }
}
```

Every call site checks the guard tokens **twice**: once right after the
network call returns (cheap early exit before touching storage), and once
again inside the `MutationQueue.enqueue` callback (because by the time
your write actually gets its turn on the chain, something newer might
have landed while it was queued). Both checks matter — skipping the
second one is the most common way this pattern silently regresses.

---

## 3. Testing

Same philosophy as the outbound kit: all three primitives are pure Dart
with no storage/network dependency, so test them directly with
`dart test` — no fakes needed beyond a `Completer` to control timing. See
`test/generation_guard_test.dart`, `test/keyed_single_flight_test.dart`,
and `test/mutation_queue_test.dart` in this package for the pattern.

Your repository's own tests then only need to fake `_api`/`_db` and
assert on the composition — the concurrency mechanics themselves are
already covered here and don't need re-proving per domain.
