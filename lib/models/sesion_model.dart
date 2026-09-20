class Sesion {
  final int? id;
  final DateTime fecha;
  final int idEquipo;
  final int idPlantilla;
  final int? idModalidad;
  final int? idMunicion;
  final String? nota;
  final String? lugar;
  final int? distanciaMetros;
  final String? posicionTiro;
  final bool? esInterior;
  final double? temperaturaC;
  final double? humedadPct;
  final double? presionHpa;
  final double? vientoMs;
  final String? vientoDireccion;
  final String? iluminacion;
  /// Si true, la sesión es para regular miras (análisis de clics; sin técnica).
  final bool esCorreccionMira;

  Sesion({
    this.id,
    required this.fecha,
    required this.idEquipo,
    required this.idPlantilla,
    this.idModalidad,
    this.idMunicion,
    this.nota,
    this.lugar,
    this.distanciaMetros,
    this.posicionTiro,
    this.esInterior,
    this.temperaturaC,
    this.humedadPct,
    this.presionHpa,
    this.vientoMs,
    this.vientoDireccion,
    this.iluminacion,
    this.esCorreccionMira = false,
  });

  factory Sesion.fromMap(Map<String, dynamic> map) {
    return Sesion(
      id: map['id'],
      fecha: DateTime.parse(map['fecha']),
      idEquipo: map['id_equipo'],
      idPlantilla: map['id_plantilla_tiempos'],
      idModalidad: map['id_modalidad'],
      idMunicion: map['id_municion'],
      nota: map['nota'],
      lugar: map['lugar'],
      distanciaMetros: (map['distancia_m'] as num?)?.toInt(),
      posicionTiro: map['posicion_tiro'],
      esInterior: map['es_interior'] == null ? null : (map['es_interior'] as num).toInt() == 1,
      temperaturaC: (map['temperatura_c'] as num?)?.toDouble(),
      humedadPct: (map['humedad_pct'] as num?)?.toDouble(),
      presionHpa: (map['presion_hpa'] as num?)?.toDouble(),
      vientoMs: (map['viento_ms'] as num?)?.toDouble(),
      vientoDireccion: map['viento_direccion'],
      iluminacion: map['iluminacion'],
      esCorreccionMira: (map['es_correccion_mira'] as num?)?.toInt() == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'fecha': fecha.toIso8601String(),
      'id_equipo': idEquipo,
      'id_plantilla_tiempos': idPlantilla,
      'id_modalidad': idModalidad,
      'id_municion': idMunicion,
      'nota': nota,
      'lugar': lugar,
      'distancia_m': distanciaMetros,
      'posicion_tiro': posicionTiro,
      'es_interior': esInterior == null ? null : (esInterior! ? 1 : 0),
      'temperatura_c': temperaturaC,
      'humedad_pct': humedadPct,
      'presion_hpa': presionHpa,
      'viento_ms': vientoMs,
      'viento_direccion': vientoDireccion,
      'iluminacion': iluminacion,
      'es_correccion_mira': esCorreccionMira ? 1 : 0,
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
  final String? lugar;
  final int? idMunicion;
  final String? marcaMunicion;
  final String? loteMunicion;

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
    this.idMunicion,
    this.marcaMunicion,
    this.loteMunicion,
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
      lugar: map['lugar'],
      idMunicion: map['id_municion'],
      marcaMunicion: map['marca_municion'],
      loteMunicion: map['lote_municion'],
    );
  }
}
