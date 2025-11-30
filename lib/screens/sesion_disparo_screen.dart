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
import '../widgets/diana_painter.dart';

// Estados posibles de la sesión
enum FaseSesion { stop, preparacion, espera, fuego, fin }

class SesionDisparoScreen extends StatefulWidget {
  final EquipoDetalle equipo;
  final PlantillaTiempos plantilla;
  final MunicionDetalle? municion;
  
  final String? tituloSerie;
  final int? numeroSerie;
  final int? totalSeries;

  final Function(List<Disparo> disparos, int puntos)? onCompletar;

  const SesionDisparoScreen({
    super.key,
    required this.equipo,
    required this.plantilla,
    this.municion,
    this.tituloSerie,
    this.numeroSerie,
    this.totalSeries,
    this.onCompletar,
  });

  @override
  State<SesionDisparoScreen> createState() => _SesionDisparoScreenState();
}

class _SesionDisparoScreenState extends State<SesionDisparoScreen> {
  final CatalogoService _catalogoService = CatalogoService();
  final EntrenamientoService _entrenamientoService = EntrenamientoService();
  
  final List<Disparo> _listaDisparos = [];
  final List<Offset> _puntosVisuales = [];
  
  int _puntosTotal = 0;
  int _contadorMoscas = 0;
  
  // Configuración Diana
  int _valorMinimo = 1;
  int _anilloNegroInicio = 7;
  bool _esFondoNegro = false;
  bool _tieneMosca = true;
  bool _tieneGuias = false;
  bool _cargando = true;
  bool _esEstiloDuelo = false;

  // Cronómetro y Estado
  Timer? _timer;
  FaseSesion _faseActual = FaseSesion.stop;
  FaseSesion _faseAntesDePausa = FaseSesion.stop;
  int _segundosRestantes = 0;
  int _contadorSeriesDuelo = 0;
  String _mensajeEstado = "LISTO";
  Color _colorEstado = Colors.grey;
  
  // CONTROL DE INICIO (NUEVO)
  bool _haIniciado = false; // Bloquea disparos hasta que se pulsa Iniciar por 1ª vez

  // LUPA
  Offset? _posicionDedo;
  bool _mostrandoLupa = false;

  bool get _enCurso => _faseActual != FaseSesion.stop && _faseActual != FaseSesion.fin;

