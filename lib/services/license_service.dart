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
import 'license_api_http.dart';

class LicenseService {
  const LicenseService();

  /// Id canónico en el inventario unificado del panel AMG.
  static const String appName = 'TiroAMG';

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
        known: false,
        allowed: false,
        message: 'Sin registro remoto aún. Usando módulos locales.',
      );
    }

    try {
      final package = await PackageInfo.fromPlatform();
      final deviceId = await _obtenerDeviceIdPersistente();
      final identifier = identificadorUsuario?.trim() ?? '';

      final response = await LicenseApiHttp.postJson(
        baseUrl: base,
        path: '/licenses/can',
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
      );

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
    final base = apiBaseUrl.trim();

    if (base.isNotEmpty && licencia != null && licencia.licenciaKey.trim().isNotEmpty) {
      try {
        final response = await LicenseApiHttp.postJson(
          baseUrl: base,
          path: '/licenses/upgrade-request',
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
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          backendRegistrado = true;
          try {
            final data = jsonDecode(response.body);
            if (data is Map<String, dynamic> && data['message'] is String) {
              backendMensaje = (data['message'] as String).trim();
            }
          } catch (_) {}
        }
      } catch (_) {
        backendRegistrado = false;
      }
    }

    const subject = 'Solicitud de mejora de plan - TiroAMG';
    final body = [
      'Hola,',
      '',
      'Quiero solicitar una actualización de plan.',
      '',
      'Licencia: ${licencia?.licenciaKey ?? 'N/D'}',
      'Plan actual: $currentPlan',
      'Plan requerido: $requiredPlan',
      'Función solicitada: $capability',
      'Device ID: $deviceId',
      'Plataforma: $_platformKey',
      'Versión app: ${package.version}+${package.buildNumber}',
    ].join('\n');

    final emailUri = Uri(
      scheme: 'mailto',
      path: 'info@albertomaestre.es',
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );

    final emailAbierto = await launchUrl(
      emailUri,
      mode: LaunchMode.externalApplication,
    );

    final message = backendRegistrado
        ? (backendMensaje.isNotEmpty
            ? '$backendMensaje\nSe ha abierto tu cliente de email para completar la solicitud.'
            : 'Solicitud registrada. Se ha abierto tu cliente de email para completar la solicitud.')
        : (emailAbierto
            ? 'Se ha abierto tu cliente de email para solicitar la actualización.'
            : 'No se pudo abrir el cliente de email. Escribe a info@albertomaestre.es.');

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

    const subject = 'Historial de solicitudes de mejora de plan - TiroAMG';
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
    LicenciaLocal licencia;
    try {
      licencia = await _ensureLocalDefaultInstallation();
    } catch (e) {
      return LicenciaCheckResult(
        esValida: true,
        enGraciaOffline: true,
        requiereActivacion: false,
        mensaje: 'Instalación local con limitaciones: $e',
        licencia: null,
      );
    }

    if (apiBaseUrl.trim().isEmpty) {
      return LicenciaCheckResult(
        esValida: true,
        enGraciaOffline: false,
        requiereActivacion: false,
        mensaje: 'Modo local (sin servidor). Módulo Inicio activo.',
        licencia: licencia,
      );
    }

    // En arranque normal no bloqueamos por red: solo sync si toca o forzamos.
    final ahora = DateTime.now().toUtc();
    final sinClave = licencia.licenciaKey.trim().isEmpty;
    final tocaValidar = forzarServidor ||
        sinClave ||
        licencia.proximaValidacion == null ||
        !licencia.proximaValidacion!.isAfter(ahora);

    if (!tocaValidar) {
      return _evaluarLicenciaLocal(licencia, huboErrorRed: false);
    }

    if (!forzarServidor && sinClave) {
      // Deja la UI libre; el sync forzado en background registrará.
      return LicenciaCheckResult(
        esValida: true,
        enGraciaOffline: true,
        requiereActivacion: false,
        mensaje: 'Pendiente de registro en servidor.',
        licencia: licencia,
      );
    }

    if (sinClave) {
      final reg = await registrarInstalacion();
      return LicenciaCheckResult(
        esValida: true,
        enGraciaOffline: !reg.esValida || reg.enGraciaOffline,
        requiereActivacion: false,
        mensaje: reg.mensaje,
        licencia: reg.licencia ?? await obtenerLicenciaLocal() ?? licencia,
      );
    }

    var huboErrorRed = false;
    try {
      licencia = await _validarEnServidor(licencia);
    } on _LicenseServerException catch (e) {
      if (e.statusCode >= 500) {
        huboErrorRed = true;
      } else if (e.statusCode == 404) {
        final reg = await registrarInstalacion();
        return LicenciaCheckResult(
          esValida: true,
          enGraciaOffline: false,
          requiereActivacion: false,
          mensaje: reg.mensaje,
          licencia: reg.licencia ?? await obtenerLicenciaLocal() ?? licencia,
        );
      } else if (e.statusCode == 403) {
        await _marcarLicenciaInvalidaEnLocal(licencia);
        // B+C: no tumbar la app; Inicio local sigue usable.
        final local = await obtenerLicenciaLocal() ?? licencia;
        return LicenciaCheckResult(
          esValida: true,
          enGraciaOffline: false,
          requiereActivacion: false,
          mensaje: 'Servidor indicó bloqueo; operando con módulos locales.',
          licencia: local.copyWithFeatures({
            ...LicenciaLocal.defaultModulesFeatures(),
            ...local.features,
            'inicio': true,
          }),
        );
      } else {
        huboErrorRed = true;
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

    return _evaluarLicenciaLocal(licencia, huboErrorRed: huboErrorRed);
  }

  /// Registro silencioso B+C (sin email).
  Future<LicenciaCheckResult> registrarInstalacion({
    String nombreApp = appName,
  }) async {
    var local = await _ensureLocalDefaultInstallation();
    final base = apiBaseUrl.trim();
    if (base.isEmpty) {
      return LicenciaCheckResult(
        esValida: true,
        enGraciaOffline: false,
        requiereActivacion: false,
        mensaje: 'Instalación local lista.',
        licencia: local,
      );
    }

    try {
      final package = await _packageInfoSafe();
      final deviceId = await _obtenerDeviceIdPersistente();
      final body = jsonEncode({
        'device_id': deviceId,
        'platform': _platformKey,
        'app_version': package?.version ?? '0.0.0',
        'build_number': package?.buildNumber ?? '0',
        'app_name': nombreApp,
        'app_id': nombreApp,
      });

      Future<http.Response> post(String path) {
        return LicenseApiHttp.postJson(
          baseUrl: base,
          path: path,
          body: body,
          timeout: const Duration(seconds: 8),
        );
      }

      var response = await post('/installations/register');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        response = await post('/licenses/register');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Último intento: request sin email (compat).
        response = await post('/licenses/request');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '[License] registro HTTP ${response.statusCode} → ${response.body}',
        );
        return LicenciaCheckResult(
          esValida: true,
          enGraciaOffline: true,
          requiereActivacion: false,
          mensaje: 'Sin registro en servidor. Operando con Inicio en local.',
          licencia: local,
        );
      }

      final data = jsonDecode(response.body);
      final payload = _normalizarPayloadLicencia(
        data,
        licenciaKey: '',
        deviceId: deviceId,
        mergeLocalMeta: local,
      );
      local = await _guardarPayloadLicencia(payload);
      debugPrint('[License] instalación registrada: ${local.licenciaKey}');
      return LicenciaCheckResult(
        esValida: true,
        enGraciaOffline: false,
        requiereActivacion: false,
        mensaje: 'Instalación registrada.',
        licencia: local,
      );
    } catch (e, st) {
      debugPrint('[License] registro falló: $e\n$st');
      return LicenciaCheckResult(
        esValida: true,
        enGraciaOffline: true,
        requiereActivacion: false,
        mensaje: 'Sin red. Operando con Inicio en local.',
        licencia: local,
      );
    }
  }

  Future<PackageInfo?> _packageInfoSafe() async {
    try {
      return await PackageInfo.fromPlatform()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  /// Asocia email opcional a la instalación.
  Future<LicenciaCheckResult> identificarEmail({
    required String email,
  }) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || !trimmed.contains('@')) {
      return const LicenciaCheckResult(
        esValida: false,
        enGraciaOffline: false,
        requiereActivacion: false,
        mensaje: 'Introduce un email válido.',
        licencia: null,
      );
    }

    var local = await _ensureLocalDefaultInstallation();
    final base = apiBaseUrl.trim();

    // Guarda email en local siempre.
    final meta = Map<String, dynamic>.from(local.features);
    meta['contact_email'] = trimmed;
    meta.remove('identify_snooze_until');
    meta['identify_never'] = false;
    local = await _guardarPayloadLicencia({
      ...local.toMap(),
      'features_json': jsonEncode(meta),
    });

    if (base.isEmpty) {
      return LicenciaCheckResult(
        esValida: true,
        enGraciaOffline: false,
        requiereActivacion: false,
        mensaje: 'Email guardado en local.',
        licencia: local,
      );
    }

    try {
      final package = await PackageInfo.fromPlatform();
      final deviceId = await _obtenerDeviceIdPersistente();
      final response = await LicenseApiHttp.postJson(
        baseUrl: base,
        path: '/installations/identify',
        body: jsonEncode({
          'device_id': deviceId,
          'app_name': appName,
          'app_id': appName,
          'email': trimmed,
          'platform': _platformKey,
          'app_version': package.version,
          'build_number': package.buildNumber,
          if (local.licenciaKey.trim().isNotEmpty)
            'license_key': local.licenciaKey.trim(),
        }),
        timeout: const Duration(seconds: 10),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return LicenciaCheckResult(
          esValida: true,
          enGraciaOffline: false,
          requiereActivacion: false,
          mensaje:
              'Email guardado localmente. El servidor no respondió (${response.statusCode}).',
          licencia: local,
        );
      }

      final data = jsonDecode(response.body);
      final payload = _normalizarPayloadLicencia(
        data,
        licenciaKey: local.licenciaKey,
        deviceId: deviceId,
        mergeLocalMeta: local,
      );
      // Conserva contact_email local.
      final features = jsonDecode(payload['features_json'] as String)
          as Map<String, dynamic>;
      features['contact_email'] = trimmed;
      payload['features_json'] = jsonEncode(features);
      local = await _guardarPayloadLicencia(payload);
      return LicenciaCheckResult(
        esValida: true,
        enGraciaOffline: false,
        requiereActivacion: false,
        mensaje: 'Instalación identificada.',
        licencia: local,
      );
    } catch (_) {
      return LicenciaCheckResult(
        esValida: true,
        enGraciaOffline: true,
        requiereActivacion: false,
        mensaje: 'Email guardado en local (sin red).',
        licencia: local,
      );
    }
  }

  /// Identificación obligatoria: sin email o sin privacidad aceptada.
  Future<bool> shouldShowIdentifyPrompt() async {
    final local = await obtenerLicenciaLocal();
    if (local == null) return true;
    return !local.puedeUsarApp;
  }

  Future<void> snoozeIdentifyPrompt({int days = 7}) async {
    final local = await _ensureLocalDefaultInstallation();
    final meta = Map<String, dynamic>.from(local.features);
    meta['identify_snooze_until'] =
        DateTime.now().toUtc().add(Duration(days: days)).toIso8601String();
    await _guardarPayloadLicencia({
      ...local.toMap(),
      'features_json': jsonEncode(meta),
    });
  }

  Future<void> neverAskIdentifyPrompt() async {
    final local = await _ensureLocalDefaultInstallation();
    final meta = Map<String, dynamic>.from(local.features);
    meta['identify_never'] = true;
    meta.remove('identify_snooze_until');
    await _guardarPayloadLicencia({
      ...local.toMap(),
      'features_json': jsonEncode(meta),
    });
  }

  /// Guarda la aceptación de la política de privacidad (versión + fecha UTC).
  Future<void> registrarAceptacionPrivacidad({
    required String version,
  }) async {
    final local = await _ensureLocalDefaultInstallation();
    final meta = Map<String, dynamic>.from(local.features);
    meta['privacy_accepted'] = true;
    meta['privacy_version'] = version;
    meta['privacy_accepted_at'] = DateTime.now().toUtc().toIso8601String();
    await _guardarPayloadLicencia({
      ...local.toMap(),
      'features_json': jsonEncode(meta),
    });
  }

  /// Guarda la aceptación de las condiciones de uso (versión + fecha UTC).
  Future<void> registrarAceptacionCondiciones({
    required String version,
  }) async {
    final local = await _ensureLocalDefaultInstallation();
    final meta = Map<String, dynamic>.from(local.features);
    meta['terms_accepted'] = true;
    meta['terms_version'] = version;
    meta['terms_accepted_at'] = DateTime.now().toUtc().toIso8601String();
    await _guardarPayloadLicencia({
      ...local.toMap(),
      'features_json': jsonEncode(meta),
    });
  }

  /// Aceptación conjunta de privacidad y condiciones (arranque / gate de uso).
  Future<void> registrarAceptacionLegal({
    required String privacyVersion,
    required String termsVersion,
  }) async {
    final local = await _ensureLocalDefaultInstallation();
    final meta = Map<String, dynamic>.from(local.features);
    final now = DateTime.now().toUtc().toIso8601String();
    meta['privacy_accepted'] = true;
    meta['privacy_version'] = privacyVersion;
    meta['privacy_accepted_at'] = now;
    meta['terms_accepted'] = true;
    meta['terms_version'] = termsVersion;
    meta['terms_accepted_at'] = now;
    await _guardarPayloadLicencia({
      ...local.toMap(),
      'features_json': jsonEncode(meta),
    });
  }

  Future<LicenciaLocal> _ensureLocalDefaultInstallation() async {
    final existing = await obtenerLicenciaLocal();
    if (existing != null) {
      // Asegura módulos por defecto si faltan.
      final features = Map<String, dynamic>.from(existing.features);
      var changed = false;
      if (!features.containsKey('inicio')) {
        features['inicio'] = true;
        changed = true;
      }
      if (!features.containsKey('target_shot_detection')) {
        features['target_shot_detection'] = false;
        changed = true;
      }
      if (changed) {
        return _guardarPayloadLicencia({
          ...existing.toMap(),
          'features_json': jsonEncode(features),
          if ((existing.estado).isEmpty || existing.estado == 'inactive')
            'estado': 'active',
        });
      }
      if (existing.estado.toLowerCase() == 'inactive' &&
          existing.licenciaKey.trim().isEmpty) {
        return _guardarPayloadLicencia({
          ...existing.toMap(),
          'estado': 'active',
        });
      }
      return existing;
    }

    final deviceId = await _obtenerDeviceIdPersistente();
    final now = DateTime.now().toUtc().toIso8601String();
    return _guardarPayloadLicencia({
      'id': 1,
      'license_key': '',
      'estado': 'active',
      'fecha_inicio': now,
      'fecha_fin': null,
      'plan': 'pro',
      'features_json': jsonEncode(LicenciaLocal.defaultModulesFeatures()),
      'device_id': deviceId,
      'ultima_validacion': now,
      'proxima_validacion': null,
      'dias_gracia_offline': 3,
      'max_dispositivos': 1,
      'firma': null,
    });
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

      final response = await LicenseApiHttp.postJson(
        baseUrl: base,
        path: '/licenses/activate',
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
        timeout: const Duration(seconds: 10),
      );

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
      final local = await obtenerLicenciaLocal();
      final payload = _normalizarPayloadLicencia(
        data,
        licenciaKey: key,
        deviceId: deviceId,
        mergeLocalMeta: local,
      );
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
    // Compat: ahora es identify + register.
    final email = identificadorUsuario.trim();
    final reg = await registrarInstalacion(
      nombreApp: nombreApp ?? appName,
    );
    if (email.isEmpty) return reg;
    return identificarEmail(email: email);
  }

  Future<LicenciaLocal> _validarEnServidor(LicenciaLocal local) async {
    final package = await PackageInfo.fromPlatform();
    final base = apiBaseUrl.trim();
    final deviceId = local.deviceId ?? await _obtenerDeviceIdPersistente();

    final body = <String, dynamic>{
      'device_id': deviceId,
      'app_name': appName,
      'app_id': appName,
      'platform': _platformKey,
      'app_version': package.version,
      'build_number': package.buildNumber,
    };
    if (local.licenciaKey.trim().isNotEmpty) {
      body['license_key'] = local.licenciaKey.trim();
    }

    Future<http.Response> post(String path) {
      return LicenseApiHttp.postJson(
        baseUrl: base,
        path: path,
        body: jsonEncode(body),
        timeout: const Duration(seconds: 10),
      );
    }

    var response = await post('/installations/validate');
    if (response.statusCode == 404) {
      response = await post('/licenses/validate');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _LicenseServerException(response.statusCode);
    }

    final data = jsonDecode(response.body);
    final payload = _normalizarPayloadLicencia(
      data,
      licenciaKey: local.licenciaKey,
      deviceId: deviceId,
      mergeLocalMeta: local,
    );
    return _guardarPayloadLicencia(payload);
  }

  Future<LicenciaLocal> _guardarPayloadLicencia(Map<String, dynamic> payload) async {
    final db = await DatabaseProvider.instance.database;

    // No permitir que un sync en vuelo borre aceptación legal ya guardada.
    final actual = await obtenerLicenciaLocal();
    if (actual != null) {
      Map<String, dynamic> features = {};
      final raw = payload['features_json']?.toString();
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            features = Map<String, dynamic>.from(decoded);
          } else if (decoded is Map) {
            features = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }
      for (final key in const [
        'privacy_accepted',
        'privacy_version',
        'privacy_accepted_at',
        'terms_accepted',
        'terms_version',
        'terms_accepted_at',
        'contact_email',
      ]) {
        final localVal = actual.features[key];
        if (localVal != null && !features.containsKey(key)) {
          features[key] = localVal;
        } else if (localVal == true && features[key] != true) {
          // Preferir "aceptado" local frente a un snapshot antiguo sin flags.
          features[key] = localVal;
        } else if (key == 'contact_email' &&
            (features[key] == null || features[key].toString().isEmpty) &&
            localVal != null &&
            localVal.toString().isNotEmpty) {
          features[key] = localVal;
        }
      }
      // Si local ya aceptó, mantener versiones/fechas locales si el payload no las trae.
      if (actual.privacyAccepted) {
        features['privacy_accepted'] = true;
        features['privacy_version'] ??= actual.features['privacy_version'];
        features['privacy_accepted_at'] ??= actual.features['privacy_accepted_at'];
      }
      if (actual.termsAccepted) {
        features['terms_accepted'] = true;
        features['terms_version'] ??= actual.features['terms_version'];
        features['terms_accepted_at'] ??= actual.features['terms_accepted_at'];
      }
      payload = Map<String, dynamic>.from(payload);
      payload['features_json'] = jsonEncode(features);
    }

    await db.insert(
      'Licencias',
      payload,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final guardada = await obtenerLicenciaLocal();
    if (guardada == null) {
      throw StateError('No se pudo persistir la instalación local.');
    }
    return guardada;
  }

  Map<String, dynamic> _normalizarPayloadLicencia(
    dynamic responseData, {
    required String licenciaKey,
    required String deviceId,
    LicenciaLocal? mergeLocalMeta,
  }) {
    final root = responseData is Map<String, dynamic> ? responseData : const {};
    final lic = root['license'] is Map<String, dynamic>
        ? root['license'] as Map<String, dynamic>
        : root;
    final nowUtc = DateTime.now().toUtc();
    final serverNow = DateTime.tryParse(
                (root['server_time'] ?? lic['server_time'] ?? '').toString())
            ?.toUtc() ??
        nowUtc;
    final nextValidation = serverNow.add(const Duration(hours: 12));

    final features = <String, dynamic>{
      ...LicenciaLocal.defaultModulesFeatures(),
    };

    final rawFeatures = lic['features'];
    if (rawFeatures is Map) {
      features.addAll(Map<String, dynamic>.from(rawFeatures));
    }
    final rawModules = lic['modules'];
    if (rawModules is Map) {
      features.addAll(Map<String, dynamic>.from(rawModules));
    }

    // Conserva meta local (email / snooze / aceptaciones legales).
    if (mergeLocalMeta != null) {
      final email = mergeLocalMeta.contactEmail;
      if (email != null) features['contact_email'] = email;
      if (mergeLocalMeta.identifyNeverAsk) {
        features['identify_never'] = true;
      }
      final snooze = mergeLocalMeta.identifySnoozeUntil;
      if (snooze != null) {
        features['identify_snooze_until'] = snooze.toIso8601String();
      }
      final localFeatures = mergeLocalMeta.features;
      for (final key in const [
        'privacy_accepted',
        'privacy_version',
        'privacy_accepted_at',
        'terms_accepted',
        'terms_version',
        'terms_accepted_at',
      ]) {
        if (localFeatures.containsKey(key)) {
          features[key] = localFeatures[key];
        }
      }
    }

    final remoteEmail = lic['email']?.toString().trim();
    if (remoteEmail != null && remoteEmail.isNotEmpty) {
      features['contact_email'] = remoteEmail;
    }

    return {
      'id': 1,
      'license_key': lic['license_key']?.toString().trim().isNotEmpty == true
          ? lic['license_key'].toString().trim()
          : licenciaKey.trim(),
      'estado': (lic['status'] ?? lic['estado'] ?? 'active').toString(),
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
        mensaje: 'Instalación deshabilitada ($estado).',
        licencia: local,
      );
    }

    final fechaFin = local.fechaFin;
    if ((estado == 'active' || estado == 'inactive') &&
        (fechaFin == null || !fechaFin.isBefore(now))) {
      // inactive sin bloqueo duro: en B+C tratamos como usable si no está revoked.
      return LicenciaCheckResult(
        esValida: true,
        enGraciaOffline: false,
        requiereActivacion: false,
        mensaje: local.hasDeteccionAutomatica
            ? 'Instalación activa (Inicio + Detección automática).'
            : 'Instalación activa (módulo Inicio).',
        licencia: local.copyWithFeatures({
          ...local.features,
          'inicio': local.hasInicioModule,
          'target_shot_detection': local.hasDeteccionAutomatica,
        }),
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
          mensaje: 'Sin red. Operando con la última configuración de módulos.',
          licencia: local,
        );
      }
    }

    // Caducada: en B+C seguimos dejando Inicio local.
    return LicenciaCheckResult(
      esValida: true,
      enGraciaOffline: huboErrorRed,
      requiereActivacion: false,
      mensaje: huboErrorRed
          ? 'Sin red. Operando con Inicio en local.'
          : 'Instalación usable (Inicio).',
      licencia: local,
    );
  }

  Future<String> _obtenerDeviceIdPersistente() async {
    final db = await DatabaseProvider.instance.database;
    final rows = await db.query('Licencias', columns: ['device_id'], where: 'id = 1', limit: 1);
    final existing = rows.isNotEmpty ? rows.first['device_id']?.toString() : null;
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _generarDeviceId();
    if (rows.isNotEmpty) {
      await db.update(
        'Licencias',
        {'device_id': generated},
        where: 'id = ?',
        whereArgs: const [1],
      );
    } else {
      await db.insert(
        'Licencias',
        {
          'id': 1,
          'license_key': '',
          'estado': 'active',
          'device_id': generated,
          'features_json': jsonEncode(LicenciaLocal.defaultModulesFeatures()),
          'ultima_validacion': null,
          'proxima_validacion': null,
        },
      );
    }
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
