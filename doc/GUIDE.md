# Implementation Guide

How to wire the kit into an app — either a fresh feature or replacing an
existing hand-rolled sync loop. If you're starting from nothing, the
[fresh project walkthrough](FRESH_PROJECT_WALKTHROUGH.md) is a gentler
entry point; if you're migrating an existing hand-rolled sync
implementation onto this kit, see also
[MIGRATING_AN_EXISTING_APP.md](MIGRATING_AN_EXISTING_APP.md).

Code below uses `OfflineTaskActivity`/`TaskRepository`/`CheckInOutAction`
as a worked example (the domain this kit was originally extracted
from) — swap in your own model/repository names.

---

## 0. Mental model

Every offline-sync domain (check-in/out, task activities, expense
reports, ...) is the same shape:

```
local queue  →  try to push each item to the server  →  success: remove
                                                       →  transient fail: stop, keep pending
                                                       →  permanent fail: mark failed
```

The kit gives you that loop once (`SyncPass`) and a way to run several of
them together with a single-flight guard (`SyncOrchestrator`). **You**
supply, per domain:

1. an `OfflineQueueStore` — how to read/remove/mark-failed for *your*
   storage (Hive box, sqflite table, whatever)
2. a `pushOne` function — how to call *your* API and classify the result

Nothing else changes per domain. If you add another offline feature next
year, you write those two things again — you don't touch the engine.

---

## 1. Install

Not on pub.dev yet — for now, add it as a path or git dependency (see the
main [README](../README.md)). Run `flutter pub get`.

---

## 2. Implement the storage adapter for one domain

Take your existing local-storage code (a Hive box, a sqflite table — you
likely already have this) and wrap it so it satisfies
`OfflineQueueStore<T, Id>`:

```dart
class TaskActivityQueueStore
    implements OfflineQueueStore<OfflineTaskActivity, int> {
  TaskActivityQueueStore(this._db);
  final TaskDatabaseService _db;

  @override
  Future<List<OfflineTaskActivity>> getPending() =>
      _db.getPendingActivities();

  @override
  Future<void> remove(int id) => _db.deleteActivity(id);

  @override
  Future<OfflineTaskActivity?> getById(int id) => _db.getActivityById(id);

  @override
  Future<void> markFailed(int id, {String? errorMessage}) =>
      _db.markActivityAsFailed(id, errorMessage: errorMessage);

  @override
  int idOf(OfflineTaskActivity item) => item.id!;
}
```

**Checklist for this step:**
- [ ] `getPending()` returns items in the order you want them sent (if
  your storage doesn't preserve insertion order — Hive boxes don't
  guarantee this — sort here, not in the engine).
- [ ] `remove()` is only called after a confirmed success; make sure it
  can't silently no-op in a way that hides a bug if the id is already
  gone (a clean no-op is fine — Hive's `delete` is one — just be aware
  of it).
- [ ] `markFailed()` should be additive (set a status/error field), not
  destructive — the user needs to still see failed items to retry/delete.
- [ ] `getById()` must find an item **regardless of status** — including
  ones `getPending()` excludes because they're already marked failed.
  Usually a direct key lookup on the same underlying storage — needed for
  `SyncPass.retryOne` (see below).

Repeat this once per domain. Each one is ~15–20 lines; if yours is
bigger, it's probably doing domain policy that belongs in step 3 instead.

---

## 3. Implement the classifier (`pushOne`)

This is the try/catch block that talks to your real API and returns a
`SyncOutcome`:

```dart
Future<SyncOutcome> pushTaskActivity(
  OfflineTaskActivity activity,
  TaskRepository taskRepo,
) async {
  try {
    final response = activity.activityType == TaskStatus.doing
        ? await taskRepo.syncStartTaskActivity(activity)
        : await taskRepo.syncDoneTaskActivity(activity);

    if (response.status == ResponseStatus.success) {
      return const SyncOutcome.success();
    }
    return response.isNetworkError
        ? SyncOutcome.transientFailure(response.message)
        : SyncOutcome.permanentFailure(response.message);

  } on DioException catch (e) {
    final isTransient = e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.error is SocketException;

    return isTransient
        ? SyncOutcome.transientFailure(e.message)
        : SyncOutcome.permanentFailure(e.message ?? 'Network error');
  }
}
```

