import 'package:flutter/material.dart';
import '../utils/impacto_visual.dart';

class DianaPainter extends CustomPainter {
  final List<Offset> impactos;
  
  // Configuración Diana
  final int valorMinimo;
  final int anilloNegroInicio;
  final bool esFondoNegro;
  final bool tieneMosca;
  final bool tieneGuias;
  final bool esEstiloDuelo;
  final String? nombreCalibre;
  final Offset? centroGravedad; 

  DianaPainter({
    required this.impactos,
    required this.valorMinimo,
    required this.anilloNegroInicio,
    required this.esFondoNegro,
    required this.tieneMosca,
    required this.tieneGuias,
    required this.esEstiloDuelo,
    this.nombreCalibre,
    this.centroGravedad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    if (esEstiloDuelo) {
      _pintarDianaDuelo(canvas, center, radius);
    } else {
      _pintarDianaPrecision(canvas, center, radius);
    }

    final totalZonas = esEstiloDuelo ? 6 : (11 - valorMinimo).clamp(1, 20);
    final anchoZona = radius / totalZonas;
    final radioImpacto = ImpactoVisual.radioPx(
      anchoZona: anchoZona,
      nombreCalibre: nombreCalibre,
    );
    for (final punto in impactos) {
      ImpactoVisual.dibujar(canvas, punto, radioImpacto);
    }

    if (centroGravedad != null) {
      _pintarCentroGravedad(canvas, centroGravedad!);
    }
  }

  void _pintarCentroGravedad(Canvas canvas, Offset pos) {
    final paintMPI = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    double sizeCruz = 15.0;
    canvas.drawLine(Offset(pos.dx - sizeCruz, pos.dy), Offset(pos.dx + sizeCruz, pos.dy), paintMPI);
    canvas.drawLine(Offset(pos.dx, pos.dy - sizeCruz), Offset(pos.dx, pos.dy + sizeCruz), paintMPI);
    canvas.drawCircle(pos, sizeCruz / 1.5, paintMPI);
  }

  void _pintarDianaDuelo(Canvas canvas, Offset center, double radius) {
      final paintNegro = Paint()..color = const Color(0xFF1A1A1A)..style = PaintingStyle.fill;
      final paintLinea = Paint()..color = Colors.white54..style = PaintingStyle.stroke..strokeWidth = 1.0;
      canvas.drawCircle(center, radius, paintNegro);
      for(int i=0; i<6; i++) canvas.drawCircle(center, radius - (i*(radius/6)), paintLinea);
  }

  void _pintarDianaPrecision(Canvas canvas, Offset center, double radius) {
      final paintPapel = Paint()..color = const Color(0xFFF5F3E0)..style = PaintingStyle.fill;
      final paintNegro = Paint()..color = Colors.black..style = PaintingStyle.fill;
      final paintLinea = Paint()..color = Colors.grey..style = PaintingStyle.stroke..strokeWidth = 1.0;
      
      canvas.drawCircle(center, radius, paintPapel);
      
      double paso = radius / (11 - valorMinimo);
      for(int i=0; i<(11-valorMinimo); i++) {
          double r = radius - (i * paso);
          if ((valorMinimo + i) >= anilloNegroInicio) {
             canvas.drawCircle(center, r, paintNegro);
             canvas.drawCircle(center, r, Paint()..color=Colors.white24..style=PaintingStyle.stroke);
          } else {
             canvas.drawCircle(center, r, paintLinea);
          }
      }
  }

  @override
  bool shouldRepaint(covariant DianaPainter oldDelegate) => true;
}
