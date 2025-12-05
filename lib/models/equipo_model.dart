class Equipo {
  final int? id;
  final String nombre;
  final int idTipoArma;
  final int idCalibre;
  final String? marca;
  final String? modelo;
  final double correccionClick; // Campo nuevo para la calculadora

  Equipo({
    this.id,
    required this.nombre,
    required this.idTipoArma,
    required this.idCalibre,
    this.marca,
    this.modelo,
    this.correccionClick = 0.0, // Por defecto 0 si no se especifica
  });

  factory Equipo.fromMap(Map<String, dynamic> map) {
    return Equipo(
      id: map['id'],
      nombre: map['nombre'],
      idTipoArma: map['id_tipo_arma'],
      idCalibre: map['id_calibre'],
      marca: map['marca'],
      modelo: map['modelo'],
      // Leemos el campo nuevo, manejando nulos
      correccionClick: (map['correccion_click_mm'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nombre': nombre,
      'id_tipo_arma': idTipoArma,
      'id_calibre': idCalibre,
      'marca': marca,
      'modelo': modelo,
      'correccion_click_mm': correccionClick,
    };
  }
}

class EquipoDetalle {
  final int id;
  final String nombre;
  final String nombreTipo;
  final String nombreCalibre;
  final String? marca;
  final double correccionClick; // También en el detalle

  EquipoDetalle({
    required this.id,
    required this.nombre,
    required this.nombreTipo,
    required this.nombreCalibre,
    this.marca,
    this.correccionClick = 0.0,
  });

  factory EquipoDetalle.fromMap(Map<String, dynamic> map) {
    return EquipoDetalle(
      id: map['id'],
      nombre: map['nombre'],
      nombreTipo: map['nombre_tipo'] ?? 'Desconocido',
      nombreCalibre: map['nombre_calibre'] ?? 'Desconocido',
      marca: map['marca'],
      correccionClick: (map['correccion_click_mm'] as num?)?.toDouble() ?? 0.0,
    );
  }
}