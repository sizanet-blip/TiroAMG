import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/equipo_model.dart';
import '../models/plantilla_tiempos_model.dart';
import '../models/municion_model.dart';
import '../models/sesion_model.dart';
import '../models/disparo_model.dart';
import '../services/catalogo_service.dart';
import '../services/entrenamiento_service.dart';
import '../services/audio_service.dart';

enum FaseSesion { stop, preparacion, espera, fuego, fin }

class SesionDisparoScreen extends StatefulWidget {
  final EquipoDetalle equipo;
  final PlantillaTiempos plantilla;
  final MunicionDetalle? municion;
  final String? lugar;
  final int? distanciaMetros;
  final String? posicionTiro;
  final bool? esInterior;
  final double? temperaturaC;
  final double? humedadPct;
  final double? presionHpa;
  final double? vientoMs;
  final String? vientoDireccion;
  final String? iluminacion;
  
  final String? tituloSerie;
  final int? numeroSerie;
  final int? totalSeries;
  final Function(List<Disparo> disparos, int puntos)? onCompletar;

  const SesionDisparoScreen({
    super.key,
    required this.equipo,
    required this.plantilla,
    this.municion,
    this.lugar,
    this.distanciaMetros,
    this.posicionTiro,
    this.esInterior,
    this.temperaturaC,
    this.humedadPct,
    this.presionHpa,
    this.vientoMs,
    this.vientoDireccion,
    this.iluminacion,
    this.tituloSerie,
    this.numeroSerie,
    this.totalSeries,
    this.onCompletar,
  });

  @override
  State<SesionDisparoScreen> createState() => _SesionDisparoScreenState();
}

class _SesionDisparoScreenState extends State<SesionDisparoScreen> {
  final _catalogoService = CatalogoService();
  final _entrenamientoService = EntrenamientoService();
  final _audioService = AudioService(); 

  final List<Disparo> _listaDisparos = [];
  final List<Offset> _puntosVisuales = [];
  
  int _puntosTotal = 0;
  
  // Configuración Diana
  int _valorMinimo = 1;
  int _anilloNegroInicio = 7;
  bool _esFondoNegro = false;
  bool _tieneMosca = true;
  bool _tieneGuias = false;
  bool _esEstiloDuelo = false;
  bool _cargando = true;

  // Estado Crono
  Timer? _timer;
  FaseSesion _faseActual = FaseSesion.stop;
  String _mensajeEstado = "LISTO";
  int _segundosRestantes = 0;
  Color _colorEstado = Colors.grey;
  bool _haIniciado = false;
  
  // Control de Duelo
  int _contadorSeriesDuelo = 0;
  
  // Lupa
  Offset? _posicionDedo;
  bool _mostrandoLupa = false;

  bool get _enCurso => _faseActual != FaseSesion.stop && _faseActual != FaseSesion.fin;

  @override
  void initState() {
    super.initState();
    _cargarConfiguracionDiana();
    _resetearValoresTiempo();
    _audioService.init();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioService.stop();
    super.dispose();
  }

  void _cargarConfiguracionDiana() async {
    if (widget.plantilla.idTipoDiana != null) {
      final dianas = await _catalogoService.obtenerTiposDiana();
      try {
        final dianaConfig = dianas.firstWhere((d) => d.id == widget.plantilla.idTipoDiana);
        setState(() {
          _valorMinimo = dianaConfig.valorMinimo;
          _anilloNegroInicio = dianaConfig.anilloNegroInicio;
          _esFondoNegro = dianaConfig.esFondoNegro;
          _tieneMosca = dianaConfig.tieneMosca;
          _tieneGuias = dianaConfig.tieneGuias;
          _esEstiloDuelo = _valorMinimo >= 5; 
          _cargando = false;
        });
      } catch (e) {
        setState(() => _cargando = false);
      }
    } else {
      setState(() => _cargando = false);
    }
  }

