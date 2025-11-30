class TipoDiana {
  final int? id;
  final String nombre;
  final int valorMinimo;      // El anillo más externo visible (1 o 5)
  final int anilloNegroInicio; // Dónde empieza el negro
  final bool esFondoNegro;    // Color del papel exterior
  final bool tieneMosca;
  final bool tieneGuias;      // Líneas horizontales blancas

  TipoDiana({
    this.id,
    required this.nombre,
    required this.valorMinimo,
    required this.anilloNegroInicio,
    required this.esFondoNegro,
    required this.tieneMosca,
    required this.tieneGuias,
  });

  factory TipoDiana.fromMap(Map<String, dynamic> map) {
    return TipoDiana(
      id: map['id'],
      nombre: map['nombre'],
      valorMinimo: map['valor_minimo'] ?? 1,
      anilloNegroInicio: map['anillo_negro_inicio'],
      esFondoNegro: map['es_fondo_negro'] == 1,
      tieneMosca: map['tiene_mosca'] == 1,
      tieneGuias: map['tiene_guias'] == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nombre': nombre,
      'valor_minimo': valorMinimo,
      'anillo_negro_inicio': anilloNegroInicio,
      'es_fondo_negro': esFondoNegro ? 1 : 0,
      'tiene_mosca': tieneMosca ? 1 : 0,
      'tiene_guias': tieneGuias ? 1 : 0,
    };
  }
}