import 'disparo_model.dart';

class GrupoFaseInforme {
  final String titulo;
  final List<Disparo> disparos;
  final bool esEnsayo; // ¡NUEVO!
  
  final int valorMinimo;
  final int anilloNegro;
  final bool esFondoNegro;
  final bool tieneMosca;
  final bool tieneGuias;
  final bool esEstiloDuelo;

  GrupoFaseInforme({
    required this.titulo,
    required this.disparos,
    required this.esEnsayo,
    required this.valorMinimo,
    required this.anilloNegro,
    required this.esFondoNegro,
    required this.tieneMosca,
    required this.tieneGuias,
    required this.esEstiloDuelo,
  });
}