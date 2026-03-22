import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tiro_deportivo_amg/database/database_provider.dart';
import 'package:tiro_deportivo_amg/main.dart' as app;
import 'package:tiro_deportivo_amg/services/license_service.dart';

const _quickCompetitionName = 'AAA E2E Torneo Rapido';

/// `true` con `--dart-define=E2E_PORTRAIT_ONLY=true` → solo capturas verticales (sin `_landscape`).
const bool _e2ePortraitOnly = bool.fromEnvironment(
  'E2E_PORTRAIT_ONLY',
  defaultValue: false,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Captura automatica de pantallas principales (portrait)',
    (tester) async {
      await _runCaptureFlow(
        tester: tester,
        binding: binding,
        suffix: '',
        landscape: false,
      );
    },
  );

  if (!_e2ePortraitOnly) {
    testWidgets(
      'Captura automatica de pantallas principales (landscape)',
      (tester) async {
        await _runCaptureFlow(
          tester: tester,
          binding: binding,
          suffix: '_landscape',
          landscape: true,
        );
      },
    );
  }
}

Future<void> _runCaptureFlow({
  required WidgetTester tester,
  required IntegrationTestWidgetsFlutterBinding binding,
  required String suffix,
  required bool landscape,
}) async {
  await _prepareScreenshotEnvironment();
  await _enableScreenshotSupport(binding);
  if (landscape) {
    await _setLandscapeViewport(binding);
  } else {
    await _setPortraitViewport(binding);
  }

  app.main();
  await _settleApp(tester);

  await _takeShot(binding, _name('01_home_panel_control', suffix));

  await _captureTrainingAndSession(tester, binding, suffix: suffix);
  await _captureHistoryAndSessionDetail(tester, binding, suffix: suffix);
  await _captureCompetitionRunnerAndFinal(tester, binding, suffix: suffix);

  await _scrollToMoreOptions(tester);
  await _openSectionFromHome(
    tester: tester,
    binding: binding,
    homeLabel: 'Copia de seguridad',
    openShotName: _name('08_backup', suffix),
    lockShotName: _name('08_backup_bloqueado', suffix),
  );

  await _scrollToMoreOptions(tester);
  await _openConfigAndCaptureSubscreens(
    tester: tester,
    binding: binding,
    suffix: suffix,
  );

  await _captureEstadisticasEntrenamiento(tester, binding, suffix: suffix);
}

Future<void> _enableScreenshotSupport(
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  if (!Platform.isAndroid) return;
  try {
    await binding.convertFlutterSurfaceToImage();
  } catch (e) {
    debugPrint('No se pudo activar modo screenshot: $e');
  }
}

Future<void> _prepareScreenshotEnvironment() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Si se ejecuta con --dart-define=DEV_PLAN_SELECTOR=true,
  // la app reutiliza esta licencia simulada y desbloquea mas secciones.
  const plan = String.fromEnvironment('E2E_PLAN', defaultValue: 'completo');
  await const LicenseService().simularPlanDesarrollo(planClave: plan);
  await _prepareIntegrationData();
}

Future<void> _setPortraitViewport(
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  await binding.setSurfaceSize(const Size(1080, 1920));
  addTearDown(() async => binding.setSurfaceSize(null));
}

Future<void> _setLandscapeViewport(
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  await binding.setSurfaceSize(const Size(1920, 1080));
  addTearDown(() async => binding.setSurfaceSize(null));
}

Future<void> _openSectionFromHome({
  required WidgetTester tester,
  required IntegrationTestWidgetsFlutterBinding binding,
  required String homeLabel,
  required String openShotName,
  required String lockShotName,
}) async {
  final target = find.text(homeLabel);
  if (target.evaluate().isEmpty) {
    debugPrint('No se encontro "$homeLabel" para capturar.');
    return;
  }

  await tester.ensureVisible(target.first);
  await tester.tap(target.first);
  await _settleApp(tester);

  final lockDialog = find.text('Función bloqueada por licencia');
  if (lockDialog.evaluate().isNotEmpty) {
    await _takeShot(binding, lockShotName);
    await _closeLicenseDialog(tester);
    await _settleApp(tester);
    return;
  }

  await _takeShot(binding, openShotName);
  await _goBack(tester);
  await _settleApp(tester);
  await _returnToHome(tester);
}

