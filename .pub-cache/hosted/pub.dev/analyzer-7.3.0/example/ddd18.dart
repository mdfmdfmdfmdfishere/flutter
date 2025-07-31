import 'dart:io' as io;

import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/analysis/byte_store.dart';
import 'package:analyzer/src/dart/analysis/file_content_cache.dart';
import 'package:analyzer/src/dart/analysis/flags.dart';
import 'package:analyzer/src/dart/analysis/performance_logger.dart';
import 'package:analyzer/src/util/performance/operation_performance.dart';
import 'package:linter/src/rules.dart';

void main() async {
  var resourceProvider = OverlayResourceProvider(
    PhysicalResourceProvider.INSTANCE,
  );

  withFineDependencies = true;
  registerLintRules();

  var byteStore = MemoryByteStore();

  var packageRootPath = '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer';
  var libPath = '$packageRootPath/lib';

  var targetPath = '$libPath/src/summary2/bundle_manifest.dart';
  print(targetPath);
  var targetCode = resourceProvider.getFile(targetPath).readAsStringSync();

  var collection = AnalysisContextCollectionImpl(
    resourceProvider: resourceProvider,
    includedPaths: [
      // packageRootPath,
      '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer',
      '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analysis_server',
      '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analysis_server_plugin',
      '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer_cli',
      '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/linter',
      //
      // '/Users/scheglov/Source/Dart/sdk.git/sdk/pkg/analyzer/lib/src/dart/analysis',
    ],
    byteStore: byteStore,
    fileContentCache: FileContentCache(resourceProvider),
    performanceLog: PerformanceLog(io.stdout),
    drainStreams: false,
  );

  for (var analysisContext in collection.contexts) {
    for (var path in analysisContext.contextRoot.analyzedFiles()) {
      if (path.endsWith('.dart')) {
        analysisContext.driver.addFile(path);
      }
    }
  }

  await collection.scheduler.waitForIdle();
  await pumpEventQueue();
  print('\n' * 2);
  print('[S] Now idle');
  print('-' * 64);

  {
    print('\n' * 2);
    var buffer = StringBuffer();
    collection.scheduler.accumulatedPerformance.write(buffer: buffer);
    print(buffer);
    collection.scheduler.accumulatedPerformance =
        OperationPerformanceImpl('<scheduler>');
  }

  resourceProvider.setOverlay(
    targetPath,
    content: targetCode.replaceAll(
      'computeManifests() {',
      'computeManifests2() {',
    ),
    modificationStamp: 1,
  );
  for (var analysisContext in collection.contexts) {
    analysisContext.changeFile(targetPath);
  }

  print('[S] computeManifests() -> computeManifests2()');
  print('\n' * 2);
  await collection.scheduler.waitForIdle();
  await pumpEventQueue();
  print('\n' * 2);
  print('[S] Now idle');
  print('-' * 64);

  {
    print('\n' * 2);
    var buffer = StringBuffer();
    collection.scheduler.accumulatedPerformance.write(buffer: buffer);
    print(buffer);
    collection.scheduler.accumulatedPerformance =
        OperationPerformanceImpl('<scheduler>');
  }

  print('[S] Disposing...');
  await collection.dispose();
}

final Stopwatch timer = Stopwatch()..start();

Future pumpEventQueue([int times = 5000]) {
  if (times == 0) return Future.value();
  return Future.delayed(Duration.zero, () => pumpEventQueue(times - 1));
}
