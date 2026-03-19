class Disparo {
  final int? id;
  final int? idSesion;
  final int numero;
  final double x; // coordenada_x
  final double y; // coordenada_y
  final double puntuacion;
  final bool esMosca;

  Disparo({
    this.id,
    this.idSesion,
    required this.numero,
    required this.x,
    required this.y,
    required this.puntuacion,
    required this.esMosca,
  });

  // --- ¡AQUÍ ESTABA EL ERROR! FALTABA ESTE MÉTODO ---
  factory Disparo.fromMap(Map<String, dynamic> map) {
    return Disparo(
      id: map['id'],
      idSesion: map['id_sesion'],
      numero: map['numero_disparo'],
      // Importante: Usar 'as num' para evitar errores si la BD devuelve int en vez de double
      x: (map['coordenada_x'] as num).toDouble(),
      y: (map['coordenada_y'] as num).toDouble(),
      puntuacion: (map['puntuacion'] as num).toDouble(),
      esMosca: map['es_mosca'] == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'id_sesion': idSesion,
      'numero_disparo': numero,
      'coordenada_x': x,
      'coordenada_y': y,
      'puntuacion': puntuacion,
      'es_mosca': esMosca ? 1 : 0,
    };
  }
}