  @override
  void initState() {
    super.initState();
    _cargarConfiguracionDiana();
    _resetearValoresTiempo();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetearValoresTiempo() {
    _faseActual = FaseSesion.stop;
    _faseAntesDePausa = FaseSesion.stop;
    _mensajeEstado = "LISTO";
    _colorEstado = Colors.grey;
    _contadorSeriesDuelo = 0;
    _haIniciado = false; // Reseteamos el bloqueo al reiniciar
    _segundosRestantes = widget.plantilla.tiempoPreparacion > 0 
        ? widget.plantilla.tiempoPreparacion 
        : widget.plantilla.tiempoExposicion;
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
          _esEstiloDuelo = _anilloNegroInicio <= 5;
          _cargando = false;
        });
      } catch (e) {
        setState(() => _cargando = false);
      }
    } else {
      setState(() => _cargando = false);
    }
  }

  // --- MOTOR DE TIEMPOS ---

  void _iniciarSecuencia() {
    // Marcamos que ya se ha iniciado al menos una vez
    if (!_haIniciado) {
      setState(() => _haIniciado = true);
    }

    if (_enCurso) { 
      _pausar();
      return;
    }

    if (_faseAntesDePausa != FaseSesion.stop && _faseAntesDePausa != FaseSesion.fin) {
       _reanudarDesdePausa();
    } else {
       if (widget.plantilla.tiempoPreparacion > 0) {
         _cambiarFase(FaseSesion.preparacion, widget.plantilla.tiempoPreparacion);
       } else {
         _siguientePasoDueloOFijo();
       }
    }
    
    _iniciarTicker();
  }

  void _reanudarDesdePausa() {
      setState(() {
        _faseActual = _faseAntesDePausa;
        _faseAntesDePausa = FaseSesion.stop;
        
        switch (_faseActual) {
            case FaseSesion.preparacion:
              _mensajeEstado = "PREPARACIÓN";
              _colorEstado = Colors.amber[800]!;
              break;
            case FaseSesion.espera:
              _mensajeEstado = "ATENCIÓN (ESPERA)";
              _colorEstado = Colors.red[700]!;
              break;
            case FaseSesion.fuego:
              _mensajeEstado = "¡FUEGO!";
              _colorEstado = Colors.green[600]!;
              break;
            default:
              break;
        }
      });
  }

  void _iniciarTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
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
          if (_contadorSeriesDuelo < widget.plantilla.disparosPorSerie) {
            _cambiarFase(FaseSesion.espera, widget.plantilla.tiempoOcultacion);
          } else {
            _terminarSesion();
          }
        } else {
          _terminarSesion();
        }
        break;
      default:
        _terminarSesion();
    }
  }

  void _avanzarFaseManual() {
    if (!_enCurso) return;
    _gestionarCambioFase(); 
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
                _contadorMoscas = 0;
                _resetearValoresTiempo();
              });
            },
            child: const Text('Reiniciar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _siguientePasoDueloOFijo() {
    if (widget.plantilla.esDuel) {
      _cambiarFase(FaseSesion.espera, widget.plantilla.tiempoOcultacion);
    } else {
      _cambiarFase(FaseSesion.fuego, widget.plantilla.tiempoExposicion);
    }
  }

  void _cambiarFase(FaseSesion nuevaFase, int duracion) {
    setState(() {
      _faseActual = nuevaFase;
      _segundosRestantes = duracion;
      
      switch (nuevaFase) {
        case FaseSesion.preparacion:
          _mensajeEstado = "PREPARACIÓN";
          _colorEstado = Colors.amber[800]!;
          break;
        case FaseSesion.espera:
          _mensajeEstado = "ATENCIÓN (ESPERA)";
          _colorEstado = Colors.red[700]!;
          break;
        case FaseSesion.fuego:
          _mensajeEstado = "¡FUEGO!";
          _colorEstado = Colors.green[600]!;
          break;
        case FaseSesion.fin:
          _mensajeEstado = "FIN";
          _colorEstado = Colors.grey;
          break;
        default:
          break;
      }
    });
  }

  void _terminarSesion() {
    _timer?.cancel();
    setState(() {
      _faseActual = FaseSesion.fin;
      _faseAntesDePausa = FaseSesion.stop;
      _mensajeEstado = "SERIE COMPLETADA";
      _colorEstado = Colors.blueGrey;
    });
  }

  void _pausar() {
    _timer?.cancel();
    setState(() {
      _faseAntesDePausa = _faseActual;
      _faseActual = FaseSesion.stop;
      _mensajeEstado = "PAUSADO";
      _colorEstado = Colors.orange;
    });
  }

  // --- LÓGICA DE IMPACTO (CORE) ---

  // Gestión de eventos del gesto (Pan/Drag)
  void _onPanStart(DragStartDetails details, Offset offsetCorrection, Size tamanoDiana) {
    setState(() {
      _mostrandoLupa = true;
      _posicionDedo = details.localPosition - offsetCorrection;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Offset offsetCorrection) {
    setState(() {
      _posicionDedo = details.localPosition - offsetCorrection;
    });
  }

  void _onPanEnd(DragEndDetails details, Offset offsetCorrection, Size tamanoDiana) {
    setState(() {
      _mostrandoLupa = false;
    });
    // Al soltar, disparamos donde estaba el dedo (ajustado)
    if (_posicionDedo != null) {
      _intentarRegistrarImpacto(null, _posicionDedo!, tamanoDiana);
    }
  }

  void _onTapUp(TapUpDetails details, Offset offsetCorrection, Size tamanoDiana) {
    // Ajustamos la coordenada del toque restando el margen (padding)
    _intentarRegistrarImpacto(null, details.localPosition - offsetCorrection, tamanoDiana);
  }

  void _intentarRegistrarImpacto(TapUpDetails? tapDetails, Offset? dragPosition, Size tamanoDiana) {
    Offset pos = tapDetails?.localPosition ?? dragPosition!;
    
    // 1. BLOQUEO: Si no se ha iniciado nunca
    if (!_haIniciado) {
       ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Dale a INICIAR para comenzar la serie.'), 
              duration: Duration(milliseconds: 1000),
              backgroundColor: Colors.blueGrey
            )
        );
        return;
    }

    // 2. BLOQUEO: Fases de no disparo (Espera/Preparación)
    if (_faseActual == FaseSesion.espera || _faseActual == FaseSesion.preparacion) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('¡Alto! Diana cerrada.'), duration: Duration(milliseconds: 500), backgroundColor: Colors.red)
        );
        return;
    }

    if (_listaDisparos.length >= widget.plantilla.disparosPorSerie) {
      _mostrarAlertaExceso(pos, tamanoDiana);
    } else {
      _registrarImpactoReal(pos, tamanoDiana);
    }
  }

  void _mostrarAlertaExceso(Offset pos, Size tamanoDiana) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ Serie Completa'),
        content: Text('Ya tienes ${widget.plantilla.disparosPorSerie} disparos. ¿Quieres registrar este tiro extra?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(ctx);
              _registrarImpactoReal(pos, tamanoDiana);
            },
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }

  void _registrarImpactoReal(Offset localPosition, Size tamanoDiana) {
    setState(() {
      // 1. Guardar visualmente (Siempre, aunque sea fuera)
      _puntosVisuales.add(localPosition);
      
      Offset centro = Offset(tamanoDiana.width / 2, tamanoDiana.height / 2);
      double distancia = (localPosition - centro).distance;
      double radioMax = tamanoDiana.width / 2;
      double distNorm = distancia / radioMax;
      
      int valorEntero = 0;
      bool esMosca = false;

      // 2. Calcular Puntos (Si está dentro del 1.0)
      if (distNorm <= 1.0) {
        int totalZonas = _esEstiloDuelo ? 6 : (11 - _valorMinimo);
        
        if (_esEstiloDuelo) {
          // Lógica Duelo (5-10)
          double calculo = 11 - (distNorm * 6);
          valorEntero = calculo.floor();
          if (valorEntero < 5) valorEntero = 0; 
          if (valorEntero > 10) valorEntero = 10;
        } else {
          // Lógica Precisión
          double calculo = 11 - (distNorm * totalZonas);
          valorEntero = calculo.floor();
          if (valorEntero < _valorMinimo) valorEntero = 0;
          if (valorEntero > 10) valorEntero = 10;
        }
        
        // Lógica Mosca
        double factorZoom = 10 / totalZonas; 
        double limiteMosca = _esEstiloDuelo ? 0.08 : (0.05 * factorZoom); 
        
        if (_tieneMosca && distNorm < limiteMosca) {
          _contadorMoscas++;
          esMosca = true;
        }
      } else {
        // Fuera de la diana visual = 0 puntos (Miss)
        valorEntero = 0;
      }
      
      _puntosTotal += valorEntero;

      // 3. Guardar Lógicamente
      double xNorm = (localPosition.dx - centro.dx) / radioMax;
      double yNorm = (localPosition.dy - centro.dy) / radioMax;

      _listaDisparos.add(Disparo(
        numero: _listaDisparos.length + 1,
        x: xNorm,
        y: yNorm,
        puntuacion: valorEntero.toDouble(),
        esMosca: esMosca,
      ));
    });
  }

  void _mostrarListaTiros() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white, 
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(16),
            height: 400,
            child: Column(
              children: [
                const Text('Registro de Impactos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                const Divider(),
                Expanded(
                  child: _listaDisparos.isEmpty
                  ? const Center(child: Text("No hay impactos registrados", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                    itemCount: _listaDisparos.length,
                    itemBuilder: (context, index) {
                      final tiroIndex = _listaDisparos.length - 1 - index;
                      final tiro = _listaDisparos[tiroIndex];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blueGrey.withOpacity(0.2), 
                          child: Text('${tiro.numero}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black))
                        ),
                        title: Text('Puntos: ${tiro.puntuacion.toInt()} ${tiro.esMosca ? '(X)' : ''}', style: const TextStyle(color: Colors.black)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            _borrarTiroEspecifico(tiroIndex);
                            setModalState(() {});
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  void _borrarTiroEspecifico(int index) {
    setState(() {
      int puntos = _listaDisparos[index].puntuacion.floor();
      if (_listaDisparos[index].esMosca) _contadorMoscas--;
      _puntosTotal -= puntos;
      _listaDisparos.removeAt(index);
      _puntosVisuales.removeAt(index);
    });
  }

  void _borrarUltimo() {
    if (_listaDisparos.isNotEmpty) _borrarTiroEspecifico(_listaDisparos.length - 1);
  }

  void _validarYGuardar() {
    int esperados = widget.plantilla.disparosPorSerie;
    int actuales = _listaDisparos.length;

    if (actuales < esperados) {
      _mostrarAlertaGuardado('Serie Incompleta', 'Faltan ${esperados - actuales} disparos. ¿Guardar de todas formas?');
    } else if (actuales > esperados) {
      _mostrarAlertaGuardado('Exceso de Disparos', 'Hay ${actuales - esperados} disparos extra. ¿Guardar así?');
    } else {
      _terminarYGuardar();
    }
  }

  void _mostrarAlertaGuardado(String titulo, String mensaje) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Revisar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _terminarYGuardar();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _terminarYGuardar() async {
    if (widget.onCompletar != null) {
      widget.onCompletar!(_listaDisparos, _puntosTotal);
      Navigator.pop(context); 
      return;
    }

    final nuevaSesion = Sesion(
      fecha: DateTime.now(),
      idEquipo: widget.equipo.id,
      idPlantilla: widget.plantilla.id!,
      nota: widget.municion != null ? 'Munición: ${widget.municion!.marca} - ${widget.municion!.lote}' : null,
    );

    try {
      await _entrenamientoService.guardarSesionCompleta(nuevaSesion, _listaDisparos);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entrenamiento guardado')));
        Navigator.pop(context);
      }
    } catch (e) {
      // Error
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    bool dianaOculta = _faseActual == FaseSesion.espera || _faseActual == FaseSesion.preparacion;

    return Scaffold(
      backgroundColor: Colors.grey[800],
      appBar: AppBar(
        title: Text(widget.tituloSerie ?? widget.plantilla.nombreDisciplina),
        backgroundColor: Colors.black,
        actions: [
          IconButton(icon: const Icon(Icons.list), onPressed: _mostrarListaTiros),
          TextButton(onPressed: _validarYGuardar, child: const Text('FIN', style: TextStyle(color: Colors.tealAccent)))
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[900],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.equipo.nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    
                    // Contador de Tiros (Verde si completo, Rojo si exceso, Gris normal)
                    Text(
                      'Tiros: ${_listaDisparos.length} / ${widget.plantilla.disparosPorSerie}', 
                      style: TextStyle(
                        color: _listaDisparos.length > widget.plantilla.disparosPorSerie 
                            ? Colors.redAccent 
                            : (_listaDisparos.length == widget.plantilla.disparosPorSerie ? Colors.greenAccent : Colors.grey),
                        fontWeight: FontWeight.bold,
                        fontSize: 14
                      )
                    ),
                  ],
                ),
                Text('$_puntosTotal pts', style: const TextStyle(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Container(
            color: _colorEstado, 
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer, color: Colors.white),
                    const SizedBox(width: 8),
                    Text("$_mensajeEstado: $_segundosRestantes s", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                if (_enCurso)
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white, size: 30),
                    tooltip: "Saltar espera / Siguiente fase",
                    onPressed: _avanzarFaseManual,
                  )
              ],
            ),
          ),
          
          // ZONA EXPANDIDA (Cubre toda la pantalla sobrante)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Área total disponible
                double fullWidth = constraints.maxWidth;
                double fullHeight = constraints.maxHeight;
                
                // Tamaño de la diana (centrado)
                double diametroDiana = min(fullWidth, fullHeight);
                double paddingX = (fullWidth - diametroDiana) / 2;
                double paddingY = (fullHeight - diametroDiana) / 2;
                Offset offsetCorrection = Offset(paddingX, paddingY);
                Size tamanoDiana = Size(diametroDiana, diametroDiana);

                return GestureDetector(
                  // behavior: HitTestBehavior.opaque asegura que coja toques en el vacío
                  behavior: HitTestBehavior.opaque,
                  
                  // Gestos de Lupa (Pan)
                  onPanStart: (d) => _onPanStart(d, offsetCorrection, tamanoDiana),
                  onPanUpdate: (d) => _onPanUpdate(d, offsetCorrection),
                  onPanEnd: (d) => _onPanEnd(d, offsetCorrection, tamanoDiana),
                  
                  // Gesto de Disparo Rápido (Tap)
                  onTapUp: (d) => _onTapUp(d, offsetCorrection, tamanoDiana),
                  
                  child: Stack(
                    children: [
                      // Centramos visualmente la diana
                      Center(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CustomPaint(
                              size: tamanoDiana,
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
                            // Overlay de "Bloqueado"
                            if (dianaOculta)
                              Container(
                                width: diametroDiana, 
                                height: diametroDiana, 
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.85), shape: BoxShape.circle),
                                child: const Center(child: Icon(Icons.block, color: Colors.red, size: 80)),
                              ),
                          ],
                        ),
                      ),

                      // LUPA FLOTANTE (Encima de todo)
                      if (_mostrandoLupa && _posicionDedo != null)
                        Positioned(
                          left: _posicionDedo!.dx + paddingX - 50, 
                          top: _posicionDedo!.dy + paddingY - 120,
                          child: Container(
                            width: 100, height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black54)],
                              color: Colors.black,
                            ),
                            child: ClipOval(
                              child: Transform(
                                transform: Matrix4.identity()
                                  ..translate(-_posicionDedo!.dx * 2 + 50, -_posicionDedo!.dy * 2 + 50)
                                  ..scale(2.0),
                                child: CustomPaint(
                                  size: tamanoDiana,
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
                            left: _posicionDedo!.dx + paddingX - 50, 
                            top: _posicionDedo!.dy + paddingY - 120,
                            child: Container(
                              width: 100, height: 100,
                              child: const Center(child: Icon(Icons.add, color: Colors.redAccent, size: 20)),
                            )
                         ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[900],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(icon: const Icon(Icons.refresh, color: Colors.red), onPressed: _reiniciarSerie),
                ElevatedButton(
                  onPressed: _iniciarSecuencia,
                  child: const Text("INICIAR / PAUSA"),
                ),
                IconButton(icon: const Icon(Icons.undo, color: Colors.white), onPressed: _borrarUltimo),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
