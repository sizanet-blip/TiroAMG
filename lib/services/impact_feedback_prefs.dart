import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias de sonido y vibración al registrar impactos en la diana.
class ImpactFeedbackPrefs {
  ImpactFeedbackPrefs._();

  static const String keySonidoImpacto = 'impact_feedback_sound_enabled';
  static const String keyVibracionImpacto = 'impact_feedback_haptic_enabled';

  /// Por defecto desactivado (galería / competición).
  static Future<bool> sonidoHabilitado() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(keySonidoImpacto) ?? false;
  }

  static Future<void> setSonidoHabilitado(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(keySonidoImpacto, value);
  }

  /// Por defecto activado.
  static Future<bool> vibracionHabilitada() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(keyVibracionImpacto) ?? true;
  }

  static Future<void> setVibracionHabilitada(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(keyVibracionImpacto, value);
  }
}
