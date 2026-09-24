import 'package:flutter/material.dart';

/// Capas de impactos de referencia: cada lista interna es una serie anterior.
/// La última capa es la más reciente (más opaca).
typedef CapasFantasma = List<List<Offset>>;

/// Tamaño y color de impactos alineados con la tirada en vivo.
class ImpactoVisual {
  ImpactoVisual._();

  static const Color colorImpacto = Color(0xFFE53935);
  static const Color colorDescartado = Color(0xFF9E9E9E);
  /// Impactos de series anteriores (solo referencia visual).
  static const Color colorFantasma = Color(0xFF1E88E5);

  /// Opacidad por antigüedad: última serie = 1.0; las previas más suaves.
  static double opacidadCapa({
    required int indiceCapa,
    required int totalCapas,
  }) {
    if (totalCapas <= 1) return 1.0;
    final antiguedad = totalCapas - 1 - indiceCapa; // 0 = más reciente
    return (1.0 - antiguedad * 0.28).clamp(0.30, 1.0);
  }

  static int contarImpactos(CapasFantasma capas) {
    var n = 0;
    for (final c in capas) {
      n += c.length;
    }
    return n;
  }

  /// Mismo estilo que un impacto normal, en azul (opacidad según capa).
  static void dibujarFantasma(
    Canvas canvas,
    Offset punto,
    double radio, {
    double opacity = 1.0,
  }) {
    dibujar(
      canvas,
      punto,
      radio,
      color: colorFantasma.withValues(alpha: opacity.clamp(0.0, 1.0)),
    );
  }

  /// Fracción del ancho de un anillo de puntuación.
  /// Referencia: diana 25 m (~25 mm/anillo) y .22 LR (~5,6 mm) ≈ 0,11.
  static double fraccionRadioAnillo(String? nombreCalibre) {
    final c = (nombreCalibre ?? '').toLowerCase();
    if (c.contains('4.5') ||
        c.contains('4,5') ||
        c.contains('.177') ||
        c.contains('aire')) {
      return 0.09;
    }
    if (c.contains('.32') || c.contains('7.65') || c.contains('7,65')) {
      return 0.13;
    }
    if (c.contains('9mm') ||
        c.contains('9 mm') ||
        c.contains('.38') ||
        c.contains('.45') ||
        c.contains('40') ||
        c.contains('.44')) {
      return 0.17;
    }
    return 0.11; // .22 / por defecto
  }

  /// Radio en píxeles del impacto sobre la diana dibujada.
  static double radioPx({
    required double anchoZona,
    String? nombreCalibre,
  }) {
    return (anchoZona * fraccionRadioAnillo(nombreCalibre))
        .clamp(2.0, anchoZona * 0.22);
  }

  static void dibujar(
    Canvas canvas,
    Offset punto,
    double radio, {
    Color color = colorImpacto,
  }) {
    canvas.drawCircle(punto, radio, Paint()..color = color);
  }
}
