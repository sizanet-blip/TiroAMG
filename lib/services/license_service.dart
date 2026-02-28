import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqflite.dart';

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

  String _mensajeServidorAmigable(int statusCode, {required String contexto}) {
    if (statusCode == 400) {
      if (contexto == 'request') {
        return 'Faltan datos para solicitar la licencia.';
      }
      if (contexto == 'activate') {
        return 'Faltan datos para activar la licencia.';
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
