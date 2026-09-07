# offline_sync_engine

Full offline-first toolkit for Flutter/Dart apps: **local-first repositories**
(so screens work offline), push queues, pull caches, Hive/Drift storage
adapters, multi-domain orchestration, and domain codegen.

Pure Dart core — no Flutter import required for the engine itself.

## Status

Working and unit-tested. v0.3 adds the full extension (read/cache layer +
codegen). v0.2 sync primitives remain available unchanged.

## Install

Not published to pub.dev. Depend on GitHub or a local path:

```yaml
dependencies:
  offline_sync_engine:
    git:
      url: https://github.com/abidzakly/offline_sync_engine.git
      ref: main
  hive: ^2.2.3              # Hive backend
  hive_flutter: ^1.1.0      # Flutter + Hive
  drift: ^2.22.1            # Drift backend (in your app)
```

## Quick start — screens that work offline

```dart
final repo = PullCacheRepository<Report, String>(
  store: HiveLocalDataStore(
    box: Hive.box<Report>('reports'),
    idOf: (r) => r.id,
  ),
  fetchAll: () => api.fetchReports(),
  isOnline: connectivity.hasInternet,
);

// Screen open — cached data immediately, refresh if online
await repo.load(refreshIfOnline: true);

// UI
StreamBuilder<CacheSnapshot<Report>>(
  stream: repo.watchSnapshot(),
  builder: (_, snap) => ListView(...),
);
```

**Add another domain without copy-paste:**

```bash
dart run offline_sync_engine:generate_domain --config offline_domain.yaml
```

## What's in the kit

### Full extension (v0.3+)
- `PullCacheRepository` — local-first reads, `watchSnapshot()`, guarded refresh
- `OutboundRepository` — save locally, `watchAll()`, integrated `SyncPass`
- `OfflineSyncKit` — register many domains; `loadAllForUi()`, `syncAllOutbound()`
- `LocalDataStore` — read/write abstraction for UI + cache
- `HiveLocalDataStore` / `HiveOutboundQueueStore` — Hive backend
- `DriftLocalDataStore` / `DriftOutboundQueueStore` + adapter interfaces — Drift backend
- `MemoryLocalDataStore` — tests and prototypes
- `generate_domain` — CLI codegen for new domains

### Sync engine (v0.2, unchanged)
- `OfflineQueueStore`, `SyncPass`, `SyncOrchestrator`, `SyncOutcome`
- `GenerationGuard`, `KeyedSingleFlight`, `MutationQueue`

## Docs

| Doc | Contents |
|-----|----------|
| **[doc/FULL_EXTENSION_GUIDE.md](doc/FULL_EXTENSION_GUIDE.md)** | **Start here** — repositories, backends, UI wiring, OfflineSyncKit |
| [doc/CODEGEN_GUIDE.md](doc/CODEGEN_GUIDE.md) | `generate_domain` CLI and YAML config |
| [doc/GUIDE.md](doc/GUIDE.md) | Outbound push-queue sync (classifiers, testing) |
| [doc/INBOUND_GUIDE.md](doc/INBOUND_GUIDE.md) | Low-level inbound primitives (used inside PullCacheRepository) |
| [doc/FRESH_PROJECT_WALKTHROUGH.md](doc/FRESH_PROJECT_WALKTHROUGH.md) | Brand-new app walkthrough |
| [doc/MIGRATING_AN_EXISTING_APP.md](doc/MIGRATING_AN_EXISTING_APP.md) | Incremental migration |

## Testing

```bash
dart pub get
dart test
```

## Example codegen config

See [example/list_transaction/offline_domain.yaml](example/list_transaction/offline_domain.yaml).
