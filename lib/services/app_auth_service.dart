import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../help/privacy_content.dart';
import '../help/terms_content.dart';
import 'license_api_http.dart';
import 'license_service.dart';
import 'local_unlock_service.dart';

/// Auth unificado AMG (panel Yii2 `/app-auth/*`).
class AppAuthService {
  AppAuthService();

  static const String appId = 'TiroAMG';
  static String get privacyPolicyVersion => PrivacyContent.acceptanceVersion;
  static String get termsVersion => TermsContent.acceptanceVersion;

  static const String _apiAuth = String.fromEnvironment(
    'APP_AUTH_API_URL',
    defaultValue: '',
  );
  static const String _apiInstall = String.fromEnvironment(
    'INSTALLATION_API_URL',
    defaultValue: '',
  );
  static const String _apiLicense = String.fromEnvironment(
    'LICENSE_API_URL',
    defaultValue: '',
  );

  static const _kToken = 'app_auth_token';
  static const _kUsername = 'app_auth_username';
  static const _kStatus = 'app_auth_status';
  static const _kDeviceId = 'app_auth_device_id';
  static const _kRecoveryShown = 'app_auth_recovery_code';

  /// Token solo en memoria: al cerrar la app se pierde y hay que volver a entrar.
  static String? _sessionToken;

  static bool _offlineUnlockNotice = false;

  final LocalUnlockService _unlock = LocalUnlockService();

  static bool takeOfflineUnlockNotice() {
    final pending = _offlineUnlockNotice;
    _offlineUnlockNotice = false;
    return pending;
  }

  static String get apiBaseUrl {
    for (final c in [_apiAuth, _apiInstall, _apiLicense]) {
      final t = c.trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  static bool get isConfigured => apiBaseUrl.isNotEmpty;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// Elimina tokens antiguos guardados en disco (versiones previas).
  static Future<void> discardPersistedSession() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    _sessionToken = null;
  }

  Future<String?> token() async => _sessionToken;

  Future<String?> username() async => (await _prefs).getString(_kUsername);

  Future<String?> status() async => (await _prefs).getString(_kStatus);

  Future<bool> hasSession() async {
    final t = await token();
    return t != null && t.isNotEmpty;
  }

  Future<void> _setSessionToken(String? value) async {
    _sessionToken = value;
    // Nunca persistir: al matar el proceso debe pedir acceso otra vez.
    final p = await _prefs;
    await p.remove(_kToken);
  }

  Future<String> deviceId() async {
    final p = await _prefs;
    final existing = p.getString(_kDeviceId)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = _generateDeviceId();
    await p.setString(_kDeviceId, generated);
    return generated;
  }

  Future<AppAuthResult> register({
    required String username,
    required String password,
    String? email,
    required bool acceptedLegal,
  }) async {
    if (!acceptedLegal) {
      return const AppAuthResult(
        ok: false,
        message: 'Debes aceptar privacidad y condiciones.',
      );
    }
    if (!isConfigured) {
      return const AppAuthResult(
        ok: false,
        skipped: true,
        message: 'API no configurada.',
      );
    }

    try {
      final package = await PackageInfo.fromPlatform();
      final id = await deviceId();
      final body = {
        'username': username.trim(),
        'password': password,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        'app_id': appId,
        'device_id': id,
        'platform': _platformKey,
        'app_version': package.version,
        'build_number': package.buildNumber,
        'privacy_accepted_version': privacyPolicyVersion,
        'terms_accepted_version': termsVersion,
      };
      final response = await _post('/app-auth/register', body);
      final data = _decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final recovery = data['recovery_code']?.toString();
        final account = data['account'];
        final status = account is Map
            ? account['status']?.toString()
            : 'pending';
        final p = await _prefs;
        await p.setString(_kUsername, username.trim());
        await p.setString(_kStatus, status ?? 'pending');
        if (recovery != null && recovery.isNotEmpty) {
          await p.setString(_kRecoveryShown, recovery);
        }
        // Evita el diálogo legal duplicado al entrar en Home.
        await _syncLocalLegalAcceptance(email: email);
        return AppAuthResult(
          ok: true,
          pending: status == 'pending',
          message: data['message']?.toString() ?? 'Solicitud enviada.',
          recoveryCode: recovery,
        );
      }
      return AppAuthResult(
        ok: false,
        message: data['message']?.toString() ??
            'Error ${response.statusCode}',
      );
    } catch (e) {
      return AppAuthResult(ok: false, message: e.toString());
    }
  }

