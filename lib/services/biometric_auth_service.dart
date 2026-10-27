import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricAuthResult {
  const BiometricAuthResult({
    this.credentials,
    this.errorMessage,
  });

  final ({String username, String password})? credentials;
  final String? errorMessage;

  bool get ok => credentials != null;
}

/// Huella / biometría para la pantalla de acceso AMG.
class BiometricAuthService {
  BiometricAuthService();

  static const _kEnabled = 'app_auth_biometric_enabled';
  static const _kUser = 'app_auth_biometric_user';
  static const _kPass = 'app_auth_biometric_pass';

  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<bool> get isSupported async {
    if (kIsWeb) return false;
    if (!(Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows)) {
      return false;
    }
    try {
      final device = await _auth.isDeviceSupported();
      final canBio = await _auth.canCheckBiometrics;
      return device || canBio;
    } catch (_) {
      return false;
    }
  }

  /// Hay al menos una huella / Face ID registrada en el sistema.
  Future<bool> get hasEnrolledBiometrics async {
    try {
      final list = await _auth.getAvailableBiometrics();
      return list.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) == true;
  }

  Future<String?> savedUsername() async {
    if (!await isEnabled) return null;
    return _secure.read(key: _kUser);
  }

  Future<bool> enable({
    required String username,
    required String password,
  }) async {
    if (!await isSupported) return false;
    if (!await hasEnrolledBiometrics) return false;
    final prefs = await SharedPreferences.getInstance();
    await _secure.write(key: _kUser, value: username.trim());
    await _secure.write(key: _kPass, value: password);
    await prefs.setBool(_kEnabled, true);
    return true;
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, false);
    await _secure.delete(key: _kUser);
    await _secure.delete(key: _kPass);
  }

  /// Pide huella/Face ID. Si OK, devuelve usuario+contraseña guardados.
  Future<BiometricAuthResult> authenticateAndLoadCredentials({
    String reason = 'Identifícate para entrar en TiroAMG',
  }) async {
    if (!await isEnabled) {
      return const BiometricAuthResult(
        errorMessage:
            'La huella no está activada. Entra con tu contraseña y actívala cuando te lo pida.',
      );
    }
    if (!await isSupported) {
      return const BiometricAuthResult(
        errorMessage:
            'Este dispositivo no admite huella o desbloqueo biométrico.',
      );
    }
    if (!await hasEnrolledBiometrics) {
      return const BiometricAuthResult(
        errorMessage:
            'No hay ninguna huella configurada en el teléfono. Añádela en Ajustes → Seguridad y vuelve a intentarlo.',
      );
    }

    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!ok) {
        return const BiometricAuthResult(
          errorMessage: 'No se ha podido verificar la huella. Prueba otra vez o usa la contraseña.',
        );
      }
    } on PlatformException catch (e) {
      return BiometricAuthResult(errorMessage: _friendlyPlatformError(e));
    } catch (_) {
      return const BiometricAuthResult(
        errorMessage:
            'No se ha podido usar la huella ahora mismo. Entra con tu contraseña.',
      );
    }

    final user = await _secure.read(key: _kUser);
    final pass = await _secure.read(key: _kPass);
    if (user == null || user.isEmpty || pass == null || pass.isEmpty) {
      await disable();
      return const BiometricAuthResult(
        errorMessage:
            'Faltan los datos guardados para la huella. Entra con la contraseña y vuelve a activarla.',
      );
    }
    return BiometricAuthResult(credentials: (username: user, password: pass));
  }

  String _friendlyPlatformError(PlatformException e) {
    final code = (e.code).toLowerCase();
    final message = (e.message ?? '').toLowerCase();

    if (code.contains('notavailable') ||
        code.contains('not_available') ||
        message.contains('not available') ||
        message.contains('security credentials')) {
      return 'No hay huella configurada en este teléfono (o el emulador no tiene huella). '
          'Configúrala en Ajustes → Seguridad o entra con tu contraseña.';
    }
    if (code.contains('notenrolled') || message.contains('no biometrics')) {
      return 'Aún no has registrado ninguna huella en el teléfono. Añádela en Ajustes y vuelve a probar.';
    }
    if (code.contains('lockedout') || code.contains('permanentlylockedout')) {
      return 'Demasiados intentos fallidos. Desbloquea el teléfono con el PIN y prueba más tarde.';
    }
    if (code.contains('canceled') || code.contains('user')) {
      return 'Has cancelado la huella. Puedes entrar con tu contraseña.';
    }
    return 'No se ha podido usar la huella. Entra con tu contraseña.';
  }
}
