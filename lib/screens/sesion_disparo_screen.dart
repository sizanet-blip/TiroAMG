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
  int _contadorMoscas = 0;
  
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
  int _msRestantes = 0;
  DateTime? _faseEndsAt;
  Color _colorEstado = Colors.grey;
  bool _haIniciado = false;
  AvisoTiroPerfil _perfilAvisos = AvisoTiroPerfil.competicion;
  bool _mute = false;
  bool _flashBlanco = false;
  bool _fuegoPitidoAnticipado = false;
  int? _ultimoTickFinal; // segundo en el que ya sonó el tick
  bool _pulsoFinal = false;
  
  // Control de Duelo
  int _contadorSeriesDuelo = 0;
  
  // Lupa
  Offset? _posicionDedo;
  bool _mostrandoLupa = false;

  bool get _enCurso => _faseActual != FaseSesion.stop && _faseActual != FaseSesion.fin;
  bool get _dianaCerrada =>
      _faseActual == FaseSesion.espera || _faseActual == FaseSesion.preparacion;
  bool get _cuentaAtrasFinal =>
      _faseActual == FaseSesion.fuego &&
      !widget.plantilla.esDuel &&
      _segundosRestantes > 0 &&
      _segundosRestantes <= 10;

  String get _textoCrono {
    if (_segundosRestantes >= 60) {
      final m = _segundosRestantes ~/ 60;
      final s = _segundosRestantes % 60;
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    if (widget.plantilla.esDuel &&
        (_faseActual == FaseSesion.fuego || _faseActual == FaseSesion.espera) &&
        _msRestantes > 0 &&
        _msRestantes < 10000) {
      final whole = _msRestantes ~/ 1000;
      final tenths = ((_msRestantes % 1000) / 100).floor();
      return '$whole.$tenths';
    }
    return '$_segundosRestantes';
  }

  /// Etiqueta corta para la barra (sin tiempo).
  String get _etiquetaFaseBarra {
    switch (_faseActual) {
      case FaseSesion.preparacion:
        return 'PREPARACIÓN';
      case FaseSesion.espera:
        return 'ATENCIÓN';
      case FaseSesion.fuego:
        return 'FUEGO';
      case FaseSesion.fin:
        return 'ALTO';
      case FaseSesion.stop:
        return _mensajeEstado;
    }
  }

  String? get _subtituloDueloFuego {
    if (!widget.plantilla.esDuel || _faseActual != FaseSesion.fuego) return null;
    final actual = (_contadorSeriesDuelo + 1).clamp(1, widget.plantilla.disparosPorSerie);
    return 'Aparición $actual / ${widget.plantilla.disparosPorSerie}';
  }

  @override
  void initState() {
    super.initState();
    _cargarConfiguracionDiana();
    _resetearValoresTiempo();
    _initAudio();
  }

  Future<void> _initAudio() async {
    await _audioService.init();
    await _audioService.aplicarAutoPerfilSiProcede(widget.plantilla);
    if (!mounted) return;
    setState(() {
      _perfilAvisos = _audioService.perfil;
      _mute = _audioService.mute;
    });
  }

  Future<void> _togglePerfilAvisos() async {
    await _audioService.togglePerfil();
    if (!mounted) return;
    setState(() => _perfilAvisos = _audioService.perfil);
    final label = _perfilAvisos == AvisoTiroPerfil.competicion
        ? 'Modo Competición (árbitro)'
        : 'Modo Entrenamiento (voz)';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(label), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _toggleMute() async {
    await _audioService.toggleMute();
    if (!mounted) return;
    setState(() => _mute = _audioService.mute);
  }

  Future<void> _dispararFlash() async {
    if (!widget.plantilla.esDuel) return;
    if (!mounted) return;
    setState(() => _flashBlanco = true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    setState(() => _flashBlanco = false);
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
    _faseEndsAt = null;
    _msRestantes = 0;
    _segundosRestantes = widget.plantilla.tiempoPreparacion > 0
        ? widget.plantilla.tiempoPreparacion
        : widget.plantilla.tiempoExposicion;
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
    _faseEndsAt = null;
    setState(() {
      _faseActual = FaseSesion.stop;
      _mensajeEstado = "PAUSADO";
      _colorEstado = Colors.orange;
    });
  }

  void _cambiarFase(FaseSesion fase, int tiempo) {
    final ms = (tiempo * 1000).clamp(0, 24 * 60 * 60 * 1000);
    final omitirPitidoFuego = fase == FaseSesion.fuego && _fuegoPitidoAnticipado;
    _fuegoPitidoAnticipado = false;
    _ultimoTickFinal = null;

    setState(() {
      _faseActual = fase;
      _segundosRestantes = tiempo;
      _msRestantes = ms;
      _faseEndsAt = ms > 0
          ? DateTime.now().add(Duration(milliseconds: ms))
          : null;
      _pulsoFinal = false;

      if (fase == FaseSesion.preparacion) {
        _mensajeEstado = "PREPARACIÓN";
        _colorEstado = Colors.amber[800]!;
        _audioService.senalPreparacion();
      } else if (fase == FaseSesion.espera) {
        _mensajeEstado = "ATENCIÓN";
        _colorEstado = Colors.red[700]!;
        _audioService.senalAtencion();
        _dispararFlash();
      } else if (fase == FaseSesion.fuego) {
        _mensajeEstado = "FUEGO";
        _colorEstado = Colors.green[600]!;
        _audioService.senalFuego(omitirPitido: omitirPitidoFuego);
        _dispararFlash();
      } else if (fase == FaseSesion.fin) {
        _mensajeEstado = "ALTO";
        _colorEstado = Colors.blueGrey;
        _audioService.senalAlto(serieTerminada: true);
      }
    });
  }

  void _iniciarTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) return;
      final ends = _faseEndsAt;
      if (ends == null) return;
      final left = ends.difference(DateTime.now()).inMilliseconds;

      // Anticipar pitido de fuego ~120 ms antes del verde (duelo espera→fuego).
      if (_faseActual == FaseSesion.espera &&
          widget.plantilla.esDuel &&
          left <= 120 &&
          left > 0 &&
          !_fuegoPitidoAnticipado) {
        _fuegoPitidoAnticipado = true;
        _audioService.senalFuegoPitido();
      }

      if (left <= 0) {
        _faseEndsAt = null;
        setState(() {
          _msRestantes = 0;
          _segundosRestantes = 0;
          _pulsoFinal = false;
        });
        _gestionarCambioFase();
      } else {
        final secs = (left / 1000).ceil();
        final pulso = _faseActual == FaseSesion.fuego &&
            !widget.plantilla.esDuel &&
            secs <= 10 &&
            ((left ~/ 100) % 10 < 5);

        // Ticks en 10, 5, 3, 2, 1 s (precisión).
        if (_faseActual == FaseSesion.fuego &&
            !widget.plantilla.esDuel &&
            (secs == 10 || secs == 5 || secs == 3 || secs == 2 || secs == 1) &&
            _ultimoTickFinal != secs) {
          _ultimoTickFinal = secs;
          _audioService.senalTickFinal(urgente: secs <= 3);
          if (_audioService.vozEntrenadorActiva && (secs == 10 || secs == 5)) {
            _audioService.decirTiempo(secs);
          }
        }

        setState(() {
          _msRestantes = left;
          _segundosRestantes = secs;
          _pulsoFinal = pulso;
        });
      }
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
        
        if (_tieneMosca && distNorm < (0.05 * (10/totalZonas))) {
          _contadorMoscas++;
        }
        
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
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return OrientationBuilder(
      builder: (context, orientation) {
        final landscape = orientation == Orientation.landscape;
        return Scaffold(
          backgroundColor: Colors.grey[800],
          // En landscape no usamos AppBar a todo el ancho: controles van al panel.
          appBar: landscape
              ? null
              : AppBar(
                  title: Text(
                    widget.tituloSerie ?? widget.plantilla.nombreDisciplina,
                  ),
                  backgroundColor: Colors.black,
                  actions: _buildAppBarActions(),
                ),
          body: landscape ? _buildLandscapeBody() : _buildPortraitBody(),
        );
      },
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      IconButton(
        tooltip: _mute ? 'Activar sonido' : 'Silenciar',
        onPressed: _toggleMute,
        icon: Icon(
          _mute ? Icons.volume_off : Icons.volume_up,
          color: _mute ? Colors.orangeAccent : Colors.white70,
        ),
      ),
      IconButton(
        tooltip: _perfilAvisos == AvisoTiroPerfil.competicion
            ? 'Modo Competición (tocar para voz)'
            : 'Modo Entrenamiento (tocar para árbitro)',
        onPressed: _togglePerfilAvisos,
        icon: Icon(
          _perfilAvisos == AvisoTiroPerfil.competicion
              ? Icons.sports_score
              : Icons.record_voice_over,
          color: _perfilAvisos == AvisoTiroPerfil.competicion
              ? Colors.tealAccent
              : Colors.amberAccent,
        ),
      ),
      TextButton(
        onPressed: _guardarYSalir,
        child: const Text(
          'FIN',
          style: TextStyle(
            color: Colors.tealAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ];
  }

  Widget _buildPortraitBody() {
    return Column(
      children: [
        _buildInfoBar(),
        _buildStatusBar(),
        Expanded(child: _buildDianaArea()),
        _buildControlesBar(),
      ],
    );
  }

  Widget _buildLandscapeBody() {
    return SafeArea(
      child: Row(
        children: [
          Expanded(flex: 5, child: _buildDianaArea()),
          SizedBox(
            width: min(MediaQuery.sizeOf(context).width * 0.34, 300),
            child: _buildPanelLateral(),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: Colors.grey[900],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              widget.equipo.nombre,
              style: const TextStyle(color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$_puntosTotal pts',
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar({bool compact = false}) {
    return Container(
      color: _colorEstado,
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 6 : 8,
      ),
      child: Row(
        children: [
          Text(
            _perfilAvisos == AvisoTiroPerfil.competicion ? 'ÁRBITRO' : 'VOZ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _etiquetaFaseBarra,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 15 : 18,
                    letterSpacing: 1.2,
                  ),
                ),
                if (_subtituloDueloFuego != null)
                  Text(
                    _subtituloDueloFuego!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (_enCurso)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.skip_next, color: Colors.white, size: 26),
              onPressed: _avanzarFaseManual,
              tooltip: 'Saltar fase',
            ),
        ],
      ),
    );
  }

  Widget _buildControlesBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey[900],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.red, size: 28),
            onPressed: _reiniciarSerie,
            tooltip: 'Reiniciar',
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, 44),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: _iniciarSecuencia,
            child: Text(_enCurso ? 'PAUSA' : 'INICIAR'),
          ),
          IconButton(
            icon: const Icon(Icons.undo, color: Colors.white, size: 28),
            onPressed: _borrarUltimo,
            tooltip: 'Deshacer',
          ),
        ],
      ),
    );
  }

  /// Panel derecho en landscape: título, FIN/mute/modo, puntos, estado, crono, controles.
  Widget _buildPanelLateral() {
    final titulo = widget.tituloSerie ?? widget.plantilla.nombreDisciplina;
    return ColoredBox(
      color: const Color(0xFF1A1A1A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera del panel (sustituye AppBar)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Volver',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                ),
                Expanded(
                  child: Text(
                    titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: _mute ? 'Activar sonido' : 'Silenciar',
                  onPressed: _toggleMute,
                  icon: Icon(
                    _mute ? Icons.volume_off : Icons.volume_up,
                    color: _mute ? Colors.orangeAccent : Colors.white70,
                    size: 22,
                  ),
                ),
                IconButton(
                  tooltip: 'Perfil de avisos',
                  onPressed: _togglePerfilAvisos,
                  icon: Icon(
                    _perfilAvisos == AvisoTiroPerfil.competicion
                        ? Icons.sports_score
                        : Icons.record_voice_over,
                    color: _perfilAvisos == AvisoTiroPerfil.competicion
                        ? Colors.tealAccent
                        : Colors.amberAccent,
                    size: 22,
                  ),
                ),
                TextButton(
                  onPressed: _guardarYSalir,
                  child: const Text(
                    'FIN',
                    style: TextStyle(
                      color: Colors.tealAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Text(
              widget.equipo.nombre,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Text(
            '$_puntosTotal',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const Text(
            'pts',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.amber, fontSize: 12),
          ),
          const SizedBox(height: 6),
          _buildStatusBar(compact: true),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final cronoSize = (c.maxHeight * 0.45).clamp(28.0, 44.0);
                return Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _faseActual == FaseSesion.fuego || _dianaCerrada
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_dianaCerrada)
                                  Text(
                                    _faseActual == FaseSesion.preparacion
                                        ? 'PREPARACIÓN'
                                        : 'DIANA CERRADA',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                Text(
                                  _textoCrono,
                                  style: TextStyle(
                                    color: _cuentaAtrasFinal
                                        ? Colors.orangeAccent
                                        : Colors.white,
                                    fontSize: cronoSize,
                                    fontWeight: FontWeight.w800,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              _etiquetaFaseBarra,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Controles compactos en una sola fila (evita overflow).
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.red),
                  onPressed: _reiniciarSerie,
                  tooltip: 'Reiniciar',
                ),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: _iniciarSecuencia,
                    child: Text(_enCurso ? 'PAUSA' : 'INICIAR'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.undo, color: Colors.white),
                  onPressed: _borrarUltimo,
                  tooltip: 'Deshacer',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDianaArea({bool showOverlaysOnDiana = true}) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    // En landscape el crono/estado van al panel; en vertical sobre la diana.
    final overlayOnDiana = showOverlaysOnDiana && !landscape;

    return LayoutBuilder(builder: (context, constraints) {
      final diametro = min(constraints.maxWidth, constraints.maxHeight);
      final offX = (constraints.maxWidth - diametro) / 2;
      final offY = (constraints.maxHeight - diametro) / 2;
      final offsetCorrection = Offset(offX, offY);
      final size = Size(diametro, diametro);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _onPanStart(d, offsetCorrection, size),
        onPanUpdate: (d) => _onPanUpdate(d, offsetCorrection),
        onPanEnd: (d) => _onPanEnd(d, offsetCorrection, size),
        onTapUp: (d) => _onTapUp(d, offsetCorrection, size),
        child: Stack(
          children: [
            Center(
              child: Container(
                decoration: _faseActual == FaseSesion.fuego
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _cuentaAtrasFinal
                              ? (_pulsoFinal
                                  ? Colors.orangeAccent
                                  : Colors.greenAccent)
                              : Colors.greenAccent,
                          width: _cuentaAtrasFinal ? (_pulsoFinal ? 8 : 5) : 5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_cuentaAtrasFinal
                                    ? Colors.orangeAccent
                                    : Colors.greenAccent)
                                .withValues(alpha: 0.35),
                            blurRadius: _pulsoFinal ? 28 : 18,
                            spreadRadius: _pulsoFinal ? 4 : 2,
                          ),
                        ],
                      )
                    : null,
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
            if (overlayOnDiana && _faseActual == FaseSesion.fuego)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Text(
                    _textoCrono,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _cuentaAtrasFinal
                          ? Colors.orangeAccent
                          : Colors.white,
                      fontSize: _cuentaAtrasFinal ? 68 : 56,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      letterSpacing: 1.5,
                      shadows: const [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 12,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (overlayOnDiana && _dianaCerrada)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: false,
                  child: Container(
                    color: _faseActual == FaseSesion.preparacion
                        ? Colors.black.withValues(alpha: 0.55)
                        : Colors.red.shade900.withValues(alpha: 0.62),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _faseActual == FaseSesion.preparacion
                              ? Icons.hourglass_top
                              : Icons.block,
                          color: Colors.white,
                          size: 36,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _faseActual == FaseSesion.preparacion
                              ? 'PREPARACIÓN'
                              : 'DIANA CERRADA',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _textoCrono,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // En landscape: overlay de diana cerrada solo visual (sin texto).
            if (!overlayOnDiana && _dianaCerrada)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: _faseActual == FaseSesion.preparacion
                        ? Colors.black.withValues(alpha: 0.45)
                        : Colors.red.shade900.withValues(alpha: 0.5),
                  ),
                ),
              ),
            if (_flashBlanco)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            if (_mostrandoLupa && _posicionDedo != null && !_dianaCerrada)
              Positioned(
                left: _posicionDedo!.dx + offX - 50,
                top: _posicionDedo!.dy + offY - 120,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipOval(
                    child: Transform(
                      transform: Matrix4.identity()
                        ..translate(
                            -_posicionDedo!.dx * 2 + 50,
                            -_posicionDedo!.dy * 2 + 50)
                        ..scale(2.0),
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
            if (_mostrandoLupa && _posicionDedo != null && !_dianaCerrada)
              Positioned(
                left: _posicionDedo!.dx + offX - 50,
                top: _posicionDedo!.dy + offY - 120,
                child: const SizedBox(
                  width: 100,
                  height: 100,
                  child: Center(
                    child: Icon(Icons.add, color: Colors.red, size: 20),
                  ),
                ),
              ),
          ],
        ),
      );
    });
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