  Future<AppAuthResult> login({
    required String username,
    required String password,
    bool acceptedLegal = false,
  }) async {
    if (!isConfigured) {
      return const AppAuthResult(
        ok: false,
        skipped: true,
        message: 'API no configurada.',
      );
    }
    try {
      final package = await PackageInfo.fromPlatform();
      final id = await deviceId();
      // Si ya se aceptó en esta instalación (o el usuario marca el checkbox),
      // reenviamos las versiones al panel: el login 428 no se resuelve solo
      // con privacy_current_version.
      final sendAcceptance =
          acceptedLegal || await hasLocalLegalAcceptance();
      final body = <String, dynamic>{
        'username': username.trim(),
        'password': password,
        'app_id': appId,
        'device_id': id,
        'platform': _platformKey,
        'app_version': package.version,
        'build_number': package.buildNumber,
        'privacy_current_version': privacyPolicyVersion,
        'terms_current_version': termsVersion,
        if (sendAcceptance) ...{
          'privacy_accepted_version': privacyPolicyVersion,
          'terms_accepted_version': termsVersion,
        },
      };
      final offlineReady = await _unlock.verify(
            username: username,
            password: password,
          ) ==
          LocalUnlockVerdict.ok;
      final response = await _post(
        '/app-auth/login',
        body,
        timeout: offlineReady
            ? const Duration(seconds: 4)
            : const Duration(seconds: 12),
      );
      final data = _decode(response.body);
      final account = data['account'];
      final status = account is Map ? account['status']?.toString() : null;

      if (response.statusCode == 403) {
        await _unlock.clear();
        if (status == 'pending') {
          final p = await _prefs;
          await p.setString(_kUsername, username.trim());
          await p.setString(_kStatus, 'pending');
          await _setSessionToken(null);
          return AppAuthResult(
            ok: false,
            pending: true,
            message: data['message']?.toString() ?? 'Pendiente de aprobación.',
          );
        }
        return AppAuthResult(
          ok: false,
          message: data['message']?.toString() ?? 'Tu cuenta no puede entrar.',
          status: status,
        );
      }

      if (response.statusCode == 401) {
        if (await _unlock.matchesPassword(
              username: username,
              password: password,
            ) ==
            true) {
          await _unlock.clear();
        }
        return AppAuthResult(
          ok: false,
          message: data['message']?.toString() ?? 'Usuario o contraseña incorrectos.',
        );
      }

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['token'] != null) {
        final p = await _prefs;
        await _setSessionToken(data['token'].toString());
        await p.setString(_kUsername, username.trim());
        await p.setString(_kStatus, status ?? 'active');
        await _syncLocalLegalAcceptance();
        await _unlock.save(username: username, password: password);
        return AppAuthResult(
          ok: true,
          message: data['message']?.toString() ?? 'Login correcto.',
        );
      }

      return AppAuthResult(
        ok: false,
        needsLegal: response.statusCode == 428,
        message: data['message']?.toString() ??
            'Error ${response.statusCode}',
      );
    } catch (e) {
      if (_isNetworkError(e)) {
        return _loginOffline(username: username, password: password);
      }
      return AppAuthResult(ok: false, message: e.toString());
    }
  }

  Future<AppAuthResult> _loginOffline({
    required String username,
    required String password,
  }) async {
    final verdict = await _unlock.verify(username: username, password: password);
    switch (verdict) {
      case LocalUnlockVerdict.ok:
        final p = await _prefs;
        await p.setString(_kUsername, username.trim());
        await p.setString(_kStatus, 'active');
        await _setSessionToken(null);
        _offlineUnlockNotice = true;
        return const AppAuthResult(
          ok: true,
          offline: true,
          message:
              'Sin conexión. Acceso con los datos de este dispositivo.',
        );
      case LocalUnlockVerdict.expired:
        return const AppAuthResult(
          ok: false,
          offline: true,
          message:
              'Sin conexión y hace más de 14 días que no se comprueba la cuenta. Conéctate para entrar.',
        );
      case LocalUnlockVerdict.mismatch:
        return const AppAuthResult(
          ok: false,
          offline: true,
          message: 'Usuario o contraseña incorrectos.',
        );
      case LocalUnlockVerdict.missing:
        return const AppAuthResult(
          ok: false,
          offline: true,
          message:
              'Sin conexión. La primera vez necesitas internet para identificarte.',
        );
    }
  }

  /// Con red, confirma que la cuenta sigue activa. `true` si hay que salir.
  Future<bool> refreshAccountOrRevoke() async {
    final user = await username();
    if (user == null || user.isEmpty) return false;
    final r = await checkStatus(username: user);
    if (r.networkError || r.status == null || r.status!.isEmpty) return false;
    final blocked = r.status == 'blocked' ||
        r.status == 'rejected' ||
        r.status == 'pending';
    final noAccess = r.status == 'active' && r.hasAppAccess == false;
    if (blocked || noAccess) {
      await _unlock.clear();
      await logout();
      return true;
    }
    if (r.status == 'active') {
      await _unlock.touch();
    }
    return false;
  }

  /// ¿Privacidad + condiciones ya aceptadas en local para la versión actual?
  Future<bool> hasLocalLegalAcceptance() async {
    try {
      const license = LicenseService();
      final local = await license.obtenerLicenciaLocal();
      if (local == null || !local.puedeUsarApp) return false;
      final pv = local.features['privacy_version']?.toString();
      final tv = local.features['terms_version']?.toString();
      final privacyOk = pv == PrivacyContent.version ||
          pv == PrivacyContent.acceptanceVersion;
      final termsOk = tv == TermsContent.version ||
          tv == TermsContent.acceptanceVersion;
      return privacyOk && termsOk;
    } catch (_) {
      return false;
    }
  }

  /// Consulta si la solicitud ya fue aprobada (sin contraseña).
  Future<AppAuthResult> checkStatus({required String username}) async {
    if (!isConfigured) {
      return const AppAuthResult(ok: false, message: 'API no configurada.');
    }
    try {
      final response = await _post('/app-auth/status', {
        'username': username.trim(),
        'app_id': appId,
      });
      final data = _decode(response.body);
      final status = data['status']?.toString();
      if (status != null && status.isNotEmpty) {
        await (await _prefs).setString(_kStatus, status);
      }
      return AppAuthResult(
        ok: response.statusCode >= 200 && response.statusCode < 300,
        pending: status == 'pending',
        message: data['message']?.toString() ?? 'Estado desconocido.',
        status: status,
        hasAppAccess: data['has_app_access'] is bool
            ? data['has_app_access'] as bool
            : null,
      );
    } catch (e) {
      return AppAuthResult(
        ok: false,
        networkError: _isNetworkError(e),
        message: e.toString(),
      );
    }
  }

  Future<AppAuthResult> recover({
    required String username,
    required String recoveryCode,
    required String newPassword,
  }) async {
    if (!isConfigured) {
      return const AppAuthResult(ok: false, message: 'API no configurada.');
    }
    try {
      final response = await _post('/app-auth/recover', {
        'username': username.trim(),
        'recovery_code': recoveryCode.trim(),
        'new_password': newPassword,
      });
      final data = _decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final recovery = data['recovery_code']?.toString();
        if (recovery != null) {
          await (await _prefs).setString(_kRecoveryShown, recovery);
        }
        await _unlock.updatePasswordIfPresent(
          username: username,
          password: newPassword,
        );
        return AppAuthResult(
          ok: true,
          message: data['message']?.toString() ?? 'Contraseña actualizada.',
          recoveryCode: recovery,
        );
      }
      return AppAuthResult(
        ok: false,
        message: data['message']?.toString() ?? 'Error',
      );
    } catch (e) {
      return AppAuthResult(ok: false, message: e.toString());
    }
  }

  Future<void> logout() async {
    final t = await token();
    // Cierra la sesión en pantalla, pero conserva el acceso local de 14 días.
    await _setSessionToken(null);

    if (t != null && isConfigured) {
      try {
        await _post(
          '/app-auth/logout',
          {},
          bearer: t,
        ).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  }

  Future<String?> lastRecoveryCode() async =>
      (await _prefs).getString(_kRecoveryShown);

  /// Marca privacidad/condiciones en la instalación local (mismo gate que Home).
  Future<void> _syncLocalLegalAcceptance({String? email}) async {
    try {
      const license = LicenseService();
      await license.registrarAceptacionLegal(
        privacyVersion: PrivacyContent.version,
        termsVersion: TermsContent.version,
      );
      final trimmed = email?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        await license.identificarEmail(email: trimmed);
      }
    } catch (e) {
      debugPrint('[AppAuth] sync legal local: $e');
    }
  }

  Future<http.Response> _post(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    // En Android + *.desarrollo usa el puente 10.0.2.2 (el emulador no resuelve hosts de Windows).
    return LicenseApiHttp.postJson(
      baseUrl: apiBaseUrl,
      path: path,
      body: jsonEncode(body),
      headers: {
        if (bearer != null) 'Authorization': 'Bearer $bearer',
      },
      timeout: timeout,
    );
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('[AppAuth] decode: $e');
    }
    return {};
  }

  String _generateDeviceId() {
    final rnd = Random.secure();
    final randomPart =
        List.generate(24, (_) => rnd.nextInt(16).toRadixString(16)).join();
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    return 'tdamg-auth-$ts-$randomPart';
  }

  bool _isNetworkError(Object e) {
    return e is SocketException ||
        e is TimeoutException ||
        e is http.ClientException ||
        e is HandshakeException ||
        e is TlsException ||
        e is HttpException;
  }

  String get _platformKey {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}

class AppAuthResult {
  const AppAuthResult({
    required this.ok,
    this.skipped = false,
    this.pending = false,
    this.needsLegal = false,
    this.offline = false,
    this.networkError = false,
    this.message,
    this.recoveryCode,
    this.status,
    this.hasAppAccess,
  });

  final bool ok;
  final bool skipped;
  final bool pending;
  final bool needsLegal;
  final bool offline;
  final bool networkError;
  final String? message;
  final String? recoveryCode;
  final String? status;
  final bool? hasAppAccess;
}
