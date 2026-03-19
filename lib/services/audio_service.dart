import 'package:flutter_tts/flutter_tts.dart';

class AudioService {
  // Singleton para usarlo en toda la app
  static final AudioService instance = AudioService._internal();
  factory AudioService() => instance;
  AudioService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _habilitado = true; // Interruptor general

  Future<void> init() async {
    await _flutterTts.setLanguage("es-ES"); // Español
    await _flutterTts.setSpeechRate(0.5);   // Velocidad normal
    await _flutterTts.setVolume(1.0);       // Volumen máximo
    await _flutterTts.setPitch(1.0);        // Tono normal
  }

  // Comandos de Tiro
  Future<void> decirPreparacion() async => _hablar("Preparación. Cargar.");
  Future<void> decirAtencion() async => _hablar("Atención.");
  
  // Para el "YA" o el inicio, usamos un texto corto para minimizar latencia
  Future<void> decirFuego() async {
     await _flutterTts.setSpeechRate(0.6); // Un poco más rápido
     await _hablar("¡YA!");
     await _flutterTts.setSpeechRate(0.5); // Restaurar
  }
  
  Future<void> decirAlto() async => _hablar("Alto. Descargar.");
  Future<void> decirFin() async => _hablar("Serie terminada.");
  
  Future<void> decirTiempo(int segundos) async => _hablar("$segundos segundos.");

  Future<void> _hablar(String texto) async {
    if (!_habilitado) return;
    await _flutterTts.speak(texto);
  }

  // Control
  void setHabilitado(bool estado) {
    _habilitado = estado;
  }
  
  // Parar si salimos de la pantalla
  void stop() {
    _flutterTts.stop();
  }
}