/// Abre Configuración, captura la pantalla principal y cada submenú (perfil, armas, etc.).
Future<void> _openConfigAndCaptureSubscreens({
  required WidgetTester tester,
  required IntegrationTestWidgetsFlutterBinding binding,
  required String suffix,
}) async {
  final configTarget = find.text('Configuración');
  if (configTarget.evaluate().isEmpty) {
    debugPrint('No se encontro "Configuracion" para capturar.');
    return;
  }

  await tester.ensureVisible(configTarget.first);
  await tester.tap(configTarget.first);
  await _settleApp(tester);

  final lockHome = find.text('Función bloqueada por licencia');
  if (lockHome.evaluate().isNotEmpty) {
    await _takeShot(binding, _name('09_configuracion_bloqueado', suffix));
    await _closeLicenseDialog(tester);
    await _settleApp(tester);
    await _returnToHome(tester);
    return;
  }

  await _takeShot(binding, _name('09_configuracion', suffix));

  await _captureConfigSubscreens(tester, binding, suffix: suffix);
  await _returnToHome(tester);
}

Future<void> _captureConfigSubscreens(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding, {
  required String suffix,
}) async {
  const submenus = <Map<String, String>>[
    {'label': 'Mis Datos (Perfil)', 'shot': '10_mis_datos_perfil'},
    {'label': 'Gestión de Armas (Equipos)', 'shot': '11_mis_armas'},
    {'label': 'Gestión de Munición', 'shot': '12_mis_municiones'},
    {'label': 'Plantillas de Tiempos/Series', 'shot': '13_plantillas_tiempos'},
    {'label': 'Catálogo Tipos de Arma', 'shot': '14_catalogo_tipos_arma'},
    {'label': 'Catálogo de Calibres', 'shot': '15_catalogo_calibres'},
    {'label': 'Catálogo de Dianas', 'shot': '16_catalogo_dianas'},
  ];

  for (final item in submenus) {
    final label = item['label']!;
    final shot = item['shot']!;
    await _scrollConfigUntilVisible(tester, label);
    final target = find.text(label);
    if (target.evaluate().isEmpty) {
      debugPrint('Config: omitido (no visible): $label');
      continue;
    }
    await tester.ensureVisible(target.first);
    await tester.tap(target.first);
    await _settleApp(tester);

    if (_findLicenseLockDialog().evaluate().isNotEmpty) {
      await _takeShot(binding, _name('${shot}_bloqueado', suffix));
      await _closeLicenseDialog(tester);
      await _settleApp(tester);
      continue;
    }

    await _takeShot(binding, _name(shot, suffix));
    await _goBack(tester);
    await _settleApp(tester);
  }
}

Finder _findLicenseLockDialog() {
  return find.textContaining('bloqueada por licencia');
}

Future<void> _scrollConfigUntilVisible(WidgetTester tester, String text) async {
  await _scrollConfigTowardsTop(tester);
  final finder = find.text(text);
  final scrollFinder = find.byType(Scrollable);
  if (scrollFinder.evaluate().isEmpty) return;

  for (var i = 0; i < 32; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder.first);
      return;
    }
    await tester.drag(scrollFinder.first, const Offset(0, -380));
    await _settleApp(tester);
  }
}

Future<void> _scrollConfigTowardsTop(WidgetTester tester) async {
  final scrollFinder = find.byType(Scrollable);
  if (scrollFinder.evaluate().isEmpty) return;
  for (var i = 0; i < 18; i++) {
    await tester.drag(scrollFinder.first, const Offset(0, 420));
    await _settleApp(tester);
  }
}

