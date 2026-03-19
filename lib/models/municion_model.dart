class Municion {
  final int? id;
  final String marca;
  final String lote;
  final int? idCalibre; // Opcional, por si queremos asignarle un calibre específico
  final int cantidadInicial;
  final int cantidadActual;
  final int totalDisparada;

  Municion({
    this.id,
    required this.marca,
    required this.lote,
    this.idCalibre,
    this.cantidadInicial = 0,
    this.cantidadActual = 0,
    this.totalDisparada = 0,
  });

  factory Municion.fromMap(Map<String, dynamic> map) {
    return Municion(
      id: map['id'],
      marca: map['marca'],
      lote: map['lote'],
      idCalibre: map['id_calibre'],
      cantidadInicial: (map['cantidad_inicial'] as num?)?.toInt() ?? 0,
      cantidadActual: (map['cantidad_actual'] as num?)?.toInt() ?? 0,
      totalDisparada: (map['total_disparada'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'marca': marca,
      'lote': lote,
      'id_calibre': idCalibre,
      'cantidad_inicial': cantidadInicial,
      'cantidad_actual': cantidadActual,
      'total_disparada': totalDisparada,
    };
  }
}

// Clase auxiliar para listados con nombre de calibre (JOIN)
class MunicionDetalle {
  final int id;
  final String marca;
  final String lote;
  final String nombreCalibre;
  final int cantidadInicial;
  final int cantidadActual;
  final int totalDisparada;

  MunicionDetalle({
    required this.id,
    required this.marca,
    required this.lote,
    required this.nombreCalibre,
    required this.cantidadInicial,
    required this.cantidadActual,
    required this.totalDisparada,
  });

  factory MunicionDetalle.fromMap(Map<String, dynamic> map) {
    return MunicionDetalle(
      id: map['id'],
      marca: map['marca'],
      lote: map['lote'],
      nombreCalibre: map['nombre_calibre'] ?? 'General',
      cantidadInicial: (map['cantidad_inicial'] as num?)?.toInt() ?? 0,
      cantidadActual: (map['cantidad_actual'] as num?)?.toInt() ?? 0,
      totalDisparada: (map['total_disparada'] as num?)?.toInt() ?? 0,
    );
  }
}

class MovimientoMunicion {
  final int? id;
  final int idMunicion;
  final String tipo; // compra | uso | ajuste
  final int cantidad;
  final DateTime fecha;
  final String? nota;

  MovimientoMunicion({
    this.id,
    required this.idMunicion,
    required this.tipo,
    required this.cantidad,
    required this.fecha,
    this.nota,
  });

  factory MovimientoMunicion.fromMap(Map<String, dynamic> map) {
    return MovimientoMunicion(
      id: map['id'],
      idMunicion: map['id_municion'],
      tipo: map['tipo'],
      cantidad: (map['cantidad'] as num).toInt(),
      fecha: DateTime.parse(map['fecha']),
      nota: map['nota'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'id_municion': idMunicion,
      'tipo': tipo,
      'cantidad': cantidad,
      'fecha': fecha.toIso8601String(),
      'nota': nota,
    };
  }
}

class UsoMunicionSesion {
  final int idSesion;
  final DateTime fecha;
  final String? lugar;
  final String? nota;
  final int disparos;
  final int? distanciaMetros;
  final bool? esInterior;
  final double? temperaturaC;
  final double? humedadPct;
  final double? vientoMs;
  final String? vientoDireccion;

  UsoMunicionSesion({
    required this.idSesion,
    required this.fecha,
    this.lugar,
    this.nota,
    required this.disparos,
    this.distanciaMetros,
    this.esInterior,
    this.temperaturaC,
    this.humedadPct,
    this.vientoMs,
    this.vientoDireccion,
  });

  factory UsoMunicionSesion.fromMap(Map<String, dynamic> map) {
    return UsoMunicionSesion(
      idSesion: (map['id_sesion'] as num).toInt(),
      fecha: DateTime.parse(map['fecha']),
      lugar: map['lugar'],
      nota: map['nota'],
      disparos: (map['disparos'] as num?)?.toInt() ?? 0,
      distanciaMetros: (map['distancia_m'] as num?)?.toInt(),
      esInterior: map['es_interior'] == null ? null : (map['es_interior'] as num).toInt() == 1,
      temperaturaC: (map['temperatura_c'] as num?)?.toDouble(),
      humedadPct: (map['humedad_pct'] as num?)?.toDouble(),
      vientoMs: (map['viento_ms'] as num?)?.toDouble(),
      vientoDireccion: map['viento_direccion'],
    );
  }
}