  void _resetearValoresTiempo() {
    _faseActual = FaseSesion.stop;
    _mensajeEstado = "LISTO";
    _colorEstado = Colors.grey;
    _contadorSeriesDuelo = 0;
    _segundosRestantes = widget.plantilla.tiempoPreparacion > 0 ? widget.plantilla.tiempoPreparacion : widget.plantilla.tiempoExposicion;
  }

  // --- LÓGICA DEL CRONÓMETRO AVANZADA ---

  void _iniciarSecuencia() {
    if (!_haIniciado) setState(() => _haIniciado = true);
    
    if (_enCurso) {
      _pausar();
      return;
    }

    if (widget.plantilla.tiempoPreparacion > 0) {
      _cambiarFase(FaseSesion.preparacion, widget.plantilla.tiempoPreparacion);
    } else {
      _siguientePasoDueloOFijo();
    }
    _iniciarTicker();
  }

  void _pausar() {
    _timer?.cancel();
    setState(() {
      _faseActual = FaseSesion.stop;
      _mensajeEstado = "PAUSADO";
      _colorEstado = Colors.orange;
    });
  }

  void _cambiarFase(FaseSesion fase, int tiempo) {
    setState(() {
      _faseActual = fase;
      _segundosRestantes = tiempo;
      
      if (fase == FaseSesion.preparacion) {
        _mensajeEstado = "PREPARACIÓN";
        _colorEstado = Colors.amber[800]!;
        _audioService.decirPreparacion();
      } else if (fase == FaseSesion.espera) {
        _mensajeEstado = "ATENCIÓN (ESPERA)";
        _colorEstado = Colors.red[700]!;
        _audioService.decirAtencion();
      } else if (fase == FaseSesion.fuego) {
        _mensajeEstado = "¡FUEGO!";
        _colorEstado = Colors.green[600]!;
        _audioService.decirFuego();
      } else if (fase == FaseSesion.fin) {
        _mensajeEstado = "FIN";
        _colorEstado = Colors.blueGrey;
        _audioService.decirFin();
      }
    });
  }