/// Desde el inicio: Historial → icono de estadísticas → pantalla de análisis de entrenamientos.
Future<void> _captureEstadisticasEntrenamiento(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding, {
  required String suffix,
}) async {
  if (!await _tapTextIfExists(tester, 'Historial y análisis')) return;
  await _settleApp(tester);

  final statsIcon = find.byIcon(Icons.bar_chart_rounded);
  if (statsIcon.evaluate().isEmpty) {
    debugPrint('Historial: sin acceso a estadisticas (icono no visible).');
    await _returnToHome(tester);
    return;
  }

  await tester.tap(statsIcon.first);
  await _settleApp(tester);
  await tester.pump(const Duration(seconds: 2));

  await _takeShot(binding, _name('17_analisis_entrenamientos', suffix));
  await _goBack(tester);
  await _settleApp(tester);
  await _returnToHome(tester);
}

Future<void> _closeLicenseDialog(WidgetTester tester) async {
  final entendidoButton = find.widgetWithText(TextButton, 'Entendido');
  final closeButton = find.text('Entendido');

  if (entendidoButton.evaluate().isNotEmpty) {
    await tester.tap(entendidoButton.first);
    return;
  }
  if (closeButton.evaluate().isNotEmpty) {
    await tester.tap(closeButton.first);
  }
}

Future<void> _goBack(WidgetTester tester) async {
  final materialBack = find.byWidgetPredicate(
    (widget) => widget is BackButton && widget.onPressed != null,
  );
  if (materialBack.evaluate().isNotEmpty) {
    await tester.tap(materialBack.first, warnIfMissed: false);
    return;
  }

  final backButton = find.byTooltip('Back');
  if (backButton.evaluate().isNotEmpty) {
    await tester.tap(backButton.first, warnIfMissed: false);
    return;
  }

  if (tester.binding.hasScheduledFrame) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _scrollToMoreOptions(WidgetTester tester) async {
  final homeScroll = find.byType(Scrollable).first;
  if (homeScroll.evaluate().isEmpty) return;
  await tester.drag(homeScroll, const Offset(0, -400));
  await _settleApp(tester);
}

Future<void> _takeShot(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  try {
    await binding.takeScreenshot(name);
    debugPrint('Captura guardada: $name');
  } catch (e) {
    // En plataformas sin soporte de screenshot no tiramos el test.
    debugPrint('No se pudo guardar captura "$name": $e');
  }
}

Future<void> _settleApp(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));

  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (!tester.binding.hasScheduledFrame) break;
  }
}

Future<void> _captureTrainingAndSession(
    WidgetTester tester, IntegrationTestWidgetsFlutterBinding binding,
    {required String suffix}) async {
  if (!await _tapTextIfExists(tester, 'Entrenamiento')) return;
  await _settleApp(tester);
  await _takeShot(binding, _name('02_entrenamiento', suffix));

  if (await _tapTextIfExists(tester, 'EMPEZAR ENTRENAMIENTO')) {
    await _settleApp(tester);
    await _takeShot(
      binding,
      _name('03_sesion_disparo_entrenamiento', suffix),
    );
    await _tapTextIfExists(tester, 'FINALIZAR');
    await _settleApp(tester);
  }

  await _returnToHome(tester);
}

