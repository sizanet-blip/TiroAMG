import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/database_provider.dart';
import '../models/licencia_model.dart';

class LicenseService {
  const LicenseService();

  static const String apiBaseUrl = String.fromEnvironment(
    'LICENSE_API_URL',
    defaultValue: '',
  );

  Future<LicenciaLocal?> obtenerLicenciaLocal() async {
    final db = await DatabaseProvider.instance.database;
    final rows = await db.query('Licencias', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return null;
    return LicenciaLocal.fromMap(rows.first);
  }

  Future<LicenseCapabilityServerResult> verificarCapacidadServidor({
    required LicenciaLocal? licencia,
    required String capability,
    String? identificadorUsuario,
  }) async {
    final base = apiBaseUrl.trim();
    if (base.isEmpty) {
      return const LicenseCapabilityServerResult(
        known: false,
        allowed: false,
        message: 'Licencias en servidor desactivadas.',
      );
    }

    if (licencia == null || licencia.licenciaKey.trim().isEmpty) {
      return const LicenseCapabilityServerResult(
        known: true,
        allowed: false,
        message: 'Licencia no disponible para validar capacidad.',
      );
    }

    try {
      final package = await PackageInfo.fromPlatform();
      final deviceId = await _obtenerDeviceIdPersistente();
      final identifier = identificadorUsuario?.trim() ?? '';

      final response = await http
          .post(
            Uri.parse('$base/licenses/can'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'license_key': licencia.licenciaKey,
              'device_id': deviceId,
              'capability': capability,
              'platform': _platformKey,
              'app_version': package.version,
              'build_number': package.buildNumber,
              if (identifier.isNotEmpty && identifier.contains('@'))
                'email': identifier,
              if (identifier.isNotEmpty && !identifier.contains('@'))
                'username': identifier,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        final allowed = data is Map<String, dynamic> && data['allowed'] == true;
        return LicenseCapabilityServerResult(
          known: true,
          allowed: allowed,
          message: allowed
              ? 'Capacidad permitida por servidor.'
              : 'Función no habilitada para tu licencia.',
        );
      }

      // Errores de negocio conocidos: bloqueamos.
      if (response.statusCode >= 400 && response.statusCode < 500) {
        String message = _mensajeServidorAmigable(
          response.statusCode,
          contexto: 'can',
        );
        try {
          final data = jsonDecode(response.body);
          if (data is Map<String, dynamic> &&
              data['message'] is String &&
              (data['message'] as String).trim().isNotEmpty) {
            message = data['message'] as String;
          }
        } catch (_) {}
        return LicenseCapabilityServerResult(
          known: true,
          allowed: false,
          message: message,
        );
      }

      // Errores 5xx: sin certeza, dejamos fallback local.
      return const LicenseCapabilityServerResult(
        known: false,
        allowed: false,
        message: 'Servidor de licencias no disponible temporalmente.',
      );
    } on SocketException {
      return const LicenseCapabilityServerResult(
        known: false,
        allowed: false,
        message: 'Sin conexión. Usando validación local.',
      );
    } on TimeoutException {
      return const LicenseCapabilityServerResult(
        known: false,
        allowed: false,
        message: 'Tiempo de espera agotado. Usando validación local.',
      );
    } on http.ClientException {
      return const LicenseCapabilityServerResult(
        known: false,
        allowed: false,
        message: 'Error de red. Usando validación local.',
      );
    } catch (_) {
      return const LicenseCapabilityServerResult(
        known: false,
        allowed: false,
        message: 'No se pudo validar con servidor. Usando validación local.',
      );
    }
  }

  Future<LicenseUpgradeResult> solicitarUpgrade({
    required LicenciaLocal? licencia,
    required String capability,
    required String requiredPlan,
    required String currentPlan,
  }) async {
    final deviceId = await _obtenerDeviceIdPersistente();
    final package = await PackageInfo.fromPlatform();

    var backendRegistrado = false;
    var backendMensaje = '';
    String? detalleFallo;
    final base = apiBaseUrl.trim();

    if (base.isEmpty) {
      detalleFallo = 'El servicio de licencias no está disponible';
    } else if (licencia == null || licencia.licenciaKey.trim().isEmpty) {
      detalleFallo = 'No hay una licencia válida para procesar la solicitud';
    } else {
      try {
        final response = await http
            .post(
              Uri.parse('$base/licenses/upgrade-request'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'license_key': licencia.licenciaKey.trim(),
                'device_id': deviceId,
                'capability': capability,
                'required_plan': requiredPlan,
                'current_plan': currentPlan,
                'platform': _platformKey,
                'app_version': package.version,
                'build_number': package.buildNumber,
              }),
            )
            .timeout(const Duration(seconds: 8));

        Map<String, dynamic>? data;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            data = decoded;
          }
        } catch (_) {}

        if (data != null && data['message'] is String) {
          backendMensaje = (data['message'] as String).trim();
        }

        if (response.statusCode >= 200 && response.statusCode < 300) {
          backendRegistrado = true;
        } else if (response.statusCode >= 500) {
          detalleFallo = 'Error temporal del servidor';
        } else if (response.statusCode == 404) {
          detalleFallo = 'La licencia no fue encontrada en el servidor';
        } else if (response.statusCode == 403) {
          detalleFallo = 'La licencia no coincide con el usuario vinculado';
        } else if (response.statusCode == 400) {
          detalleFallo = backendMensaje.isNotEmpty
              ? backendMensaje
              : 'La solicitud tiene datos incompletos';
        } else {
          detalleFallo = backendMensaje.isNotEmpty
              ? backendMensaje
              : 'No se pudo procesar la solicitud';
        }
      } on TimeoutException {
        detalleFallo = 'El servidor tardó demasiado en responder';
        backendRegistrado = false;
      } on SocketException {
        detalleFallo = 'No hay conexión a internet';
        backendRegistrado = false;
      } on http.ClientException {
        detalleFallo = 'No se pudo conectar con el servidor de licencias';
        backendRegistrado = false;
      } catch (_) {
        detalleFallo = 'Ocurrió un error inesperado al enviar la solicitud';
        backendRegistrado = false;
      }
    }

