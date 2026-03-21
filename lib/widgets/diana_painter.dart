import 'package:flutter/material.dart';
import '../constants/diana_layout.dart';

class DianaPainter extends CustomPainter {
  final List<Offset> impactos;
  
  // Configuración Diana
  final int valorMinimo;
  final int anilloNegroInicio;
  final bool esFondoNegro;
  final bool tieneMosca;
  final bool tieneGuias;
  final bool esEstiloDuelo;
  final bool mostrarCartulina;

  // NUEVO: Centro de Gravedad (MPI)
  // Si no es null, dibujaremos una cruz indicando el desvío medio
  final Offset? centroGravedad; 

  DianaPainter({
    required this.impactos,
    required this.valorMinimo,
    required this.anilloNegroInicio,
    required this.esFondoNegro,
    required this.tieneMosca,
    required this.tieneGuias,
    required this.esEstiloDuelo,
    this.mostrarCartulina = false,
    this.centroGravedad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    final radius = radioPuntuacionPx(maxR, mostrarCartulina);

    if (mostrarCartulina) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFFFFFEF5)..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = Colors.grey.shade400
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // 1. Dibujar la Diana Base
    if (esEstiloDuelo) {
      _pintarDianaDuelo(canvas, center, radius);
    } else {
      _pintarDianaPrecision(canvas, center, radius);
    }

    if (mostrarCartulina) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.grey.shade500
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // 2. Dibujar Impactos
    _pintarImpactos(canvas, radius);

    // 3. DIBUJAR CENTRO DE GRAVEDAD (MPI)
    if (centroGravedad != null) {
      _pintarCentroGravedad(canvas, centroGravedad!);
    }
  }

  void _pintarCentroGravedad(Canvas canvas, Offset pos) {
    final paintMPI = Paint()
      ..color = Colors.redAccent // Color llamativo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Dibujar una cruz grande
    double sizeCruz = 15.0;
    canvas.drawLine(Offset(pos.dx - sizeCruz, pos.dy), Offset(pos.dx + sizeCruz, pos.dy), paintMPI);
    canvas.drawLine(Offset(pos.dx, pos.dy - sizeCruz), Offset(pos.dx, pos.dy + sizeCruz), paintMPI);
    
    // Círculo alrededor
    canvas.drawCircle(pos, sizeCruz / 1.5, paintMPI);
  }

  // ... (El resto de métodos _pintarDianaDuelo, _pintarDianaPrecision, etc. son IDÉNTICOS a los que ya tenías) ...
  // ... COPIA AQUÍ LOS MÉTODOS DE PINTURA QUE YA TENÍAS FUNCIONANDO EN SESION_DETALLE O DISPARO ...
  // Para que este código compile limpio, incluyo las versiones resumidas, pero usa tu lógica completa si la tienes personalizada.

  void _pintarDianaDuelo(Canvas canvas, Offset center, double radius) {
      final paintNegro = Paint()..color = const Color(0xFF1A1A1A)..style = PaintingStyle.fill;
      final paintLinea = Paint()..color = Colors.white54..style = PaintingStyle.stroke..strokeWidth = 1.0;
      canvas.drawCircle(center, radius, paintNegro);
      for (int i = 0; i < 6; i++) {
        canvas.drawCircle(center, radius - (i * (radius / 6)), paintLinea);
      }
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

  void _pintarImpactos(Canvas canvas, double radius) {
    final paintImpacto = Paint()..color = Colors.greenAccent.withValues(alpha: 0.6)..style = PaintingStyle.fill; // Un poco transparente para ver acumulación
    
    // Cálculo de tamaño relativo
    int totalZonas = esEstiloDuelo ? 6 : (11 - valorMinimo);
    double tamano = (radius * 0.035) * (10 / totalZonas); 

    for (var punto in impactos) {
      canvas.drawCircle(punto, tamano, paintImpacto);
    }
  }

  @override
  bool shouldRepaint(covariant DianaPainter oldDelegate) => true;
}