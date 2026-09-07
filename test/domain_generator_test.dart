import 'package:offline_sync_engine/offline_sync_engine.dart';
import 'package:test/test.dart';

void main() {
  test('generates hive pull-cache scaffold', () {
    const config = DomainGeneratorConfig(
      domain: 'list_transaction',
      entity: 'ListTransaction',
      idType: 'String',
      storage: DomainStorage.hive,
      sync: DomainSync.pull,
      outputDir: 'lib/offline/list_transaction',
      hiveBox: 'list_transactions',
      sortField: 'createdAt',
    );

    final files = DomainGenerator(config).generate();

    expect(files.map((f) => f.path), [
      'lib/offline/list_transaction/list_transaction_hive_store.dart',
      'lib/offline/list_transaction/list_transaction_repository.dart',
    ]);

    final repo = files.last.content;
    expect(repo, contains('class ListTransactionRepository'));
    expect(repo, contains('PullCacheRepository<ListTransaction, String>'));
    expect(repo, contains('ListTransactionHiveLocalStore'));
  });

  test('generates drift outbound scaffold', () {
    const config = DomainGeneratorConfig(
      domain: 'expense_report',
      entity: 'ExpenseReport',
      idType: 'int',
      storage: DomainStorage.drift,
      sync: DomainSync.outbound,
      outputDir: 'lib/offline/expense_report',
    );

    final files = DomainGenerator(config).generate();
    expect(files, hasLength(2));
    expect(files.any((f) => f.path.endsWith('_drift_outbound_adapter.dart')), isTrue);
  });

  test('slugToPascal converts snake_case', () {
    expect(DomainGeneratorConfig.slugToPascal('list_transaction'), 'ListTransaction');
  });
}
