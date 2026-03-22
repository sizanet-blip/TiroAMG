import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../utils/impact_wav_bytes.dart';

/// Reproduce un clic corto en altavoz (funciona en Windows; `SystemSound` no).
class ImpactSoundPlayer {
  ImpactSoundPlayer._();

  static final AudioPlayer _player = AudioPlayer();
  static Uint8List? _bytesClick;
  static Uint8List? _bytesAlert;

  /// [entradaManual] y acierto en diana → tono agudo corto; [esFuera] → tono grave más largo.
  static Future<void> play({
    required bool esFuera,
    required bool entradaManual,
  }) async {
    final useAlert = !entradaManual && esFuera;
    final bytes = useAlert
        ? (_bytesAlert ??= buildImpactWavBytes(
            frequencyHz: 380,
            durationMs: 130,
          ))
        : (_bytesClick ??= buildImpactWavBytes(
            frequencyHz: 1450,
            durationMs: 65,
          ));
    try {
      await _player.stop();
      await _player.setVolume(1.0);
      await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
    } catch (_) {
      // Sin altavoz / permisos: ignorar
    }
  }
}
