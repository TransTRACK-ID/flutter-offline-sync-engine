# offline_sync_engine

A generic offline-queue sync engine for Flutter/Dart apps: single-flight
orchestration, transient-vs-permanent error classification, and pluggable
storage adapters. Pure Dart, no Flutter dependency — bring your own
storage (Hive, sqflite, ...) and HTTP client.

## Status
Working and unit-tested. Originally
extracted from an internal app's `SyncRepository`; the engine itself has
no dependency on that app or any other, so it can be pulled into any
Flutter/Dart project as a git or path dependency.

## Install
Not published to pub.dev. Depend on it directly from GitHub or a local
path:

```yaml
dependencies:
  offline_sync_engine:
    git:
      url: https://github.com/abidzakly/offline_sync_engine.git
      ref: main
```

## What's in the kit (generic, pure Dart, no Flutter import)
- `OfflineQueueStore<T, Id>` — storage adapter interface (Hive/sqflite/etc.
  implement this; the engine never touches storage directly)
- `SyncOutcome` / `SyncPassResult` / `SyncItemEvent` — domain-agnostic
  result types, no UI copy
- `SyncPass<T, Id>` — the loop itself: pending items → push one → classify
  → success/transient/permanent. Also `retryOne(id)` for re-attempting a
  single item on demand, and `onItemResult` — a live per-item event
  stream, not just the aggregate result at the end
- `SyncOrchestrator` — single-flight guard + running several `SyncPass`es
  together, so overlapping "sync now" triggers collapse into one run
  instead of racing each other. Also `isSyncing`/`syncStateChanges` for
  driving a loading indicator

## What stays app-specific
- Your actual domain models (a check-in event, a form submission, ...)
- The storage adapter implementation per domain (thin — typically a
  ~15-line wrapper around whatever storage you already have; see
  [doc/GUIDE.md](doc/GUIDE.md) for a worked example)
- The `pushOne` classifier per domain (talks to your real API client)
- Any domain policy beyond "transient/permanent" — e.g. "skip the rest of
  this batch once one item fails" or "not found on server → delete the
  offline copy." Those are business rules, not queue mechanics, and
  belong in your classifier/wrapper, not the generic engine.
- All UI/flash-message presentation and copy

## Why split it this way
Keeping the engine domain-agnostic means:
- it's unit-testable with fake stores/`pushOne` functions, no Hive/sqflite/
  Flutter test harness needed
- adding another offline domain is "write an adapter + classifier," not
  "copy-paste a 150-line loop and hope you don't introduce the same bug
  a third time"
- it can be reused across multiple Flutter projects, since nothing in
  `lib/` references any specific app's models

## Docs
- [doc/GUIDE.md](doc/GUIDE.md) — full implementation guide (storage
  adapter, classifier, wiring, testing)
- [doc/FRESH_PROJECT_WALKTHROUGH.md](doc/FRESH_PROJECT_WALKTHROUGH.md) —
  adding offline sync to a brand-new feature, no existing code assumed
- [doc/MIGRATING_AN_EXISTING_APP.md](doc/MIGRATING_AN_EXISTING_APP.md) —
  moving an existing hand-rolled sync repository onto the kit
  incrementally

## Note on transient vs. permanent classification
The engine has no opinion of its own on status codes — that judgment call
belongs entirely to your `pushOne` classifier. The rule of thumb: ask "did
the request reach the server?" Failure before/during the network call
(timeout, DNS, connection refused, socket error) → transient. The server
responded, even with an error status → permanent — with the judgment
call that a bare `500` right after an offline→online transition is often
treated as transient too, since it's frequently a cold-start/overload
symptom rather than a deliberate rejection. See the doc comment on
`SyncOutcomeKind.transientFailure` in `sync_outcome.dart` for the full
reasoning. Either way, the engine just needs to know which bucket the
classifier decided on.

## Testing
```
dart test
```
Tests use an in-memory fake store and don't touch Hive or any real storage.

## What this kit does *not* attempt
- Migrating your existing storage service itself — adapters wrap
  whatever you already have (see `HiveOfflineQueueStore`)
- The "am I online" reachability question — `SyncOrchestrator` just takes
  `isOnline` as an injected function, so that decision is made by the
  caller, not baked into the kit
- Connectivity-change/polling triggers, retry UI, flash messages — those
  are presentation-layer concerns and deliberately out of scope
