# Walkthrough: adding offline sync to a fresh project

Scenario: a brand-new app with **no** existing offline sync code at all.
We're adding an "Expense Reports" feature — user fills a form, might be
offline, it should queue locally and sync when back online.

This shows every piece from scratch, including the parts a mature app
usually already has (local storage, a connectivity trigger) that a fresh
project won't have yet.

---

## 0. What you need before touching the kit

The kit does NOT provide local storage or a connectivity check — those
are yours to pick.

```yaml
# pubspec.yaml
dependencies:
  offline_sync_engine:
    path: ../offline_sync_engine   # or git: once it's in its own repo
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  connectivity_plus: ^6.0.0
  dio: ^5.4.0
```

(Hive here as an example — sqflite, isar, or plain shared_preferences work
identically; only the store adapter's internals change.)

---

## 1. The domain model

```dart
// lib/models/expense_report.dart
import 'package:hive/hive.dart';

part 'expense_report.g.dart';

@HiveType(typeId: 1)
class ExpenseReport extends HiveObject {
  ExpenseReport({
    required this.localId,
    required this.title,
    required this.amount,
    required this.createdAt,
    this.status = ExpenseSyncStatus.pending,
    this.errorMessage,
  });

  @HiveField(0) final String localId; // e.g. uuid, generated on creation
  @HiveField(1) final String title;
  @HiveField(2) final double amount;
  @HiveField(3) final DateTime createdAt;
  @HiveField(4) ExpenseSyncStatus status;
  @HiveField(5) String? errorMessage;
}

enum ExpenseSyncStatus { pending, failed }
```

## 2. Local storage — a Hive box, nothing kit-specific yet

```dart
// lib/services/expense_local_store.dart
import 'package:hive/hive.dart';
import '../models/expense_report.dart';

class ExpenseLocalStore {
  static const boxName = 'expense_reports';
  Box<ExpenseReport> get _box => Hive.box<ExpenseReport>(boxName);

  Future<void> save(ExpenseReport report) async {
    await _box.put(report.localId, report);
  }

  List<ExpenseReport> allPending() {
    // sort by createdAt — don't trust Hive iteration order
    final items = _box.values
        .where((r) => r.status == ExpenseSyncStatus.pending)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  Future<void> delete(String localId) => _box.delete(localId);

  ExpenseReport? byId(String localId) => _box.get(localId);

  Future<void> markFailed(String localId, String? error) async {
    final report = _box.get(localId);
    if (report == null) return;
    report
      ..status = ExpenseSyncStatus.failed
      ..errorMessage = error;
    await report.save();
  }
}
```

This part — model + local box — is the same amount of work you'd do
*with or without* the kit. The kit only starts here:

## 3. The adapter: 15 lines wrapping the store above

```dart
// lib/services/expense_queue_store.dart
import 'package:offline_sync_engine/offline_sync_engine.dart';
import '../models/expense_report.dart';
import 'expense_local_store.dart';

class ExpenseQueueStore implements OfflineQueueStore<ExpenseReport, String> {
  ExpenseQueueStore(this._local);
  final ExpenseLocalStore _local;

  @override
  Future<List<ExpenseReport>> getPending() async => _local.allPending();

  @override
  Future<void> remove(String id) => _local.delete(id);

  @override
  Future<ExpenseReport?> getById(String id) async => _local.byId(id);

  @override
  Future<void> markFailed(String id, {String? errorMessage}) =>
      _local.markFailed(id, errorMessage);

  @override
  String idOf(ExpenseReport item) => item.localId;
}
```

## 4. The classifier: how to push one, and how to tell success/transient/permanent apart

```dart
// lib/services/expense_sync_classifier.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:offline_sync_engine/offline_sync_engine.dart';
import '../models/expense_report.dart';
import 'expense_api.dart'; // your Dio-based API client

Future<SyncOutcome> pushExpenseReport(
  ExpenseReport report,
  ExpenseApi api,
) async {
  try {
    await api.submitExpenseReport(
      title: report.title,
      amount: report.amount,
      createdAt: report.createdAt,
    );
    return const SyncOutcome.success();
  } on DioException catch (e) {
    final isTransient = e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.error is SocketException;

    if (isTransient) {
      return SyncOutcome.transientFailure(e.message);
    }
    // Server responded — e.g. 422 validation error. It's not going to
    // succeed by itself on retry, so it's permanent.
    return SyncOutcome.permanentFailure(
      e.response?.data?['message']?.toString() ?? 'Request rejected',
    );
  }
}
```

That's the entire domain-specific surface: one model, one local store, one
15-line adapter, one classifier function.

## 5. Wiring — this is where "new module" stops being new work

```dart
// lib/services/sync_service.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:offline_sync_engine/offline_sync_engine.dart';
import 'expense_queue_store.dart';
import 'expense_sync_classifier.dart';

class SyncService {
  SyncService(this._expenseStore, this._api)
      : _orchestrator = SyncOrchestrator(isOnline: _checkOnline);

  final ExpenseQueueStore _expenseStore;
  final ExpenseApi _api;
  final SyncOrchestrator _orchestrator;

  static Future<bool> _checkOnline() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
    // NOTE: this is OS-level connectivity, not real server reachability —
    // it can report "online" while a VPN-gated API host is still
    // unreachable. That's fine to start with; SyncPass's transient-
    // failure handling is the safety net for exactly this gap.
  }

  Future<Map<String, SyncPassResult>> syncAll() {
    final expensePass = SyncPass<ExpenseReport, String>(
      store: _expenseStore,
      pushOne: (item) => pushExpenseReport(item, _api),
    );

    return _orchestrator.syncAll({
      'expenseReports': expensePass,
    });
  }
}
```

Later, when "Leave Requests" needs the same treatment: repeat steps 1–4
for `LeaveRequest`, then add **one line** to the map in step 5:

```dart
    return _orchestrator.syncAll({
      'expenseReports': expensePass,
      'leaveRequests': leaveRequestPass,   // <- the only change to this file
    });
```

`SyncOrchestrator` already handles both under the same single-flight
guard, with no changes to `SyncPass` or the orchestrator itself. That's
the "dynamic" part: adding a module is additive (new store + new
classifier + one map entry), never a modification to shared engine code.

## 6. Triggering it (connectivity + save-time)

```dart
// lib/main.dart or a top-level bloc/provider
final syncService = SyncService(ExpenseQueueStore(ExpenseLocalStore()), ExpenseApi());

// a) on connectivity regained
Connectivity().onConnectivityChanged.listen((result) {
  if (!result.contains(ConnectivityResult.none)) {
    syncService.syncAll();
  }
});

// b) right after the user saves an expense offline, try immediately
Future<void> saveExpense(ExpenseReport report) async {
  await ExpenseLocalStore().save(report);
  unawaited(syncService.syncAll()); // no-op / queues if still offline
}

// c) optionally, a periodic timer as a fallback (useful because
// connectivity_plus's stream isn't fully reliable on all devices)
Timer.periodic(const Duration(minutes: 2), (_) => syncService.syncAll());
```

## 7. Showing the result to the user

```dart
final results = await syncService.syncAll();
final failed = results.values.fold(0, (a, r) => a + r.failureCount);
final synced = results.values.fold(0, (a, r) => a + r.successCount);

if (failed > 0) {
  showSnackBar('$synced synced, $failed failed — check Expense Reports');
} else if (synced > 0) {
  showSnackBar('All expense reports synced');
}
```

---

## Cost of adding a module, with vs. without the kit

| | Without the kit | With the kit |
|---|---|---|
| Local storage | write it | write it (same either way) |
| Sync loop (pending → push → classify → success/fail) | ~150 lines, hand-written, usually copy-pasted from the last domain | 0 lines — reused `SyncPass` |
| Single-flight guard across domains | hand-written per app | 0 lines — reused `SyncOrchestrator` |
| New domain wiring | copy an existing ~150-line method and edit it (a classic source of copy-paste bugs, e.g. double-counting a failure) | ~15-line store adapter + classifier function + one map entry |

The local storage and API-calling code is irreducible — every domain has
its own model and its own endpoint. What the kit removes is re-deriving
and re-testing the *loop and error-classification shape* every time a new
module needs offline support.
