# Codegen guide — `generate_domain`

Automates scaffolding when you add a new offline domain (e.g. **list report**
→ **list transaction**) so you do not copy-paste repository boilerplate.

---

## Command

From your Flutter/Dart app (with `offline_sync_engine` as a dependency):

```bash
dart run offline_sync_engine:generate_domain [options]
```

Help:

```bash
dart run offline_sync_engine:generate_domain --help
```

---

## Config file (recommended)

Create `offline_domain.yaml` in your app:

```yaml
domain: list_transaction       # slug — drives file names
entity: ListTransaction        # Dart class name (must exist in your app)
id_type: String                # Id generic on repositories
storage: hive                  # hive | drift | memory
sync: pull                     # pull | outbound | both
hive_box: list_transactions    # Hive box name (hive storage)
drift_table: ListTransactions  # comment hint for Drift adapter (drift storage)
sort_field: createdAt          # optional — local sort comparator
output_dir: lib/offline/list_transaction
package_name: offline_sync_engine   # override if you fork/rename the package
```

Run:

```bash
dart run offline_sync_engine:generate_domain --config offline_domain.yaml
```

Example in this repo: [example/list_transaction/offline_domain.yaml](../example/list_transaction/offline_domain.yaml).

---

## CLI flags

| Flag | Default | Description |
|------|---------|-------------|
| `--config` / `-c` | — | YAML config file |
| `--domain` | required* | Domain slug |
| `--entity` | PascalCase(domain) | Entity class |
| `--id-type` | `String` | Repository id type |
| `--storage` | `hive` | `hive`, `drift`, or `memory` |
| `--sync` | `pull` | `pull`, `outbound`, or `both` |
| `--output-dir` | required* | Where to write files |
| `--hive-box` | domain slug | Hive box name |
| `--drift-table` | `{Entity}s` | Drift table hint |
| `--sort-field` | — | Field for local sort |

\* Required when `--config` is not used.

---

## Generated files

### `sync: pull` + `storage: hive`

```
lib/offline/list_transaction/
  list_transaction_hive_store.dart      # HiveLocalDataStore subclass
  list_transaction_repository.dart      # PullCacheRepository wiring + delegates
```

### `sync: outbound` + `storage: hive`

```
  list_transaction_hive_outbound_store.dart
  list_transaction_repository.dart
```

### `storage: drift`

```
  list_transaction_drift_adapter.dart           # pull — fill in DAO calls
  list_transaction_drift_outbound_adapter.dart  # outbound — fill in DAO calls
  list_transaction_repository.dart
```

### `storage: memory`

```
  list_transaction_memory_store.dart
  list_transaction_repository.dart
```

---

## After generation

1. **Ensure your entity class exists** with an `id` field matching `id_type`.
2. **Open generated Drift adapters** — replace `UnimplementedError` with real
   DAO calls.
3. **Wire API** in the repository constructor call site:

```dart
final repo = ListTransactionRepository.pull(
  box: await Hive.openBox<ListTransaction>('list_transactions'),
  fetchAll: () => api.getTransactions(),
  isOnline: () => connectivity.hasInternet(),
);
```

4. **Register** in `OfflineSyncKit` and use `watchSnapshot()` / `load()` in UI.

---

## Generating list_transaction from list_report

If list_report was built manually:

1. Copy your list_report YAML/config, change `domain`, `entity`, `hive_box`,
   `output_dir`.
2. Run codegen.
3. Copy only the **API wiring** pattern from list_report's constructor call
   (fetch function, connectivity) — not the repository internals.

Repeat for every new list/detail module.

---

## Customization

Generated files are **starting points**. Safe to edit:

- Sort order, extra filters in store subclasses
- `onRefreshed` hooks via direct `PullCacheRepository` use instead of generated wrapper
- Additional methods on `{Domain}Repository`

Re-running codegen **overwrites** generated files — keep custom logic in
separate files or merge carefully.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `item.id` not defined | Add `id` field to entity or edit generated store `idOf` |
| Box type mismatch | Register Hive adapter before `openBox` |
| Drift adapter throws | Implement all adapter methods against your DAO |
| Empty list offline | Call `load()` once while online first, or seed local storage |

See [FULL_EXTENSION_GUIDE.md](FULL_EXTENSION_GUIDE.md) for end-to-end wiring.
