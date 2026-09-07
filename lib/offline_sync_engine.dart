library offline_sync_engine;

export 'src/offline_queue.dart';
export 'src/sync_outcome.dart';
export 'src/sync_pass.dart';
export 'src/sync_orchestrator.dart';

// Inbound (pull-cache) primitives — see doc/INBOUND_GUIDE.md. Unlike the
// outbound queue above, these are standalone mechanics (no shared "pass"
// loop, since fetch+merge shapes differ per screen/domain) meant to be
// composed directly inside a pull-cache repository.
export 'src/generation_guard.dart';
export 'src/keyed_single_flight.dart';
export 'src/mutation_queue.dart';
