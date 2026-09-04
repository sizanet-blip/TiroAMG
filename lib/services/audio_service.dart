import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plantilla_tiempos_model.dart';

/// Competición = árbitro (pitidos + color). Entrenamiento = pitidos + voz.
enum AvisoTiroPerfil { competicion, entrenamiento }

class AudioService {
  static final AudioService instance = AudioService._internal();
  factory AudioService() => instance;
  AudioService._internal();

  static const _prefsPerfil = 'aviso_tiro_perfil';
  static const _prefsMute = 'aviso_tiro_mute';
  static const _prefsVolumen = 'aviso_tiro_volumen';
  static const _prefsVibracion = 'aviso_tiro_vibracion';
  static const _prefsAutoPerfil = 'aviso_tiro_auto_perfil';
  static const _prefsPerfilManual = 'aviso_tiro_perfil_manual';

  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _beepPlayer = AudioPlayer();

  AvisoTiroPerfil _perfil = AvisoTiroPerfil.competicion;
  bool _mute = false;
  double _volumen = 1.0;
  bool _vibracion = true;
  bool _autoPerfil = true;
  bool _perfilManual = false;
  bool _listo = false;

  AvisoTiroPerfil get perfil => _perfil;
  bool get vozEntrenadorActiva =>
      !_mute && _perfil == AvisoTiroPerfil.entrenamiento;
  bool get mute => _mute;
  double get volumen => _volumen;
  bool get vibracion => _vibracion;
  bool get autoPerfil => _autoPerfil;
  bool get perfilManual => _perfilManual;

