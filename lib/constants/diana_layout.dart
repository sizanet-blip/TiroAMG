/// Fracción del radio máximo del widget que ocupa el disco de puntuación
/// cuando se muestra cartulina alrededor (margen visible de “papel”).
const double kRadioPuntuacionConCartulina = 0.93;

/// Radio en píxeles del disco de puntuación (normalizado |coord|≤1 respecto a este radio).
double radioPuntuacionPx(double halfWidth, bool mostrarCartulina) {
  return halfWidth *
      (mostrarCartulina ? kRadioPuntuacionConCartulina : 1.0);
}