    const emailAbierto = false;

    final message = backendRegistrado
        ? (backendMensaje.isNotEmpty
            ? backendMensaje
            : 'Solicitud de mejora de plan registrada correctamente.')
        : 'No se pudo registrar la solicitud en este momento.'
            '${detalleFallo != null && detalleFallo.isNotEmpty ? ' $detalleFallo.' : ''}'
            ' Inténtalo de nuevo más tarde.';

    await _guardarEstadoUltimoUpgrade(
      capability: capability,
      requiredPlan: requiredPlan,
      currentPlan: currentPlan,
      backendRegistered: backendRegistrado,
      emailOpened: emailAbierto,
      message: message,
    );
    await _registrarEnHistorialUpgrade(
      capability: capability,
      requiredPlan: requiredPlan,
      currentPlan: currentPlan,
      backendRegistered: backendRegistrado,
      emailOpened: emailAbierto,
      message: message,
    );

    return LicenseUpgradeResult(
      backendRegistered: backendRegistrado,
      emailOpened: emailAbierto,
      message: message,
    );
  }

  Future<LicenseUpgradeStatus?> obtenerUltimoUpgradeStatus() async {
    final db = await DatabaseProvider.instance.database;
    final rows = await db.query(
      'Licencias',
      columns: [
        'ultimo_upgrade_at',
        'ultimo_upgrade_capability',
        'ultimo_upgrade_plan_requerido',
        'ultimo_upgrade_plan_actual',
        'ultimo_upgrade_backend_ok',
        'ultimo_upgrade_email_ok',
        'ultimo_upgrade_msg',
      ],
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final rawDate = row['ultimo_upgrade_at']?.toString();
    if (rawDate == null || rawDate.trim().isEmpty) return null;
    final at = DateTime.tryParse(rawDate);
    if (at == null) return null;

    return LicenseUpgradeStatus(
      at: at.toLocal(),
      capability: row['ultimo_upgrade_capability']?.toString() ?? '-',
      requiredPlan: row['ultimo_upgrade_plan_requerido']?.toString() ?? '-',
      currentPlan: row['ultimo_upgrade_plan_actual']?.toString() ?? '-',
      backendRegistered: (row['ultimo_upgrade_backend_ok'] as num?)?.toInt() == 1,
      emailOpened: (row['ultimo_upgrade_email_ok'] as num?)?.toInt() == 1,
      message: row['ultimo_upgrade_msg']?.toString() ?? '',
    );
  }

  Future<List<LicenseUpgradeStatus>> obtenerHistorialUpgrade({
    int limit = 20,
  }) async {
    final db = await DatabaseProvider.instance.database;
    final rows = await db.query(
      'UpgradeSolicitudes',
      orderBy: 'id DESC',
      limit: limit,
    );

    return rows
        .map((row) {
          final at = DateTime.tryParse(row['fecha']?.toString() ?? '');
          if (at == null) return null;
          return LicenseUpgradeStatus(
            at: at.toLocal(),
            capability: row['capability']?.toString() ?? '-',
            requiredPlan: row['plan_requerido']?.toString() ?? '-',
            currentPlan: row['plan_actual']?.toString() ?? '-',
            backendRegistered: (row['backend_ok'] as num?)?.toInt() == 1,
            emailOpened: (row['email_ok'] as num?)?.toInt() == 1,
            message: row['mensaje']?.toString() ?? '',
          );
        })
        .whereType<LicenseUpgradeStatus>()
        .toList();
  }

  Future<int> limpiarHistorialUpgrade({bool limpiarUltimoEstado = false}) async {
    final db = await DatabaseProvider.instance.database;
    final borradas = await db.delete('UpgradeSolicitudes');
    if (limpiarUltimoEstado) {
      await _limpiarEstadoUltimoUpgrade();
    }
    return borradas;
  }

  Future<bool> exportarHistorialUpgradePorEmail({
    required List<LicenseUpgradeStatus> items,
    String to = 'info@albertomaestre.es',
  }) async {
    final exportItems = items.take(20).toList();
    final truncado = items.length > exportItems.length;

    const subject = 'Historial de solicitudes de mejora de plan - Tiro Deportivo AMG';
    final body = <String>[
      'Hola,',
      '',
      'Comparto historial de solicitudes de mejora de plan desde la app.',
      '',
      if (exportItems.isEmpty) 'No hay solicitudes en el historial.',
      if (exportItems.isNotEmpty) ...[
        'Solicitudes incluidas: ${exportItems.length}${truncado ? ' (truncado)' : ''}',
        '',
        for (final item in exportItems) ...[
          '- Fecha: ${item.at.toString().split('.').first}',
          '  Capability: ${item.capability}',
          '  Plan requerido: ${item.requiredPlan}',
          '  Plan actual: ${item.currentPlan}',
          '  Backend: ${item.backendRegistered ? 'registrado' : 'pendiente'}',
          '  Email: ${item.emailOpened ? 'abierto' : 'no abierto'}',
          '  Mensaje: ${item.message}',
          '',
        ],
      ],
    ].join('\n');

    final emailUri = Uri(
      scheme: 'mailto',
      path: to,
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );

    return launchUrl(
      emailUri,
      mode: LaunchMode.externalApplication,
    );
  }

  Future<LicenciaCheckResult> revisarLicencia({bool forzarServidor = false}) async {
    if (apiBaseUrl.trim().isEmpty) {
      return const LicenciaCheckResult(
        esValida: true,
        enGraciaOffline: false,
        requiereActivacion: false,
        mensaje: 'Licencias desactivadas (LICENSE_API_URL sin configurar).',
        licencia: null,
      );
    }
    final licenciaLocal = await obtenerLicenciaLocal();
    if (licenciaLocal == null || licenciaLocal.licenciaKey.trim().isEmpty) {
      return const LicenciaCheckResult(
        esValida: false,
        enGraciaOffline: false,
        requiereActivacion: true,
        mensaje: 'Activa una licencia para continuar.',
        licencia: null,
      );
    }
    var licencia = licenciaLocal;

    final ahora = DateTime.now().toUtc();
    final tocaValidar = forzarServidor ||
        licencia.proximaValidacion == null ||
        !licencia.proximaValidacion!.isAfter(ahora);

    var huboErrorRed = false;
    if (tocaValidar) {
      try {
        licencia = await _validarEnServidor(licencia);
      } on _LicenseServerException catch (e) {
        if (e.statusCode >= 500) {
          huboErrorRed = true;
        } else {
          await _marcarLicenciaInvalidaEnLocal(licencia);
          return LicenciaCheckResult(
            esValida: false,
            enGraciaOffline: false,
            requiereActivacion: true,
            mensaje: _mensajeServidorAmigable(e.statusCode, contexto: 'validate'),
            licencia: licencia,
          );
        }
      } on SocketException {
        huboErrorRed = true;
      } on TimeoutException {
        huboErrorRed = true;
      } on http.ClientException {
        huboErrorRed = true;
      } catch (_) {
        huboErrorRed = true;
      }
    }

    return _evaluarLicenciaLocal(licencia, huboErrorRed: huboErrorRed);
  }

  Future<LicenciaCheckResult> activarLicencia({
    required String licenciaKey,
    String? identificadorUsuario,
  }) async {
    final base = apiBaseUrl.trim();
    if (base.isEmpty) {
      return const LicenciaCheckResult(
        esValida: false,
        enGraciaOffline: false,
        requiereActivacion: true,
        mensaje: 'No se ha configurado LICENSE_API_URL.',
        licencia: null,
      );
    }
    final key = licenciaKey.trim();
    if (key.isEmpty) {
      return const LicenciaCheckResult(
        esValida: false,
        enGraciaOffline: false,
        requiereActivacion: true,
        mensaje: 'Introduce una licencia válida.',
        licencia: null,
      );
    }

    try {
      final package = await PackageInfo.fromPlatform();
      final deviceId = await _obtenerDeviceIdPersistente();
      final identifier = identificadorUsuario?.trim() ?? '';

      final response = await http
          .post(
            Uri.parse('$base/licenses/activate'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'license_key': key,
              'device_id': deviceId,
              'platform': _platformKey,
              'app_version': package.version,
              'build_number': package.buildNumber,
              if (identifier.isNotEmpty && identifier.contains('@'))
                'email': identifier,
              if (identifier.isNotEmpty && !identifier.contains('@'))
                'username': identifier,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return LicenciaCheckResult(
          esValida: false,
          enGraciaOffline: false,
          requiereActivacion: true,
          mensaje: _mensajeServidorAmigable(response.statusCode, contexto: 'activate'),
          licencia: null,
        );
      }

      final data = jsonDecode(response.body);
      final payload = _normalizarPayloadLicencia(data, licenciaKey: key, deviceId: deviceId);
      final licencia = await _guardarPayloadLicencia(payload);
      return _evaluarLicenciaLocal(licencia, huboErrorRed: false);
    } catch (e) {
      return LicenciaCheckResult(
        esValida: false,
        enGraciaOffline: false,
        requiereActivacion: true,
        mensaje: 'No se pudo activar la licencia: $e',
        licencia: null,
      );
    }
  }

  Future<LicenciaCheckResult> solicitarLicenciaAutomatica({
    required String identificadorUsuario,
    String? nombreApp,
  }) async {
    final base = apiBaseUrl.trim();
    if (base.isEmpty) {
      return const LicenciaCheckResult(
        esValida: false,
        enGraciaOffline: false,
        requiereActivacion: true,
        mensaje: 'No se ha configurado LICENSE_API_URL.',
        licencia: null,
      );
    }

    final identifier = identificadorUsuario.trim();
    if (identifier.isEmpty) {
      return const LicenciaCheckResult(
        esValida: false,
        enGraciaOffline: false,
        requiereActivacion: true,
        mensaje: 'Introduce un email válido para solicitar licencia.',
        licencia: null,
      );
    }

    try {
      final package = await PackageInfo.fromPlatform();
      final deviceId = await _obtenerDeviceIdPersistente();
      final response = await http
          .post(
            Uri.parse('$base/licenses/request'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'device_id': deviceId,
              'platform': _platformKey,
              'app_version': package.version,
              'build_number': package.buildNumber,
              if (nombreApp != null && nombreApp.trim().isNotEmpty)
                'app_name': nombreApp.trim(),
              if (identifier.contains('@')) 'email': identifier,
              if (!identifier.contains('@')) 'username': identifier,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return LicenciaCheckResult(
          esValida: false,
          enGraciaOffline: false,
          requiereActivacion: true,
          mensaje: _mensajeServidorAmigable(response.statusCode, contexto: 'request'),
          licencia: null,
        );
      }

      final data = jsonDecode(response.body);
      final remoteLicense = data['license'];
      final remoteKey = remoteLicense is Map<String, dynamic>
          ? (remoteLicense['license_key']?.toString() ?? '').trim()
          : '';
      final payload = _normalizarPayloadLicencia(
        data,
        licenciaKey: remoteKey,
        deviceId: deviceId,
      );
      final licencia = await _guardarPayloadLicencia(payload);
      return _evaluarLicenciaLocal(licencia, huboErrorRed: false);
    } catch (e) {
      return LicenciaCheckResult(
        esValida: false,
        enGraciaOffline: false,
        requiereActivacion: true,
        mensaje: 'No se pudo solicitar licencia automática: $e',
        licencia: null,
      );
    }
  }

  Future<LicenciaLocal> _validarEnServidor(LicenciaLocal local) async {
    final package = await PackageInfo.fromPlatform();
    final base = apiBaseUrl.trim();

    final response = await http
        .post(
          Uri.parse('$base/licenses/validate'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'license_key': local.licenciaKey,
            'device_id': local.deviceId,
            'platform': _platformKey,
            'app_version': package.version,
            'build_number': package.buildNumber,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _LicenseServerException(response.statusCode);
    }

    final data = jsonDecode(response.body);
    final payload = _normalizarPayloadLicencia(
      data,
      licenciaKey: local.licenciaKey,
      deviceId: local.deviceId ?? await _obtenerDeviceIdPersistente(),
    );
    return _guardarPayloadLicencia(payload);
  }

  Future<LicenciaLocal> _guardarPayloadLicencia(Map<String, dynamic> payload) async {
    final db = await DatabaseProvider.instance.database;
    await db.insert(
      'Licencias',
      payload,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final guardada = await obtenerLicenciaLocal();
    if (guardada == null) {
      throw StateError('No se pudo persistir la licencia local.');
    }
    return guardada;
  }

  Map<String, dynamic> _normalizarPayloadLicencia(
    dynamic responseData, {
    required String licenciaKey,
    required String deviceId,
  }) {
    final root = responseData is Map<String, dynamic> ? responseData : const {};
    final lic = root['license'] is Map<String, dynamic>
        ? root['license'] as Map<String, dynamic>
        : root;
    final nowUtc = DateTime.now().toUtc();
    final serverNow = DateTime.tryParse((root['server_time'] ?? lic['server_time'] ?? '').toString())?.toUtc() ?? nowUtc;
    final nextValidation = serverNow.add(const Duration(hours: 12));

    final rawFeatures = lic['features'];
    final features = rawFeatures is Map<String, dynamic> ? rawFeatures : <String, dynamic>{};

    return {
      'id': 1,
      'license_key': lic['license_key']?.toString().trim().isNotEmpty == true
          ? lic['license_key'].toString().trim()
          : licenciaKey.trim(),
      'estado': (lic['status'] ?? lic['estado'] ?? 'inactive').toString(),
      'fecha_inicio': _asDateIso(lic['fecha_inicio']),
      'fecha_fin': _asDateIso(lic['fecha_fin']),
      'plan': lic['plan']?.toString(),
      'features_json': jsonEncode(features),
      'device_id': (lic['device_id'] ?? deviceId).toString(),
      'ultima_validacion': serverNow.toIso8601String(),
      'proxima_validacion': nextValidation.toIso8601String(),
      'dias_gracia_offline': (lic['grace_days_offline'] as num?)?.toInt() ?? 3,
      'max_dispositivos': (lic['max_devices'] as num?)?.toInt(),
      'firma': (lic['signature'] ?? root['signature'])?.toString(),
    };
  }

  LicenciaCheckResult _evaluarLicenciaLocal(
    LicenciaLocal local, {
    required bool huboErrorRed,
  }) {
    final now = DateTime.now().toUtc();
    final estado = local.estado.toLowerCase().trim();

    if (estado == 'revoked' || estado == 'suspended') {
      return LicenciaCheckResult(
        esValida: false,
        enGraciaOffline: false,
        requiereActivacion: false,
        mensaje: 'Licencia deshabilitada ($estado).',
        licencia: local,
      );
    }

    final fechaFin = local.fechaFin;
    if (estado == 'active' && (fechaFin == null || !fechaFin.isBefore(now))) {
      return LicenciaCheckResult(
        esValida: true,
        enGraciaOffline: false,
        requiereActivacion: false,
        mensaje: 'Licencia activa.',
        licencia: local,
      );
    }

    if (huboErrorRed && local.ultimaValidacion != null) {
      final venceGracia = local.ultimaValidacion!
          .add(Duration(days: local.diasGraciaOffline));
      if (!venceGracia.isBefore(now)) {
        return LicenciaCheckResult(
          esValida: true,
          enGraciaOffline: true,
          requiereActivacion: false,
          mensaje: 'Sin red. Operando en periodo de gracia offline.',
          licencia: local,
        );
      }
    }

    return LicenciaCheckResult(
      esValida: false,
      enGraciaOffline: false,
      requiereActivacion: false,
      mensaje: 'La licencia ha expirado o no está activa.',
      licencia: local,
    );
  }

  Future<String> _obtenerDeviceIdPersistente() async {
    final db = await DatabaseProvider.instance.database;
    final rows = await db.query('Licencias', columns: ['device_id'], where: 'id = 1', limit: 1);
    final existing = rows.isNotEmpty ? rows.first['device_id']?.toString() : null;
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _generarDeviceId();
    await db.insert(
      'Licencias',
      {
        'id': 1,
        'license_key': '',
        'estado': 'inactive',
        'device_id': generated,
        'ultima_validacion': null,
        'proxima_validacion': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return generated;
  }

  String _generarDeviceId() {
    final rnd = Random.secure();
    final randomPart = List.generate(24, (_) => rnd.nextInt(16).toRadixString(16)).join();
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    return 'tdamg-$ts-$randomPart';
  }

  String? _asDateIso(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc().toIso8601String();
  }

  String get _platformKey {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  Future<void> _marcarLicenciaInvalidaEnLocal(LicenciaLocal licencia) async {
    final db = await DatabaseProvider.instance.database;
    await db.update(
      'Licencias',
      {
        'estado': 'revoked',
        'proxima_validacion': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [licencia.id],
    );
  }

  Future<void> _guardarEstadoUltimoUpgrade({
    required String capability,
    required String requiredPlan,
    required String currentPlan,
    required bool backendRegistered,
    required bool emailOpened,
    required String message,
  }) async {
    final db = await DatabaseProvider.instance.database;
    await db.insert(
      'Licencias',
      {
        'id': 1,
        'ultimo_upgrade_at': DateTime.now().toUtc().toIso8601String(),
        'ultimo_upgrade_capability': capability,
        'ultimo_upgrade_plan_requerido': requiredPlan,
        'ultimo_upgrade_plan_actual': currentPlan,
        'ultimo_upgrade_backend_ok': backendRegistered ? 1 : 0,
        'ultimo_upgrade_email_ok': emailOpened ? 1 : 0,
        'ultimo_upgrade_msg': message,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.update(
      'Licencias',
      {
        'ultimo_upgrade_at': DateTime.now().toUtc().toIso8601String(),
        'ultimo_upgrade_capability': capability,
        'ultimo_upgrade_plan_requerido': requiredPlan,
        'ultimo_upgrade_plan_actual': currentPlan,
        'ultimo_upgrade_backend_ok': backendRegistered ? 1 : 0,
        'ultimo_upgrade_email_ok': emailOpened ? 1 : 0,
        'ultimo_upgrade_msg': message,
      },
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  Future<void> _registrarEnHistorialUpgrade({
    required String capability,
    required String requiredPlan,
    required String currentPlan,
    required bool backendRegistered,
    required bool emailOpened,
    required String message,
  }) async {
    final db = await DatabaseProvider.instance.database;
    await db.insert(
      'UpgradeSolicitudes',
      {
        'fecha': DateTime.now().toUtc().toIso8601String(),
        'capability': capability,
        'plan_requerido': requiredPlan,
        'plan_actual': currentPlan,
        'backend_ok': backendRegistered ? 1 : 0,
        'email_ok': emailOpened ? 1 : 0,
        'mensaje': message,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> _limpiarEstadoUltimoUpgrade() async {
    final db = await DatabaseProvider.instance.database;
    await db.update(
      'Licencias',
      {
        'ultimo_upgrade_at': null,
        'ultimo_upgrade_capability': null,
        'ultimo_upgrade_plan_requerido': null,
        'ultimo_upgrade_plan_actual': null,
        'ultimo_upgrade_backend_ok': null,
        'ultimo_upgrade_email_ok': null,
        'ultimo_upgrade_msg': null,
      },
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  String _mensajeServidorAmigable(int statusCode, {required String contexto}) {
    if (statusCode == 400) {
      if (contexto == 'request') {
        return 'Faltan datos para solicitar la licencia.';
      }
      if (contexto == 'activate') {
        return 'Faltan datos para activar la licencia.';
      }
      if (contexto == 'can') {
        return 'Faltan datos para validar permisos de licencia.';
      }
      return 'La validación de licencia no tiene todos los datos requeridos.';
    }
    if (statusCode == 401) {
      return 'No se pudo autenticar la solicitud con el servidor de licencias.';
    }
    if (statusCode == 403) {
      return 'La licencia no está autorizada o está bloqueada.';
    }
    if (statusCode == 404) {
      if (contexto == 'request') {
        return 'No se encontró el servicio de licencias.';
      }
      if (contexto == 'can') {
        return 'No se encontró la licencia al validar permisos.';
      }
      return 'La clave de licencia no existe o ya no es válida.';
    }
    if (statusCode == 409) {
      return 'Se alcanzó el máximo de dispositivos permitidos para esta licencia.';
    }
    if (statusCode >= 500) {
      return 'El servidor de licencias no está disponible temporalmente.';
    }
    return 'No se pudo completar la operación de licencia en este momento.';
  }

}

class _LicenseServerException implements Exception {
  final int statusCode;

  _LicenseServerException(this.statusCode);
}

class LicenseCapabilityServerResult {
  final bool known;
  final bool allowed;
  final String message;

  const LicenseCapabilityServerResult({
    required this.known,
    required this.allowed,
    required this.message,
  });
}

class LicenseUpgradeResult {
  final bool backendRegistered;
  final bool emailOpened;
  final String message;

  const LicenseUpgradeResult({
    required this.backendRegistered,
    required this.emailOpened,
    required this.message,
  });
}

class LicenseUpgradeStatus {
  final DateTime at;
  final String capability;
  final String requiredPlan;
  final String currentPlan;
  final bool backendRegistered;
  final bool emailOpened;
  final String message;

  const LicenseUpgradeStatus({
    required this.at,
    required this.capability,
    required this.requiredPlan,
    required this.currentPlan,
    required this.backendRegistered,
    required this.emailOpened,
    required this.message,
  });
}
