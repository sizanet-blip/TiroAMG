// CLASE PADRE: La definición del Torneo/Modalidad
class Modalidad {
  final int? id;
  final String nombre;
  final String? descripcion;
  final bool esOficial; // Si es true, no dejamos editar el nombre/borrarla fácilmente

  Modalidad({
    this.id,
    required this.nombre,
    this.descripcion,
    this.esOficial = false,
  });

  factory Modalidad.fromMap(Map<String, dynamic> map) {
    return Modalidad(
      id: map['id'],
      nombre: map['nombre'],
      descripcion: map['descripcion'],
      esOficial: map['es_oficial'] == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nombre': nombre,
      'descripcion': descripcion,
      'es_oficial': esOficial ? 1 : 0,
    };
  }
}

// CLASE HIJA: Cada paso de la "Playlist"
class FaseModalidad {
  final int? id;
  final int idModalidad;        // A qué torneo pertenece
  final int orden;              // 1, 2, 3...
  final int idPlantillaTiempos; // Qué regla usa (Duelo, Precisión...)
  final int repeticiones;       // Cuántas veces se repite (series)
  final bool esEnsayo;          // Si cuenta o no
  final String descripcionFase; // Nombre visual (ej: "Fase Precisión")

  FaseModalidad({
    this.id,
    required this.idModalidad,
    required this.orden,
    required this.idPlantillaTiempos,
    required this.repeticiones,
    required this.esEnsayo,
    required this.descripcionFase,
  });

  factory FaseModalidad.fromMap(Map<String, dynamic> map) {
    return FaseModalidad(
      id: map['id'],
      idModalidad: map['id_modalidad'],
      orden: map['orden'],
      idPlantillaTiempos: map['id_plantilla_tiempos'],
      repeticiones: map['repeticiones'],
      esEnsayo: map['es_ensayo'] == 1,
      descripcionFase: map['descripcion_fase'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'id_modalidad': idModalidad,
      'orden': orden,
      'id_plantilla_tiempos': idPlantillaTiempos,
      'repeticiones': repeticiones,
      'es_ensayo': esEnsayo ? 1 : 0,
      'descripcion_fase': descripcionFase,
    };
  }
}

// CLASE EXTRA: Para mostrar la lista bonita con JOINs
// Nos servirá para mostrar: "Fase 1: Precisión (5 min) - 6 Series"
class FaseDetalle {
  final FaseModalidad fase;
  final String nombrePlantilla;
  final bool esDuelo;

  FaseDetalle({
    required this.fase,
    required this.nombrePlantilla,
    required this.esDuelo,
  });
}