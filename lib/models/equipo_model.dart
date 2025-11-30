class Equipo {
  final int? id;
  final String nombre;
  final int idTipoArma; // Relación con el catálogo
  final int idCalibre;  // Relación con el catálogo
  final String? marca;
  final String? modelo;

  Equipo({
    this.id,
    required this.nombre,
    required this.idTipoArma,
    required this.idCalibre,
    this.marca,
    this.modelo,
  });

  factory Equipo.fromMap(Map<String, dynamic> map) {
    return Equipo(
      id: map['id'],
      nombre: map['nombre'],
      idTipoArma: map['id_tipo_arma'],
      idCalibre: map['id_calibre'],
      marca: map['marca'],
      modelo: map['modelo'],
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
    };
  }
}

// Clase auxiliar para mostrar la lista con nombres (JOIN)
class EquipoDetalle {
  final int id;
  final String nombre;
  final String nombreTipo;
  final String nombreCalibre;
  final String? marca;

  EquipoDetalle({
    required this.id,
    required this.nombre,
    required this.nombreTipo,
    required this.nombreCalibre,
    this.marca,
  });

  factory EquipoDetalle.fromMap(Map<String, dynamic> map) {
    return EquipoDetalle(
      id: map['id'],
      nombre: map['nombre'],
      nombreTipo: map['nombre_tipo'] ?? 'Desconocido',
      nombreCalibre: map['nombre_calibre'] ?? 'Desconocido',
      marca: map['marca'],
    );
  }
}