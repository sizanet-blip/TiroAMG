class Disparo {
  final int? id;
  final int? idSesion;
  final int numero;
  final double x;
  final double y;
  final double puntuacion;
  final bool esMosca;
  final double? puntuacionOficial;
  final bool? esMoscaOficial;

  Disparo({
    this.id,
    this.idSesion,
    required this.numero,
    required this.x,
    required this.y,
    required this.puntuacion,
    required this.esMosca,
    this.puntuacionOficial,
    this.esMoscaOficial,
  });

  factory Disparo.fromMap(Map<String, dynamic> map) {
    return Disparo(
      id: map['id'],
      idSesion: map['id_sesion'],
      numero: map['numero_disparo'],
      x: (map['coordenada_x'] as num).toDouble(),
      y: (map['coordenada_y'] as num).toDouble(),
      puntuacion: (map['puntuacion'] as num).toDouble(),
      esMosca: map['es_mosca'] == 1,
      puntuacionOficial: (map['puntuacion_oficial'] as num?)?.toDouble(),
      esMoscaOficial: map['es_mosca_oficial'] == null
          ? null
          : (map['es_mosca_oficial'] as num).toInt() == 1,
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
      'puntuacion_oficial': puntuacionOficial,
      'es_mosca_oficial': esMoscaOficial == null ? null : (esMoscaOficial! ? 1 : 0),
    };
  }

  Disparo copyWith({
    double? puntuacionOficial,
    bool? esMoscaOficial,
    bool clearOficial = false,
  }) {
    return Disparo(
      id: id,
      idSesion: idSesion,
      numero: numero,
      x: x,
      y: y,
      puntuacion: puntuacion,
      esMosca: esMosca,
      puntuacionOficial: clearOficial ? null : (puntuacionOficial ?? this.puntuacionOficial),
      esMoscaOficial: clearOficial ? null : (esMoscaOficial ?? this.esMoscaOficial),
    );
  }
}
