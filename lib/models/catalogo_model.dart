class TipoArma {
  final int? id;
  final String nombre;

  TipoArma({this.id, required this.nombre});

  // Convertir de Map (Base de Datos) a Clase
  factory TipoArma.fromMap(Map<String, dynamic> map) {
    return TipoArma(
      id: map['id'],
      nombre: map['nombre'],
    );
  }

  // Convertir de Clase a Map (para guardar en BD)
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nombre': nombre,
    };
  }
}

class Calibre {
  final int? id;
  final String nombre;

  Calibre({this.id, required this.nombre});

  factory Calibre.fromMap(Map<String, dynamic> map) {
    return Calibre(
      id: map['id'],
      nombre: map['nombre'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nombre': nombre,
    };
  }
}