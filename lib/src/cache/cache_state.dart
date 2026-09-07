/// Where the data in a [CacheLoadResult] came from.
enum CacheDataSource {
  /// Only local storage was read (offline, or refresh skipped).
  localOnly,

  /// Local data was returned first, then a background refresh succeeded.
  refreshed,

  /// Local data was returned, but a refresh was attempted and failed.
  refreshFailed,
}

/// Result of [PullCacheRepository.load] — always includes whatever is in
/// local storage, plus metadata about whether a refresh ran.
class CacheLoadResult<T> {
  const CacheLoadResult({
    required this.items,
    required this.source,
    this.refreshError,
  });

  final List<T> items;
  final CacheDataSource source;
  final Object? refreshError;

  bool get hasLocalData => items.isNotEmpty;
}

/// Optional metadata apps can surface in UI (stale banner, offline chip, …).
class CacheSnapshot<T> {
  const CacheSnapshot({
    required this.items,
    required this.lastUpdatedAt,
    required this.isRefreshing,
  });

  final List<T> items;
  final DateTime? lastUpdatedAt;
  final bool isRefreshing;
}