  void _iniciarTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_segundosRestantes > 0) {
          _segundosRestantes--;
        } else {
          _gestionarCambioFase();
        }
      });
    });
  }

  void _gestionarCambioFase() {
    switch (_faseActual) {
      case FaseSesion.preparacion:
        _contadorSeriesDuelo = 0;
        _siguientePasoDueloOFijo();
        break;
      case FaseSesion.espera:
        _cambiarFase(FaseSesion.fuego, widget.plantilla.tiempoExposicion);
        break;
      case FaseSesion.fuego:
        if (widget.plantilla.esDuel) {
          _contadorSeriesDuelo++;
          // En Duelo, se repite espera->fuego por cada disparo (o serie de 5)
          // Si queremos simular 5 apariciones:
          if (_contadorSeriesDuelo < widget.plantilla.disparosPorSerie) {
             _cambiarFase(FaseSesion.espera, widget.plantilla.tiempoOcultacion);
          } else {
             _cambiarFase(FaseSesion.fin, 0);
             _timer?.cancel();
          }
        } else {
          // En Precisión (fijo), al acabar el tiempo de fuego se acaba la serie
          _cambiarFase(FaseSesion.fin, 0);
          _timer?.cancel();
        }
        break;
      default:
        break;
    }
  }

  void _siguientePasoDueloOFijo() {
    if (widget.plantilla.esDuel) {
      _cambiarFase(FaseSesion.espera, widget.plantilla.tiempoOcultacion);
    } else {
      _cambiarFase(FaseSesion.fuego, widget.plantilla.tiempoExposicion);
    }
  }

  // --- FUNCIÓN SALTAR FASE (SKIP) ---
  void _avanzarFaseManual() {
    if (!_enCurso) return;
    // Forzamos el cambio inmediato como si el tiempo hubiera llegado a 0
    _gestionarCambioFase();
  }

  // --- REGISTRO DE IMPACTOS ---
  void _registrarImpacto(Offset localPosition, Size tamanoDiana) {
    if (!_haIniciado) return;

    // Bloqueo en fases de espera/preparación
    if (_faseActual == FaseSesion.espera || _faseActual == FaseSesion.preparacion) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('¡Alto! Diana cerrada.'), duration: Duration(milliseconds: 500), backgroundColor: Colors.red));
        return;
    }

    setState(() {
      _puntosVisuales.add(localPosition);
      
      Offset centro = Offset(tamanoDiana.width / 2, tamanoDiana.height / 2);
      double distancia = (localPosition - centro).distance;
      double radioMax = tamanoDiana.width / 2;
      double distNorm = distancia / radioMax;

      if (distNorm <= 1.0) {
        int totalZonas = 11 - _valorMinimo;
        double calculo = 11 - (distNorm * totalZonas);
        int valor = calculo.floor();
        
        if (valor < _valorMinimo) valor = 0;
        if (valor > 10) valor = 10;
        
        _puntosTotal += valor;
        
        _listaDisparos.add(Disparo(
          numero: _listaDisparos.length + 1,
          x: (localPosition.dx - centro.dx) / radioMax,
          y: (localPosition.dy - centro.dy) / radioMax,
          puntuacion: valor.toDouble(),
          esMosca: false 
        ));
      }
    });
  }

  void _borrarUltimo() {
    if (_puntosVisuales.isNotEmpty) {
      setState(() {
        _puntosVisuales.removeLast();
        if (_listaDisparos.isNotEmpty) {
          _puntosTotal -= _listaDisparos.last.puntuacion.toInt();
          _listaDisparos.removeLast();
        }
      });
    }
  }

  void _guardarYSalir() async {
     if (widget.onCompletar != null) {
       widget.onCompletar!(_listaDisparos, _puntosTotal);
       Navigator.pop(context);
       return;
     }
     
     final sesion = Sesion(
        fecha: DateTime.now(),
        idEquipo: widget.equipo.id,
        idPlantilla: widget.plantilla.id!,
        idMunicion: widget.municion?.id,
        nota: widget.municion != null ? "${widget.municion!.marca} (${widget.municion!.lote})" : null,
        lugar: widget.lugar,
        distanciaMetros: widget.distanciaMetros,
        posicionTiro: widget.posicionTiro,
        esInterior: widget.esInterior,
        temperaturaC: widget.temperaturaC,
        humedadPct: widget.humedadPct,
        presionHpa: widget.presionHpa,
        vientoMs: widget.vientoMs,
        vientoDireccion: widget.vientoDireccion,
        iluminacion: widget.iluminacion,
     );
     
     await _entrenamientoService.guardarSesionCompleta(sesion, _listaDisparos);
     if (mounted) {
       Navigator.pop(context);
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Guardado")));
     }
  }

  void _reiniciarSerie() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Reiniciar Serie?'),
        content: const Text('Se borrarán los disparos actuales y el cronómetro volverá al inicio.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _pausar();
              setState(() {
                _listaDisparos.clear();
                _puntosVisuales.clear();
                _puntosTotal = 0;
                _resetearValoresTiempo();
              });
            },
            child: const Text('Reiniciar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Gestos Lupa
  void _onPanStart(DragStartDetails d, Offset offset, Size size) { setState(() { _mostrandoLupa = true; _posicionDedo = d.localPosition - offset; }); }
  void _onPanUpdate(DragUpdateDetails d, Offset offset) { setState(() { _posicionDedo = d.localPosition - offset; }); }
  void _onPanEnd(DragEndDetails d, Offset offset, Size size) { 
    setState(() { _mostrandoLupa = false; });
    if (_posicionDedo != null) _registrarImpacto(_posicionDedo!, size);
  }
  void _onTapUp(TapUpDetails d, Offset offset, Size size) { _registrarImpacto(d.localPosition - offset, size); }


  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.grey[800],
      appBar: AppBar(
        title: Text(widget.tituloSerie ?? widget.plantilla.nombreDisciplina),
        backgroundColor: Colors.black,
        actions: [
          TextButton(onPressed: _guardarYSalir, child: const Text('FIN', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)))
        ],
      ),
      body: Column(
        children: [
          // INFO
          Container(
            padding: const EdgeInsets.all(12), color: Colors.grey[900],
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(widget.equipo.nombre, style: const TextStyle(color: Colors.white)),
                Text('$_puntosTotal pts', style: const TextStyle(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.bold))
            ])
          ),
          
          // CRONO + BOTÓN DE SALTAR (SKIP)
          Container(
            color: _colorEstado, 
            width: double.infinity, 
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                 const Expanded(child: SizedBox()), // Spacer
                 Text("$_mensajeEstado: $_segundosRestantes s", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                 const Expanded(child: SizedBox()), // Spacer
                 
                 // BOTÓN SALTAR FASE (Solo visible si está corriendo)
                 if (_enCurso)
                   IconButton(
                     icon: const Icon(Icons.skip_next, color: Colors.white, size: 30),
                     onPressed: _avanzarFaseManual,
                     tooltip: "Saltar tiempo de espera",
                   )
              ],
            )
          ),
          
          // DIANA
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
               double diametro = min(constraints.maxWidth, constraints.maxHeight);
               double offX = (constraints.maxWidth - diametro) / 2;
               double offY = (constraints.maxHeight - diametro) / 2;
               Offset offsetCorrection = Offset(offX, offY);
               Size size = Size(diametro, diametro);

               return GestureDetector(
                 behavior: HitTestBehavior.opaque,
                 onPanStart: (d) => _onPanStart(d, offsetCorrection, size),
                 onPanUpdate: (d) => _onPanUpdate(d, offsetCorrection),
                 onPanEnd: (d) => _onPanEnd(d, offsetCorrection, size),
                 onTapUp: (d) => _onTapUp(d, offsetCorrection, size),
                 child: Stack(
                   children: [
                     Center(
                       child: CustomPaint(
                         size: size,
                         painter: DianaPainter(
                           impactos: _puntosVisuales,
                           valorMinimo: _valorMinimo,
                           anilloNegroInicio: _anilloNegroInicio,
                           esFondoNegro: _esFondoNegro,
                           tieneMosca: _tieneMosca,
                           tieneGuias: _tieneGuias,
                           esEstiloDuelo: _esEstiloDuelo,
                         ),
                       ),
                     ),
                     
                     // LUPA
                     if (_mostrandoLupa && _posicionDedo != null)
                        Positioned(
                          left: _posicionDedo!.dx + offX - 50,
                          top: _posicionDedo!.dy + offY - 120,
                          child: Container(
                            width: 100, height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle, color: Colors.black,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: ClipOval(
                              child: Transform(
                                transform: Matrix4.identity()
                                  ..translateByDouble(-_posicionDedo!.dx * 2 + 50, -_posicionDedo!.dy * 2 + 50, 0, 1)
                                  ..scaleByDouble(2.0, 2.0, 1.0, 1.0),
                                child: CustomPaint(
                                  size: size,
                                  painter: DianaPainter(
                                    impactos: _puntosVisuales,
                                    valorMinimo: _valorMinimo,
                                    anilloNegroInicio: _anilloNegroInicio,
                                    esFondoNegro: _esFondoNegro,
                                    tieneMosca: _tieneMosca,
                                    tieneGuias: _tieneGuias,
                                    esEstiloDuelo: _esEstiloDuelo,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        
                      if (_mostrandoLupa && _posicionDedo != null)
                        Positioned(
                           left: _posicionDedo!.dx + offX - 50, top: _posicionDedo!.dy + offY - 120,
                           child: const SizedBox(width: 100, height: 100, child: Center(child: Icon(Icons.add, color: Colors.red, size: 20)))
                        )
                   ],
                 ),
               );
            }),
          ),
          
          // BOTONES INFERIORES
          Container(
            padding: const EdgeInsets.all(20), color: Colors.grey[900],
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                IconButton(icon: const Icon(Icons.refresh, color: Colors.red), onPressed: _reiniciarSerie),
                ElevatedButton(onPressed: _iniciarSecuencia, child: Text(_enCurso ? "PAUSA" : "INICIAR")),
                IconButton(icon: const Icon(Icons.undo, color: Colors.white), onPressed: _borrarUltimo),
            ]),
          )
        ],
      ),
    );
  }
}

