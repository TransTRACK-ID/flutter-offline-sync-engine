import 'sync_orchestrator.dart';
import 'cache/cache_state.dart';
import 'cache/pull_cache_repository.dart';
import 'outbound/outbound_repository.dart';
import 'sync_outcome.dart';

/// Top-level wiring helper for apps with multiple offline domains.
class OfflineSyncKit {
  OfflineSyncKit({required Future<bool> Function() isOnline})
      : orchestrator = SyncOrchestrator(isOnline: isOnline);

  final SyncOrchestrator orchestrator;

  final _pullCaches = <String, PullCacheRepository<dynamic, dynamic>>{};
  final _outbound = <String, OutboundRepository<dynamic, dynamic>>{};

  void registerPullCache<T, Id>(String name, PullCacheRepository<T, Id> repo) {
    _pullCaches[name] = repo;
  }

  void registerOutbound<T, Id>(
    String name,
    OutboundRepository<T, Id> repo,
  ) {
    _outbound[name] = repo;
  }

  Future<Map<String, CacheLoadResult<dynamic>>> loadAllForUi({
    bool refreshIfOnline = true,
  }) async {
    final results = <String, CacheLoadResult<dynamic>>{};
    for (final entry in _pullCaches.entries) {
      results[entry.key] = await entry.value.load(
        refreshIfOnline: refreshIfOnline,
      );
    }
    return results;
  }

  Future<void> refreshAllPullCaches() async {
    for (final repo in _pullCaches.values) {
      await repo.refresh();
    }
  }

  Future<Map<String, SyncPassResult>> syncAllOutbound() {
    return orchestrator.syncAll({
      for (final entry in _outbound.entries)
        entry.key: entry.value.syncPass,
    });
  }

  void invalidateAllSessions() {
    for (final repo in _pullCaches.values) {
      repo.invalidateSession();
    }
  }

  void dispose() {
    orchestrator.dispose();
    for (final repo in _pullCaches.values) {
      repo.dispose();
    }
    for (final repo in _outbound.values) {
      repo.dispose();
    }
  }
}