  Future<void> init() async {
    if (_listo) {
      await _aplicarVolumen();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsPerfil);
    _perfil = raw == AvisoTiroPerfil.entrenamiento.name
        ? AvisoTiroPerfil.entrenamiento
        : AvisoTiroPerfil.competicion;
    _mute = prefs.getBool(_prefsMute) ?? false;
    _volumen = (prefs.getDouble(_prefsVolumen) ?? 1.0).clamp(0.0, 1.0);
    _vibracion = prefs.getBool(_prefsVibracion) ?? true;
    _autoPerfil = prefs.getBool(_prefsAutoPerfil) ?? true;
    _perfilManual = prefs.getBool(_prefsPerfilManual) ?? false;

    await _flutterTts.setLanguage('es-ES');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);

    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Audio] AudioContext: $e');
    }

    await _beepPlayer.setReleaseMode(ReleaseMode.stop);
    await _aplicarVolumen();
    _listo = true;
  }

  Future<void> _aplicarVolumen() async {
    final v = _mute ? 0.0 : _volumen;
    await _beepPlayer.setVolume(v);
    await _flutterTts.setVolume(v);
  }

  /// [manual] true si lo elige el usuario (Config / icono sesión):
  /// no lo pisa el perfil automático hasta reactivar auto.
  Future<void> setPerfil(
    AvisoTiroPerfil perfil, {
    bool manual = true,
  }) async {
    _perfil = perfil;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPerfil, perfil.name);
    if (manual) {
      _perfilManual = true;
      await prefs.setBool(_prefsPerfilManual, true);
    }
  }

  Future<void> togglePerfil() async {
    await setPerfil(
      _perfil == AvisoTiroPerfil.competicion
          ? AvisoTiroPerfil.entrenamiento
          : AvisoTiroPerfil.competicion,
      manual: true,
    );
  }

  Future<void> setMute(bool value) async {
    _mute = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsMute, value);
    await _aplicarVolumen();
  }

  Future<void> toggleMute() => setMute(!_mute);

  Future<void> setVolumen(double value) async {
    _volumen = value.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsVolumen, _volumen);
    await _aplicarVolumen();
  }

  Future<void> setVibracion(bool value) async {
    _vibracion = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsVibracion, value);
  }

  Future<void> setAutoPerfil(bool value) async {
    _autoPerfil = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAutoPerfil, value);
    if (value) {
      // Reactivar auto: vuelve a permitir sugerencias por tipo de serie.
      _perfilManual = false;
      await prefs.setBool(_prefsPerfilManual, false);
    }
  }

  /// Duelo → Competición; precisión larga (≥2 min) → Entrenamiento.
  /// No aplica si el usuario eligió perfil a mano (hasta reactivar auto).
  Future<AvisoTiroPerfil> aplicarAutoPerfilSiProcede(
    PlantillaTiempos plantilla,
  ) async {
    await init();
    if (!_autoPerfil || _perfilManual) return _perfil;
    final sugerido = plantilla.esDuel
        ? AvisoTiroPerfil.competicion
        : (plantilla.tiempoExposicion >= 120
            ? AvisoTiroPerfil.entrenamiento
            : AvisoTiroPerfil.competicion);
    if (sugerido != _perfil) {
      await setPerfil(sugerido, manual: false);
    }
    return _perfil;
  }

  Future<void> _haptico(void Function() fn) async {
    if (!_vibracion || _mute) return;
    fn();
  }

  /// Señal de preparación / cargar (doble tono medio).
  Future<void> senalPreparacion() async {
    await _playAsset('sounds/prep1.wav', waitMs: 220);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await _playAsset('sounds/prep2.wav', waitMs: 220);
    await _haptico(HapticFeedback.selectionClick);
    if (vozEntrenadorActiva) await _hablar('Preparación. Cargar.');
  }

  /// Señal de atención (tono agudo).
  Future<void> senalAtencion() async {
    await _playAsset('sounds/atencion.wav', waitMs: 300);
    await _haptico(HapticFeedback.mediumImpact);
    if (vozEntrenadorActiva) await _hablar('Atención.');
  }

  /// Pitido de fuego (puede anticiparse ~100 ms antes del verde).
  Future<void> senalFuegoPitido() async {
    await _playAsset('sounds/fuego.wav', waitMs: 200);
  }

  /// Señal de fuego completa (pitido + háptico + voz opcional).
  Future<void> senalFuego({bool omitirPitido = false}) async {
    if (!omitirPitido) await senalFuegoPitido();
    await _haptico(HapticFeedback.heavyImpact);
    if (vozEntrenadorActiva) {
      await _flutterTts.setSpeechRate(0.6);
      await _hablar('¡YA!');
      await _flutterTts.setSpeechRate(0.5);
    }
  }

  /// Fin de serie / alto (doble tono grave descendente).
  Future<void> senalAlto({bool serieTerminada = false}) async {
    await _playAsset('sounds/alto1.wav', waitMs: 180);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _playAsset('sounds/alto2.wav', waitMs: 340);
    await _haptico(HapticFeedback.mediumImpact);
    if (vozEntrenadorActiva) {
      if (serieTerminada) {
        await _hablar('Serie terminada.');
      } else {
        await _hablar('Alto. Descargar.');
      }
    }
  }

  /// Tick de cuenta atrás final (10/5/3/2/1).
  Future<void> senalTickFinal({bool urgente = false}) async {
    await _playAsset(
      urgente ? 'sounds/warn.wav' : 'sounds/tick.wav',
      waitMs: urgente ? 100 : 80,
    );
    await _haptico(HapticFeedback.selectionClick);
  }

  Future<void> decirTiempo(int segundos) async {
    if (!vozEntrenadorActiva) return;
    await _hablar('$segundos segundos.');
  }

  Future<void> probarSenalFuego() => senalFuego();

  Future<void> _hablar(String texto) async {
    if (_mute) return;
    await _flutterTts.speak(texto);
  }

  Future<void> _playAsset(String assetPath, {required int waitMs}) async {
    if (_mute) return;
    try {
      await _beepPlayer.stop();
      await _beepPlayer.play(AssetSource(assetPath));
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    } catch (e) {
      debugPrint('[Audio] beep falló ($assetPath): $e');
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {
        await SystemSound.play(SystemSoundType.click);
      }
    }
  }

  void stop() {
    _flutterTts.stop();
    _beepPlayer.stop();
  }

  Future<void> dispose() async {
    stop();
    await _beepPlayer.dispose();
  }
}