class DianaPainter extends CustomPainter {
  final List<Offset> impactos;
  final int valorMinimo;
  final int anilloNegroInicio;
  final bool esFondoNegro;
  final bool tieneMosca;
  final bool tieneGuias;
  final bool esEstiloDuelo;

  DianaPainter({
    required this.impactos,
    required this.valorMinimo,
    required this.anilloNegroInicio,
    required this.esFondoNegro,
    required this.tieneMosca,
    required this.tieneGuias,
    required this.esEstiloDuelo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Fondo
    final paintFondo = Paint()..color = esFondoNegro ? const Color(0xFF1A1A1A) : const Color(0xFFF5F3E0)..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paintFondo);

    // 2. Anillos y Números
    int totalZonas = 11 - valorMinimo; 
    double anchoZona = radius / totalZonas;
    
    final paintNegro = Paint()..color = Colors.black..style = PaintingStyle.fill;
    final paintLineaClara = Paint()..color = Colors.grey[400]!..style = PaintingStyle.stroke..strokeWidth = 1.0;
    final paintLineaBlanca = Paint()..color = Colors.white70..style = PaintingStyle.stroke..strokeWidth = 1.0;

    for (int i = 0; i < totalZonas; i++) {
      int numeroAnillo = valorMinimo + i;
      double r = radius - (i * anchoZona);
      
      // Zona Negra
      if (numeroAnillo >= anilloNegroInicio) {
        canvas.drawCircle(center, r, paintNegro);
        canvas.drawCircle(center, r, paintLineaBlanca);
        // NÚMEROS BLANCOS EN ZONA NEGRA
        if (numeroAnillo < 10) {
           _dibujarNumeros4Ejes(canvas, numeroAnillo.toString(), center, r - (anchoZona / 2), Colors.white);
        }
      } 
      // Zona Clara
      else {
        if (i > 0) canvas.drawCircle(center, r, esFondoNegro ? paintLineaBlanca : paintLineaClara);
        // NÚMEROS NEGROS EN ZONA CLARA (O BLANCOS SI FONDO NEGRO)
        Color colorNum = esFondoNegro ? Colors.white : Colors.black;
        _dibujarNumeros4Ejes(canvas, numeroAnillo.toString(), center, r - (anchoZona / 2), colorNum);
      }
    }

    // 3. Mosca
    if (tieneMosca) {
      double radioMosca = (radius / totalZonas) / 2;
      canvas.drawCircle(center, radioMosca, paintLineaBlanca);
    }
    
    // 4. Guías
    if (tieneGuias) {
      Paint guia = Paint()..color = Colors.white..strokeWidth = 2.0;
      double largo = radius * 0.3;
      canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx - radius + largo, center.dy), guia);
      canvas.drawLine(Offset(center.dx + radius, center.dy), Offset(center.dx + radius - largo, center.dy), guia);
    }
    
    // 5. Impactos
    final paintImpacto = Paint()..color = Colors.greenAccent;
    for(var p in impactos) {
       canvas.drawCircle(p, anchoZona * 0.3, paintImpacto);
    }
  }

  void _dibujarNumeros4Ejes(Canvas canvas, String texto, Offset center, double dist, Color color) {
    _texto(canvas, texto, Offset(center.dx, center.dy - dist), color); // Arriba
    _texto(canvas, texto, Offset(center.dx, center.dy + dist), color); // Abajo
    _texto(canvas, texto, Offset(center.dx + dist, center.dy), color); // Derecha
    _texto(canvas, texto, Offset(center.dx - dist, center.dy), color); // Izquierda
  }

  void _texto(Canvas canvas, String texto, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: texto, 
        style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold) 
      ),
      textDirection: TextDirection.ltr
    );
    tp.layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant DianaPainter oldDelegate) => true;
}