class Municion {
  final int? id;
  final String marca;
  final String lote;
  final int? idCalibre; // Opcional, por si queremos asignarle un calibre específico

  Municion({
    this.id,
    required this.marca,
    required this.lote,
    this.idCalibre,
  });

  factory Municion.fromMap(Map<String, dynamic> map) {
    return Municion(
      id: map['id'],
      marca: map['marca'],
      lote: map['lote'],
      idCalibre: map['id_calibre'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'marca': marca,
      'lote': lote,
      'id_calibre': idCalibre,
    };
  }
}

// Clase auxiliar para listados con nombre de calibre (JOIN)
class MunicionDetalle {
  final int id;
  final String marca;
  final String lote;
  final String nombreCalibre;

  MunicionDetalle({
    required this.id,
    required this.marca,
    required this.lote,
    required this.nombreCalibre,
  });

  factory MunicionDetalle.fromMap(Map<String, dynamic> map) {
    return MunicionDetalle(
      id: map['id'],
      marca: map['marca'],
      lote: map['lote'],
      nombreCalibre: map['nombre_calibre'] ?? 'General',
    );
  }
}