Future<void> _captureHistoryAndSessionDetail(
    WidgetTester tester, IntegrationTestWidgetsFlutterBinding binding,
    {required String suffix}) async {
  if (!await _tapTextIfExists(tester, 'Historial y análisis')) return;
  await _settleApp(tester);
  await _takeShot(binding, _name('04_historial', suffix));

  final tappedE2E = await _tapTextContainingIfExists(tester, '[E2E]');
  if (!tappedE2E) {
    await _tapAnyHistoryItem(tester);
  }
  await _settleApp(tester);

  if (find.text('Detalle de Tirada').evaluate().isNotEmpty) {
    await _takeShot(binding, _name('05_detalle_tirada', suffix));
    await _goBack(tester);
    await _settleApp(tester);
  } else if (find.text('Detalle Competición').evaluate().isNotEmpty) {
    await _takeShot(binding, _name('05_detalle_competicion', suffix));
    await _goBack(tester);
    await _settleApp(tester);
  }

  await _returnToHome(tester);
}

Future<void> _captureCompetitionRunnerAndFinal(
    WidgetTester tester, IntegrationTestWidgetsFlutterBinding binding,
    {required String suffix}) async {
  if (!await _tapTextIfExists(tester, 'Competición')) return;
  await _settleApp(tester);
  await _takeShot(binding, _name('06_competicion', suffix));

  final quickMode = find.text(_quickCompetitionName);
  if (quickMode.evaluate().isEmpty) {
    await _returnToHome(tester);
    return;
  }

  await tester.ensureVisible(quickMode.first);
  await tester.tap(quickMode.first);
  await _settleApp(tester);

  await _tapTextIfExists(tester, 'EMPEZAR');
  await _settleApp(tester);
  await _takeShot(binding, _name('07_competicion_setup', suffix));

  await _tapTextIfExists(tester, 'COMENZAR TORNEO');
  await _settleApp(tester);
  await _takeShot(binding, _name('07a_competicion_runner', suffix));

  await _tapTextContainingIfExists(tester, 'TIRAR SERIE');
  await _settleApp(tester);
  await _takeShot(binding, _name('07b_competicion_serie', suffix));

  await _tapTextIfExists(tester, 'FINALIZAR');
  await _settleApp(tester);

  if (find.textContaining('COMPETICIÓN FINALIZADA').evaluate().isNotEmpty ||
      find.textContaining('FINALIZADA').evaluate().isNotEmpty) {
    await _takeShot(
      binding,
      _name('07c_competicion_resultados_finales', suffix),
    );
    await _tapTextIfExists(tester, 'SALIR AL MENÚ');
    await _settleApp(tester);
  }

  await _returnToHome(tester);
}

Future<void> _tapAnyHistoryItem(WidgetTester tester) async {
  final tappables = find.byWidgetPredicate(
    (widget) => widget is InkWell && widget.onTap != null,
  );
  if (tappables.evaluate().isEmpty) return;
  await tester.tap(tappables.first);
}

Future<void> _returnToHome(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    if (find.text('Panel de Control').evaluate().isNotEmpty) return;
    await _goBack(tester);
    await _settleApp(tester);
  }
}

Future<bool> _tapTextIfExists(WidgetTester tester, String text) async {
  final target = find.text(text);
  if (target.evaluate().isEmpty) return false;
  await tester.ensureVisible(target.first);
  await tester.tap(target.first);
  return true;
}

Future<bool> _tapTextContainingIfExists(
  WidgetTester tester,
  String text,
) async {
  final target = find.textContaining(text);
  if (target.evaluate().isEmpty) return false;
  await tester.ensureVisible(target.first);
  await tester.tap(target.first);
  return true;
}

Future<void> _prepareIntegrationData() async {
  final db = await DatabaseProvider.instance.database;
  final equipoId = await _ensureEquipo(db);
  final plantillaId = await _ensurePlantilla(db);
  await _recreateQuickTrainingSession(db, equipoId, plantillaId);
  await _upsertQuickCompetition(db, plantillaId);
}