**Rule of thumb for transient vs. permanent:** ask "did the request reach
the server?" If the failure happened before/during the network call
(timeout, DNS, connection refused, socket error) → transient. If the
server responded, even with an error status → permanent (with the
judgment call that a bare `500` right after an offline→online transition
is often treated as transient too — see the note on
`SyncOutcomeKind.transientFailure` in `sync_outcome.dart`). Getting this
wrong in either direction is the single most impactful bug class in this
kind of system: either you mark real failures as "still pending
forever," or you give up on retryable network blips too early.

**Domain policy goes here too, as a wrapper, not in the engine.** For
example, a "not found on server → treat as already done" rule:

```dart
Future<SyncOutcome> pushTaskActivityWithPolicy(
  OfflineTaskActivity activity,
  TaskRepository taskRepo,
  TaskActivityQueueStore store,
) async {
  final outcome = await pushTaskActivity(activity, taskRepo);
  if (outcome.kind == SyncOutcomeKind.permanentFailure &&
      outcome.reason?.contains('not found') == true) {
    await store.remove(store.idOf(activity)); // policy: treat as done
    return const SyncOutcome.success();
  }
  return outcome;
}
```

---

## 4. Wire up `SyncPass` and `SyncOrchestrator`

```dart
final orchestrator = SyncOrchestrator(
  isOnline: hasInternetConnection, // see the note in step 6 below
);

Future<Map<String, SyncPassResult>> syncEverything() {
  final checkInOutPass = SyncPass<CheckInOutAction, String>(
    store: CheckInOutQueueStore(hiveService),
    pushOne: (item) => pushCheckInOut(item, checkInRepo),
  );

  final taskActivityPass = SyncPass<OfflineTaskActivity, int>(
    store: TaskActivityQueueStore(taskDb),
    pushOne: (item) =>
        pushTaskActivityWithPolicy(item, taskRepo, TaskActivityQueueStore(taskDb)),
  );

  return orchestrator.syncAll({
    'checkInOut': checkInOutPass,
    'taskActivities': taskActivityPass,
  });
}
```

`orchestrator.syncAll(...)` is your single "sync everything" entry point.
Call it from wherever you currently trigger sync: app start, a periodic
timer, a connectivity callback. The single-flight behavior is automatic —
calling `syncEverything()` again while one is running returns the same
in-flight future instead of starting a second, overlapping run.

---

## 5. Turn results into UI feedback

The kit deliberately returns plain data (`Map<String, SyncPassResult>`),
no Flutter, no copy. Build your flash message/snackbar from that in the
presentation layer, not inside the sync code:

```dart
final results = await syncEverything();
final totalSuccess = results.values.fold(0, (a, r) => a + r.successCount);
final totalFailed  = results.values.fold(0, (a, r) => a + r.failureCount);

if (totalSuccess > 0 || totalFailed > 0) {
  showFlash(buildSyncMessage(totalSuccess, totalFailed)); // your existing copy/logic
}
```

Keeping presentation out of the sync layer is what makes the kit portable
to another project later — worth holding the line on even under time
pressure.

### Showing a "syncing..." indicator

`SyncOrchestrator` also exposes sync-in-progress state directly, so you
don't need a local `bool _syncing` field wrapped around every call:

```dart
// Synchronous — correct immediately, e.g. for a widget's initial state.
orchestrator.isSyncing; // bool

// Reactive — emits true right before a run starts, false right after it
// finishes. Broadcast, so multiple widgets can listen independently.
orchestrator.syncStateChanges; // Stream<bool>
```

In Flutter, wire it to a `StreamBuilder` with `initialData: isSyncing` so
there's no flash of the wrong state before the first stream event:

```dart
StreamBuilder<bool>(
  stream: orchestrator.syncStateChanges,
  initialData: orchestrator.isSyncing,
  builder: (context, snapshot) {
    final syncing = snapshot.data ?? false;
    return syncing ? const CircularProgressIndicator() : const Icon(Icons.sync);
  },
)
```

