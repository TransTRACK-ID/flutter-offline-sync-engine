# Full extension guide — offline screens that just work

This guide covers the **v0.3+ full extension**: local-first repositories,
storage backends (Hive, Drift, in-memory), and multi-domain wiring via
[OfflineSyncKit](README.md). For the original push-queue-only docs, see
[GUIDE.md](GUIDE.md) and [INBOUND_GUIDE.md](INBOUND_GUIDE.md).

---

## 0. Mental model (read this first)

Every offline screen follows the same pattern:

```
UI  →  Repository.watch* / load  →  Local storage (Hive / Drift / memory)
                ↓ when online
         Sync engine (pull refresh or outbound push)
```

**Screens never call the API directly.** They read from local storage through
a repository. Sync runs in the background and updates storage; the repository
notifies the UI via streams.

| Direction | Use case | Main class |
|-----------|----------|------------|
| **Pull** | Server lists/details (reports, transactions) | `PullCacheRepository` |
| **Outbound** | User creates data offline (forms, check-ins) | `OutboundRepository` |
| **Both** | Rare — same entity cached *and* queued | Generate with `sync: both` |

Register all domains in one [`OfflineSyncKit`](#5-offlinesynckit-multi-domain-apps) for app-wide
`loadAllForUi()`, `refreshAllPullCaches()`, and `syncAllOutbound()`.

---

## 1. Install

```yaml
dependencies:
  offline_sync_engine:
    git:
      url: https://github.com/abidzakly/offline_sync_engine.git
      ref: main
  hive: ^2.2.3          # if using Hive backend
  hive_flutter: ^1.1.0  # Flutter apps
  drift: ^2.22.1        # if using Drift backend (in your app, not required by the engine)
```

Run `flutter pub get`.

---

## 2. Fastest path — generate a new domain

You already have **list report** wired manually. To add **list transaction**
without copy-paste:

### 2a. Create a config file

Copy [example/list_transaction/offline_domain.yaml](../example/list_transaction/offline_domain.yaml)
and adjust names:

```yaml
domain: list_transaction
entity: ListTransaction
id_type: String
storage: hive          # hive | drift | memory
sync: pull             # pull | outbound | both
hive_box: list_transactions
sort_field: createdAt
output_dir: lib/offline/list_transaction
```

### 2b. Run the generator

From your **app** root (not the engine repo):

```bash
dart run offline_sync_engine:generate_domain --config offline_domain.yaml
```

Or with flags:

```bash
dart run offline_sync_engine:generate_domain \
  --domain list_transaction \
  --entity ListTransaction \
  --storage hive \
  --sync pull \
  --output-dir lib/offline/list_transaction \
  --hive-box list_transactions \
  --sort-field createdAt
```

See [CODEGEN_GUIDE.md](CODEGEN_GUIDE.md) for all options.

### 2c. Wire API + register

```dart
final listTransactionRepo = ListTransactionRepository.pull(
  box: Hive.box<ListTransaction>('list_transactions'),
  fetchAll: () => api.fetchTransactions(),
  isOnline: connectivity.hasInternet,
);

kit.registerPullCache('listTransaction', listTransactionRepo.pull);
```

Only **fetchAll / pushOne / isOnline** need your app-specific code — everything
else is generated.

---

## 3. Pull-cache (server data, offline viewing)

### 3a. Hive

```dart
final store = HiveLocalDataStore<Report, String>(
  box: Hive.box<Report>('reports'),
  idOf: (r) => r.id,
  sort: (a, b) => b.date.compareTo(a.date),
);

final repo = PullCacheRepository<Report, String>(
  store: store,
  fetchAll: () => api.fetchReports(),
  isOnline: connectivity.hasInternet,
);
```

### 3b. Drift

Implement [`DriftCacheAdapter`](https://github.com/abidzakly/offline_sync_engine/blob/main/lib/src/storage/drift/drift_stores.dart)
against your generated DAO (codegen scaffolds a stub):

```dart
final adapter = ReportDriftCacheAdapter(db);
final store = DriftLocalDataStore(adapter);

final repo = PullCacheRepository<Report, String>(
  store: store,
  fetchAll: () => api.fetchReports(),
  isOnline: connectivity.hasInternet,
);
```

### 3c. Screen wiring (Flutter)

```dart
class ReportListScreen extends StatelessWidget {
  const ReportListScreen({required this.repo});
  final PullCacheRepository<Report, String> repo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CacheSnapshot<Report>>(
      stream: repo.watchSnapshot(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final reports = data?.items ?? [];
        final refreshing = data?.isRefreshing ?? false;

        return Column(
          children: [
            if (refreshing) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: reports.length,
                itemBuilder: (_, i) => Text(reports[i].title),
              ),
            ),
          ],
        );
      },
    );
  }
}
```

On screen open:

```dart
await repo.load(refreshIfOnline: true);
```

- **Offline:** `load()` returns cached rows (`CacheDataSource.localOnly`).
- **Online:** refreshes from API, updates Hive/Drift, UI stream rebuilds.

Pull-to-refresh: `await repo.refresh()`.

Logout: `repo.invalidateSession()` (or `kit.invalidateAllSessions()`).

---

## 4. Outbound (user creates data offline)

```dart
final readStore = HiveLocalDataStore<Expense, String>(
  box: box,
  idOf: (e) => e.localId,
);

final queueStore = HiveOutboundQueueStore<Expense, String>(
  box: box,
  idOf: (e) => e.localId,
  statusOf: (e) => e.syncStatus,
  withStatus: (e, status, {errorMessage}) => e.copyWith(
    syncStatus: status,
    errorMessage: errorMessage,
  ),
);

final repo = OutboundRepository<Expense, String>(
  readStore: readStore,
  queueStore: queueStore,
  pushOne: (item) => pushExpense(item, api),
  isOnline: connectivity.hasInternet,
  statusOf: (e) => e.syncStatus,
  withStatus: (e, status, {errorMessage}) => e.copyWith(
    syncStatus: status,
    errorMessage: errorMessage,
  ),
);
```

Save + show in list:

```dart
await repo.save(newExpense);

// UI
StreamBuilder<List<Expense>>(
  stream: repo.watchAll(),
  builder: (_, snap) => ListView(...),
);
```

Register for app-wide sync:

```dart
kit.registerOutbound('expenses', repo);
// later
await kit.syncAllOutbound();
```

See [GUIDE.md](GUIDE.md) for transient vs permanent classification in `pushOne`.

---

## 5. OfflineSyncKit (multi-domain apps)

```dart
final kit = OfflineSyncKit(isOnline: connectivity.hasInternet);

kit.registerPullCache('reports', reportRepo);
kit.registerPullCache('transactions', transactionRepo);
kit.registerOutbound('expenses', expenseRepo);

// App startup — every list screen gets local data immediately
await kit.loadAllForUi(refreshIfOnline: true);

// Connectivity regained
await kit.refreshAllPullCaches();
await kit.syncAllOutbound();

// Logout
kit.invalidateAllSessions();
```

Sync indicator: use `kit.orchestrator.syncStateChanges` (same as before).

---

## 6. Storage backend cheat sheet

| Backend | Pull-cache store | Outbound queue store | When to use |
|---------|------------------|----------------------|-------------|
| **Hive** | `HiveLocalDataStore` | `HiveOutboundQueueStore` | Simple models, quick setup |
| **Drift** | `DriftLocalDataStore` + your `DriftCacheAdapter` | `DriftOutboundQueueStore` + `DriftOutboundAdapter` | SQL, relations, migrations |
| **Memory** | `MemoryLocalDataStore` | custom / generated bundle | Unit tests, prototypes |

Drift adapters stay in **your app** (they reference generated tables). The
engine provides interfaces + thin wrappers only.

---

## 7. What you still own (by design)

- Domain models + Hive type adapters / Drift tables
- API client (`fetchAll`, `pushOne`)
- Connectivity probe passed as `isOnline`
- UI copy, snackbars, routing
- Domain-specific reconcile logic (paginated detail sync) — use
  `PullCacheRepository.reconcile(id, fetchForId)`

The engine owns: sync loops, staleness guards, single-flight, local-first
load/watch APIs, and codegen scaffolding.

---

## 8. Testing

```bash
dart test
```

Use `MemoryLocalDataStore` in repository tests — no Hive/Drift harness needed.
See `test/pull_cache_repository_test.dart` and `test/outbound_repository_test.dart`.

---

## 9. Migration from v0.2 (sync-only)

1. Wrap existing Hive/sqflite read code in `HiveLocalDataStore` or a
   `DriftCacheAdapter`.
2. Replace hand-rolled refresh loops with `PullCacheRepository`.
3. Point list screens at `watchSnapshot()` instead of API futures.
4. Optionally run codegen for **new** domains; migrate existing ones
   incrementally (see [MIGRATING_AN_EXISTING_APP.md](MIGRATING_AN_EXISTING_APP.md)).

Your existing `SyncPass` / `SyncOrchestrator` code keeps working — the full
extension adds repositories on top, it does not replace the low-level API.
