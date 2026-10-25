import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../help/privacy_content.dart';
import '../help/terms_content.dart';

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

  static String get apiBaseUrl {
    for (final c in [_apiAuth, _apiInstall, _apiLicense]) {
      final t = c.trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  static bool get isConfigured => apiBaseUrl.isNotEmpty;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String?> token() async => (await _prefs).getString(_kToken);

  Future<String?> username() async => (await _prefs).getString(_kUsername);

  Future<String?> status() async => (await _prefs).getString(_kStatus);

  Future<bool> hasSession() async {
    final t = await token();
    return t != null && t.isNotEmpty;
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
      final body = {
        'username': username.trim(),
        'password': password,
        'app_id': appId,
        'device_id': id,
        'platform': _platformKey,
        'app_version': package.version,
        'build_number': package.buildNumber,
        'privacy_current_version': privacyPolicyVersion,
        'terms_current_version': termsVersion,
      };
      final response = await _post('/app-auth/login', body);
      final data = _decode(response.body);
      final account = data['account'];
      final status = account is Map ? account['status']?.toString() : null;

      if (response.statusCode == 403 && status == 'pending') {
        final p = await _prefs;
        await p.setString(_kUsername, username.trim());
        await p.setString(_kStatus, 'pending');
        await p.remove(_kToken);
        return AppAuthResult(
          ok: false,
          pending: true,
          message: data['message']?.toString() ?? 'Pendiente de aprobación.',
        );
      }

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['token'] != null) {
        final p = await _prefs;
        await p.setString(_kToken, data['token'].toString());
        await p.setString(_kUsername, username.trim());
        await p.setString(_kStatus, status ?? 'active');
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
      return AppAuthResult(ok: false, message: e.toString());
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
    if (t != null && isConfigured) {
      try {
        await _post(
          '/app-auth/logout',
          {},
          bearer: t,
        );
      } catch (_) {}
    }
    final p = await _prefs;
    await p.remove(_kToken);
    await p.remove(_kStatus);
  }

  Future<String?> lastRecoveryCode() async =>
      (await _prefs).getString(_kRecoveryShown);

  Future<http.Response> _post(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    final base = apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (bearer != null) 'Authorization': 'Bearer $bearer',
    };
    return http
        .post(
          Uri.parse('$base$path'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
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
    this.message,
    this.recoveryCode,
  });

  final bool ok;
  final bool skipped;
  final bool pending;
  final bool needsLegal;
  final String? message;
  final String? recoveryCode;
}
