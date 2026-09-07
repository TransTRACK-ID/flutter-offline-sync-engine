library offline_sync_engine;

// --- Outbound sync (push queue) ---
export 'src/offline_queue.dart';
export 'src/sync_outcome.dart';
export 'src/sync_pass.dart';
export 'src/sync_orchestrator.dart';

// --- Inbound sync primitives (low-level) ---
export 'src/generation_guard.dart';
export 'src/keyed_single_flight.dart';
export 'src/mutation_queue.dart';

// --- Full extension: local-first reads + repositories ---
export 'src/cache/cache_state.dart';
export 'src/cache/local_data_store.dart';
export 'src/cache/pull_cache_repository.dart';
export 'src/outbound/outbound_repository.dart';
export 'src/offline_sync_kit.dart';

// --- Storage backends ---
export 'src/storage/memory_local_data_store.dart';
export 'src/storage/hive/hive_stores.dart';
export 'src/storage/drift/drift_stores.dart';

// --- Codegen (import in apps or run via executable) ---
export 'src/codegen/domain_generator.dart';
