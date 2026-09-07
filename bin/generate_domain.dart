#!/usr/bin/env dart

import 'dart:io';

import 'package:args/args.dart';
import 'package:offline_sync_engine/src/codegen/domain_generator.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('config', abbr: 'c', help: 'Path to offline_domain.yaml')
    ..addOption('domain', help: 'Domain slug, e.g. list_transaction')
    ..addOption('entity', help: 'Entity class name, e.g. ListTransaction')
    ..addOption('id-type', defaultsTo: 'String', help: 'Id type (String, int, …)')
    ..addOption('storage', defaultsTo: 'hive', help: 'hive | drift | memory')
    ..addOption('sync', defaultsTo: 'pull', help: 'pull | outbound | both')
    ..addOption('output-dir', help: 'Output directory, e.g. lib/offline/list_transaction')
    ..addOption('hive-box', help: 'Hive box name')
    ..addOption('drift-table', help: 'Drift table name for codegen comments')
    ..addOption('sort-field', help: 'Entity field used for local sort, e.g. createdAt')
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(arguments);

  if (args['help'] == true) {
    stdout.writeln('Generate offline domain scaffolding.\n');
    stdout.writeln('Usage: dart run offline_sync_engine:generate_domain [options]\n');
    stdout.writeln(parser.usage);
    stdout.writeln('\nExample config (offline_domain.yaml):');
    stdout.writeln('''
domain: list_transaction
entity: ListTransaction
id_type: String
storage: hive
sync: pull
hive_box: list_transactions
sort_field: createdAt
output_dir: lib/offline/list_transaction
''');
    exit(0);
  }

  final DomainGeneratorConfig config;
  if (args['config'] != null) {
    final file = File(args['config'] as String);
    final yaml = loadYaml(await file.readAsString()) as YamlMap;
    config = DomainGeneratorConfig.fromYamlMap(yaml);
  } else {
    final domain = args['domain'] as String?;
    final outputDir = args['output-dir'] as String?;
    if (domain == null || outputDir == null) {
      stderr.writeln('Provide --config or both --domain and --output-dir.');
      stderr.writeln(parser.usage);
      exit(64);
    }
    config = DomainGeneratorConfig(
      domain: domain,
      entity: args['entity'] as String? ?? DomainGeneratorConfig.slugToPascal(domain),
      idType: args['id-type'] as String,
      storage: DomainStorage.fromString(args['storage'] as String),
      sync: DomainSync.fromString(args['sync'] as String),
      outputDir: outputDir,
      hiveBox: args['hive-box'] as String?,
      driftTable: args['drift-table'] as String?,
      sortField: args['sort-field'] as String?,
    );
  }

  final generator = DomainGenerator(config);
  final files = generator.generate();

  for (final file in files) {
    final outFile = File(p.normalize(file.path));
    await outFile.parent.create(recursive: true);
    await outFile.writeAsString(file.content);
    stdout.writeln('Wrote ${outFile.path}');
  }

  stdout.writeln('\nDone. Wire fetchAll/pushOne/isOnline to your API, then register in OfflineSyncKit.');
}