A second overlapping `syncAll()` call reuses the existing run (per the
single-flight guarantee) and does **not** emit a duplicate `true` — the
indicator won't flicker if the user taps sync twice.

Call `orchestrator.dispose()` when whatever owns it is torn down, same as
any other `StreamController`-backed API.

### Retrying one specific item

Sometimes a full `syncAll()` isn't what you want — e.g. a "retry" button
on a specific failed item in a list, where re-running the whole queue
would be overkill (and would re-trigger other unrelated pending items).
`SyncPass.retryOne(id)` handles exactly that:

```dart
final outcome = await taskActivityPass.retryOne(activityId);
if (outcome == null) {
  // no item with this id exists anymore (e.g. already deleted)
} else {
  // outcome.kind is success / transientFailure / permanentFailure,
  // same as any other SyncOutcome — the store update (remove /
  // markFailed / left as-is) already happened by the time this returns
}
```

This requires `OfflineQueueStore.getById(id)` to actually be able to find
the item — including one that's already been marked failed, which
`getPending()` deliberately excludes. If your adapter's backing storage
supports a direct key lookup (a Hive `box.get(id)`, a sqflite `WHERE id =
?`), this is usually a one-liner, same as `getById` in the storage
adapter example in step 2 above.

`retryOne` never consults `stopOnTransientFailure` and never touches any
other item — it's a standalone, single-item operation, same shape as the
original app's dedicated per-item retry entry point
(`syncFailedActivityForm`).

### Reacting to individual items, not just the aggregate

`SyncPass.onItemResult` is a `Stream<SyncItemEvent<T, Id>>` that fires
once per item — from both `run()`'s loop and `retryOne()` — carrying the
item, its id, and its `SyncOutcome`. Useful when a specific open screen
(e.g. a task detail view) needs to know "did *my* item just sync?"
without parsing the aggregate `SyncPassResult`:

```dart
final sub = taskActivityPass.onItemResult.listen((event) {
  if (event.id == currentlyOpenTaskId) {
    // refresh this screen now that its item resolved one way or another
  }
});
// ... later
sub.cancel();
```

Broadcast, so multiple listeners can subscribe independently — a list
screen and a detail screen can both listen to the same `SyncPass` without
competing for one subscription. Call `pass.dispose()` when the pass
itself is no longer needed.

---

## 6. The `isOnline` function — don't skip this

`SyncOrchestrator` takes `isOnline` as a plain injected function. A basic
OS-level connectivity check (`connectivity_plus`, etc.) works, but
remember it will report "online" even when a VPN-gated or otherwise
gated API host is still unreachable. That's exactly why `SyncPass`'s
transient-failure handling exists: it's the safety net for this gap, not
a redundant precaution. If you later upgrade to a real reachability
probe, it's a one-line change at the call site — nothing else needs to
know.

---

## 7. Testing

Because `OfflineQueueStore` and `pushOne` are just interfaces/functions,
you can test `SyncPass`/`SyncOrchestrator` with fakes and no Hive/sqflite/
Flutter test harness at all — write your own:

```dart
class FakeStore implements OfflineQueueStore<String, int> {
  final items = <int, String>{1: 'a', 2: 'b'};
  @override Future<List<String>> getPending() async => items.values.toList();
  @override Future<String?> getById(int id) async => items[id];
  @override Future<void> remove(int id) async => items.remove(id);
  @override Future<void> markFailed(int id, {String? errorMessage}) async {}
  @override int idOf(String item) => items.entries.firstWhere((e) => e.value == item).key;
}

test('stops on transient failure and leaves item pending', () async {
  final store = FakeStore();
  final pass = SyncPass<String, int>(
    store: store,
    pushOne: (_) async => const SyncOutcome.transientFailure('timeout'),
  );
  final result = await pass.run();
  expect(result.stoppedEarly, isTrue);
  expect(store.items.length, 2); // nothing removed
});
```

Write one test per transient/permanent/success branch, per domain
classifier. This coverage is what tells you immediately if a later
refactor of your storage layer changes sync behavior.
