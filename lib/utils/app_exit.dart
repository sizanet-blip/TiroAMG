import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Cierra la app de forma fiable en móvil y escritorio.
void exitApp() {
  if (kIsWeb) return;
  if (Platform.isAndroid || Platform.isIOS) {
    SystemNavigator.pop();
    return;
  }
  exit(0);
}
