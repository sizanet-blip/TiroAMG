class Sesion {
  final int? id;
  final DateTime fecha;
  final int idEquipo;
  final int idPlantilla;
  final int? idModalidad;
  final String? nota;
  final String? lugar; // ¡NUEVO!

  Sesion({
    this.id,
    required this.fecha,
    required this.idEquipo,
    required this.idPlantilla,
    this.idModalidad,
    this.nota,
    this.lugar,
  });

  factory Sesion.fromMap(Map<String, dynamic> map) {
    return Sesion(
      id: map['id'],
      fecha: DateTime.parse(map['fecha']),
      idEquipo: map['id_equipo'],
      idPlantilla: map['id_plantilla_tiempos'],
      idModalidad: map['id_modalidad'],
      nota: map['nota'],
      lugar: map['lugar'], // ¡NUEVO!
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'fecha': fecha.toIso8601String(),
      'id_equipo': idEquipo,
      'id_plantilla_tiempos': idPlantilla,
      'id_modalidad': idModalidad,
      'nota': nota,
      'lugar': lugar, // ¡NUEVO!
    };
  }
}

class SesionResumen {
  final int id;
  final DateTime fecha;
  final String nombreEquipo;
  final String nombreTitulo;
  final int totalPuntos;
  final int totalMoscas;
  final bool esCompeticion;
  final String? nota;
  final String? lugar; // ¡NUEVO! También en resumen para mostrarlo si quieres

  SesionResumen({
    required this.id,
    required this.fecha,
    required this.nombreEquipo,
    required this.nombreTitulo,
    required this.totalPuntos,
    required this.totalMoscas,
    required this.esCompeticion,
    this.nota,
    this.lugar,
  });

  factory SesionResumen.fromMap(Map<String, dynamic> map) {
    return SesionResumen(
      id: map['id'],
      fecha: DateTime.parse(map['fecha']),
      nombreEquipo: map['nombre_equipo'] ?? 'Desconocido',
      nombreTitulo: map['titulo_torneo'] ?? map['titulo'] ?? 'Entrenamiento',
      totalPuntos: (map['total_puntos'] as num?)?.toInt() ?? 0,
      totalMoscas: (map['total_moscas'] as num?)?.toInt() ?? 0,
      esCompeticion: map.containsKey('id_modalidad') ? (map['id_modalidad'] != null) : false,
      nota: map['nota'],
      lugar: map['lugar'], // ¡NUEVO!
    );
  }
}