Future<int> _ensureEquipo(Database db) async {
  final equipos = await db.query('Equipos', columns: ['id'], limit: 1);
  if (equipos.isNotEmpty) return (equipos.first['id'] as int?) ?? 1;

  final tipos = await db.query('CatalogoTiposArma', columns: ['id'], limit: 1);
  final calibres =
      await db.query('CatalogoCalibres', columns: ['id'], limit: 1);
  final idTipo = (tipos.isNotEmpty ? tipos.first['id'] : null) as int?;
  final idCalibre = (calibres.isNotEmpty ? calibres.first['id'] : null) as int?;

  return db.insert('Equipos', {
    'nombre': 'Equipo E2E',
    'id_tipo_arma': idTipo,
    'id_calibre': idCalibre,
    'marca': 'E2E',
    'modelo': 'Auto',
    'correccion_click_mm': 5.0,
  });
}

Future<int> _ensurePlantilla(Database db) async {
  final plantillas =
      await db.query('PlantillasTiempos', columns: ['id'], limit: 1);
  if (plantillas.isNotEmpty) return (plantillas.first['id'] as int?) ?? 1;

  final dianas = await db.query('CatalogoDianas', columns: ['id'], limit: 1);
  final idDiana = (dianas.isNotEmpty ? dianas.first['id'] : null) as int?;

  return db.insert('PlantillasTiempos', {
    'nombre_disciplina': 'Plantilla E2E',
    'disparos_por_serie': 5,
    'series_por_sesion': 1,
    'puntuacion_decimal': 0,
    'tiempo_preparacion': 1,
    'es_duelo': 0,
    'tiempo_exposicion': 1,
    'tiempo_ocultacion': 0,
    'id_tipo_diana': idDiana,
  });
}

Future<void> _recreateQuickTrainingSession(
  Database db,
  int equipoId,
  int plantillaId,
) async {
  final oldSessions = await db.query(
    'Sesiones',
    columns: ['id'],
    where: 'nota LIKE ?',
    whereArgs: ['[E2E] %'],
  );
  for (final row in oldSessions) {
    final idSesion = (row['id'] as int?) ?? 0;
    if (idSesion == 0) continue;
    await db.delete('Disparos', where: 'id_sesion = ?', whereArgs: [idSesion]);
    await db.delete('Sesiones', where: 'id = ?', whereArgs: [idSesion]);
  }

  final now = DateTime.now().toIso8601String();
  final sesionId = await db.insert('Sesiones', {
    'fecha': now,
    'id_equipo': equipoId,
    'id_plantilla_tiempos': plantillaId,
    'id_modalidad': null,
    'nota': '[E2E] Sesion Manual',
    'lugar': 'Galeria E2E',
  });

  for (var i = 1; i <= 5; i++) {
    await db.insert('Disparos', {
      'id_sesion': sesionId,
      'numero_disparo': i,
      'coordenada_x': 0.01 * i,
      'coordenada_y': 0.02 * i,
      'puntuacion': 8.0 + (i * 0.2),
      'es_mosca': 0,
      'es_fuera': 0,
    });
  }
}

Future<void> _upsertQuickCompetition(Database db, int plantillaId) async {
  final existing = await db.query(
    'Modalidades',
    columns: ['id'],
    where: 'nombre = ?',
    whereArgs: [_quickCompetitionName],
    limit: 1,
  );

  int modalidadId;
  if (existing.isNotEmpty) {
    modalidadId = (existing.first['id'] as int?) ?? 0;
  } else {
    modalidadId = await db.insert('Modalidades', {
      'nombre': _quickCompetitionName,
      'descripcion': 'Flujo rapido para screenshots',
      'es_oficial': 0,
    });
  }
  if (modalidadId == 0) return;

  await db.delete(
    'FasesModalidad',
    where: 'id_modalidad = ?',
    whereArgs: [modalidadId],
  );
  await db.insert('FasesModalidad', {
    'id_modalidad': modalidadId,
    'orden': 1,
    'id_plantilla_tiempos': plantillaId,
    'repeticiones': 1,
    'es_ensayo': 0,
    'descripcion_fase': 'Serie unica E2E',
  });
}

String _name(String base, String suffix) => '$base$suffix';
