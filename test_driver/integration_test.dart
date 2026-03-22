// Driver para integration_test: guarda las capturas en docs/screenshots/
// Uso: flutter drive --driver=test_driver/integration_test.dart --target=integration_test/screenshot_flow_test.dart ...
//
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  await integrationDriver(
    onScreenshot:
        (String screenshotName, List<int> screenshotBytes, [
      Map<String, Object?>? args,
    ]) async {
      final root = Directory.current.path;
      final outDir = Directory(p.join(root, 'docs', 'screenshots'));
      await outDir.create(recursive: true);
      final file = File(p.join(outDir.path, '$screenshotName.png'));
      await file.writeAsBytes(screenshotBytes);
      print('PNG guardado: ${file.path}');
      return true;
    },
  );
}
