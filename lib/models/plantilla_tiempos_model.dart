class PlantillaTiempos {
  final int? id;
  final String nombreDisciplina;
  final int disparosPorSerie;
  final int seriesPorSesion;
  final bool puntuacionDecimal;
  final int tiempoPreparacion;
  final bool esDuel; 
  final int tiempoExposicion;
  final int tiempoOcultacion;
  
  // ¡NUEVO CAMPO!
  final int? idTipoDiana; 

  PlantillaTiempos({
    this.id,
    required this.nombreDisciplina,
    required this.disparosPorSerie,
    required this.seriesPorSesion,
    required this.puntuacionDecimal,
    required this.tiempoPreparacion,
    required this.esDuel,
    required this.tiempoExposicion,
    required this.tiempoOcultacion,
    this.idTipoDiana, // Opcional por compatibilidad
  });

  factory PlantillaTiempos.fromMap(Map<String, dynamic> map) {
    return PlantillaTiempos(
      id: map['id'],
      nombreDisciplina: map['nombre_disciplina'],
      disparosPorSerie: map['disparos_por_serie'],
      seriesPorSesion: map['series_por_sesion'],
      puntuacionDecimal: map['puntuacion_decimal'] == 1,
      tiempoPreparacion: map['tiempo_preparacion'] ?? 0,
      esDuel: map['es_duelo'] == 1,
      tiempoExposicion: map['tiempo_exposicion'],
      tiempoOcultacion: map['tiempo_ocultacion'] ?? 0,
      idTipoDiana: map['id_tipo_diana'], // Leemos de la BD
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nombre_disciplina': nombreDisciplina,
      'disparos_por_serie': disparosPorSerie,
      'series_por_sesion': seriesPorSesion,
      'puntuacion_decimal': puntuacionDecimal ? 1 : 0,
      'tiempo_preparacion': tiempoPreparacion,
      'es_duelo': esDuel ? 1 : 0,
      'tiempo_exposicion': tiempoExposicion,
      'tiempo_ocultacion': tiempoOcultacion,
      'id_tipo_diana': idTipoDiana, // Guardamos en la BD
    };
  }
}