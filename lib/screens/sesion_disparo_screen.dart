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
import '../widgets/tiro_amg_app_bar_title.dart';
import '../utils/impacto_visual.dart';

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
  /// Si true: panel X/10…0 en lugar de marcar impactos en la diana.
  final bool usarEntradaManualPuntos;
  /// Sesión orientada a regular miras (análisis de clics).
  final bool esCorreccionMira;

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
    this.usarEntradaManualPuntos = false,
    this.esCorreccionMira = false,
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
  final GlobalKey _dianaPaintKey = GlobalKey();
  final GlobalKey _dianaStackKey = GlobalKey();
  
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
  
  // Lupa de puntería (arrastrar sobre diana)
  static const double _lupaRadio = 60;
  /// Desplaza la lupa hacia arriba para no tapar el puntero; el foco sigue en el ratón.
  static const double _lupaDesfaseY = 72;
  Offset? _posicionDedo;
  Offset? _posicionGlobalPuntero;
  bool _mostrandoLupa = false;
  bool _impactoRegistradoEnPan = false;

  // Inspección: ampliar diana para ver impactos
  bool _modoInspeccion = false;
  final TransformationController _inspeccionController =
      TransformationController();

  /// true = Serie (tope suave), false = Libre (sin límite)
  bool _modoSerieLimitada = true;

  int get _maxDisparosSerie => widget.plantilla.disparosPorSerie;
  int get _disparosActuales => _listaDisparos.length;
  bool get _serieCompleta =>
      _modoSerieLimitada && _disparosActuales >= _maxDisparosSerie;

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
    _inspeccionController.dispose();
    _audioService.stop();
    super.dispose();
  }

  void _toggleModoInspeccion() {
    setState(() {
      _modoInspeccion = !_modoInspeccion;
      _mostrandoLupa = false;
      _posicionDedo = null;
      _posicionGlobalPuntero = null;
      if (!_modoInspeccion) {
        _inspeccionController.value = Matrix4.identity();
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _modoInspeccion
              ? 'Inspección: pellizca o arrastra para ampliar la diana'
              : 'Inspección desactivada',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _botonLupaInspeccion() {
    return IconButton(
      tooltip: _modoInspeccion ? 'Salir de inspección' : 'Ampliar diana',
      onPressed: _toggleModoInspeccion,
      icon: Icon(
        _modoInspeccion ? Icons.zoom_out_map : Icons.search,
        color: _modoInspeccion ? Colors.amberAccent : Colors.white,
        size: 28,
      ),
    );
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
    if (_faseActual == FaseSesion.espera ||
        _faseActual == FaseSesion.preparacion) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Alto! Diana cerrada.'),
          duration: Duration(milliseconds: 500),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_serieCompleta) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Serie completa · $_disparosActuales/$_maxDisparosSerie',
          ),
          duration: const Duration(milliseconds: 1200),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      // ignore: unawaited_futures
      _audioService.avisarSerieCompleta(
        actual: _disparosActuales,
        maximo: _maxDisparosSerie,
      );
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

        if (_tieneMosca && distNorm < (0.05 * (10 / totalZonas))) {
          _contadorMoscas++;
        }

        _listaDisparos.add(Disparo(
          numero: _listaDisparos.length + 1,
          x: (localPosition.dx - centro.dx) / radioMax,
          y: (localPosition.dy - centro.dy) / radioMax,
          puntuacion: valor.toDouble(),
          esMosca: false,
        ));
      } else {
        // Fuera de diana: quitar el punto visual recién añadido
        _puntosVisuales.removeLast();
      }
    });
  }

  void _toggleModoSerieLibre() {
    setState(() => _modoSerieLimitada = !_modoSerieLimitada);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _modoSerieLimitada
              ? 'Modo Serie · límite $_maxDisparosSerie tiros'
              : 'Modo Libre · sin límite de tiros',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _botonModoSerieLibre({bool compact = false}) {
    return IconButton(
      tooltip: _modoSerieLimitada
          ? 'Serie (límite). Tocar para Libre'
          : 'Libre (sin límite). Tocar para Serie',
      onPressed: _toggleModoSerieLibre,
      icon: Icon(
        _modoSerieLimitada ? Icons.filter_1 : Icons.all_inclusive,
        color: _modoSerieLimitada ? Colors.lightBlueAccent : Colors.white70,
        size: compact ? 24 : 28,
      ),
    );
  }

  Widget _chipContadorTiros({bool compact = false}) {
    if (!_modoSerieLimitada) {
      return Text(
        '$_disparosActuales tiros',
        style: TextStyle(
          color: Colors.white54,
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    final completo = _serieCompleta;
    return Text(
      '$_disparosActuales / $_maxDisparosSerie',
      style: TextStyle(
        color: completo ? Colors.orangeAccent : Colors.lightBlueAccent,
        fontSize: compact ? 13 : 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  void _borrarUltimo() {
    if (_listaDisparos.isEmpty && _puntosVisuales.isEmpty) return;
    setState(() {
      if (_puntosVisuales.isNotEmpty) {
        _puntosVisuales.removeLast();
      }
      if (_listaDisparos.isNotEmpty) {
        _puntosTotal -= _listaDisparos.last.puntuacion.toInt();
        // Si hay más puntos visuales que disparos (legado), no tocar lista dos veces
        _listaDisparos.removeLast();
      }
    });
  }

  bool get _puedePuntuarManual {
    if (!_haIniciado) return false;
    // En fuego o en pausa (stop tras haber iniciado).
    return _faseActual == FaseSesion.fuego ||
        _faseActual == FaseSesion.stop;
  }

  void _registrarPuntoManual(int valor, {bool esMosca = false}) {
    if (!_puedePuntuarManual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solo puedes puntuar en FUEGO o en pausa.'),
          duration: Duration(milliseconds: 900),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_serieCompleta) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Serie completa · $_disparosActuales/$_maxDisparosSerie',
          ),
          duration: const Duration(milliseconds: 1200),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      // ignore: unawaited_futures
      _audioService.avisarSerieCompleta(
        actual: _disparosActuales,
        maximo: _maxDisparosSerie,
      );
      return;
    }

    final puntos = esMosca ? 10 : valor.clamp(0, 10);
    setState(() {
      _puntosTotal += puntos;
      if (esMosca) _contadorMoscas++;
      _listaDisparos.add(
        Disparo(
          numero: _listaDisparos.length + 1,
          x: 0,
          y: 0,
          puntuacion: puntos.toDouble(),
          esMosca: esMosca,
        ),
      );
    });
  }

  String _etiquetaMarca(Disparo d) {
    if (d.esMosca) return 'X';
    final v = d.puntuacion;
    if (widget.plantilla.puntuacionDecimal && v != v.roundToDouble()) {
      return v.toStringAsFixed(1);
    }
    return v.toInt().toString();
  }

  Widget _buildPanelPuntuacionManual() {
    final botones = <Widget>[
      _botonPuntoManual(
        label: 'X',
        color: Colors.amber.shade800,
        onTap: () => _registrarPuntoManual(10, esMosca: true),
      ),
      for (int v = 10; v >= 0; v--)
        _botonPuntoManual(
          label: '$v',
          color: v >= 9
              ? Colors.green.shade700
              : (v >= 7 ? Colors.blueGrey.shade700 : Colors.blueGrey.shade500),
          onTap: () => _registrarPuntoManual(v),
        ),
    ];

    return ColoredBox(
      color: const Color(0xFF2A2A2A),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'PUNTUACIÓN MANUAL',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                _chipContadorTiros(compact: true),
              ],
            ),
          ),
          Expanded(
            child: _listaDisparos.isEmpty
                ? const Center(
                    child: Text(
                      'Pulsa X o 10…0 para registrar tiros',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    reverse: true,
                    itemCount: _listaDisparos.length,
                    itemBuilder: (context, index) {
                      final d = _listaDisparos[
                          _listaDisparos.length - 1 - index];
                      return Card(
                        color: d.esMosca
                            ? Colors.amber.withValues(alpha: 0.15)
                            : Colors.white10,
                        child: ListTile(
                          dense: true,
                          leading: Text(
                            '#${d.numero}',
                            style: const TextStyle(color: Colors.white54),
                          ),
                          title: Text(
                            _etiquetaMarca(d),
                            style: TextStyle(
                              color: d.esMosca
                                  ? Colors.amberAccent
                                  : Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          trailing: d.esMosca
                              ? const Text(
                                  'MOSCA',
                                  style: TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: botones,
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonPuntoManual({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 52,
      height: 48,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _guardarYSalir() async {
    // Competición / series encadenadas: devolver resultado y salir.
    if (widget.onCompletar != null) {
      widget.onCompletar!(_listaDisparos, _puntosTotal);
      if (mounted) Navigator.pop(context);
      return;
    }

    final partesNota = <String>[];
    if (widget.municion != null) {
      partesNota.add('${widget.municion!.marca} (${widget.municion!.lote})');
    }
    if (widget.usarEntradaManualPuntos) {
      partesNota.add('Entrada: Manual');
    }

    final sesion = Sesion(
      fecha: DateTime.now(),
      idEquipo: widget.equipo.id,
      idPlantilla: widget.plantilla.id!,
      idMunicion: widget.municion?.id,
      nota: partesNota.isEmpty ? null : partesNota.join(' · '),
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
      esCorreccionMira: widget.esCorreccionMira,
    );

    await _entrenamientoService.guardarSesionCompleta(sesion, _listaDisparos);
    if (!mounted) return;

    final puntosGuardados = _puntosTotal;
    final disparosGuardados = _listaDisparos.length;

    final accion = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Entrenamiento guardado'),
        content: Text(
          'Puntuación: $puntosGuardados pts · $disparosGuardados disparos.\n\n'
          '¿Qué quieres hacer ahora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'menu'),
            child: const Text('Volver al menú'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'nuevo'),
            child: const Text('Nuevo entrenamiento'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (accion == 'nuevo') {
      _prepararNuevaSerie();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesión guardada. Lista para un nuevo entrenamiento.'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Guardado')),
      );
    }
  }

  void _prepararNuevaSerie() {
    _pausar();
    _inspeccionController.value = Matrix4.identity();
    setState(() {
      _listaDisparos.clear();
      _puntosVisuales.clear();
      _puntosTotal = 0;
      _contadorMoscas = 0;
      _contadorSeriesDuelo = 0;
      _modoInspeccion = false;
      _mostrandoLupa = false;
      _posicionDedo = null;
      _posicionGlobalPuntero = null;
      _resetearValoresTiempo();
    });
  }

  void _reiniciarSerie() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Reiniciar Serie?'),
        content: const Text(
            'Se borrarán los disparos actuales y el cronómetro volverá al inicio.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _prepararNuevaSerie();
            },
            child: const Text('Reiniciar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Gestos Lupa — coordenadas respecto al CustomPaint real (no offset estimado).
  Offset? _localEnDiana(Offset globalPosition) {
    final box =
        _dianaPaintKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.globalToLocal(globalPosition);
  }

  Offset? _localEnStack(Offset globalPosition) {
    final box =
        _dianaStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.globalToLocal(globalPosition);
  }

  void _actualizarPuntero(Offset globalPosition) {
    final local = _localEnDiana(globalPosition);
    if (local == null) return;
    setState(() {
      _posicionGlobalPuntero = globalPosition;
      _posicionDedo = local;
    });
  }

  void _onPanStart(DragStartDetails d, Size size) {
    _impactoRegistradoEnPan = false;
    setState(() => _mostrandoLupa = true);
    _actualizarPuntero(d.globalPosition);
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    _actualizarPuntero(d.globalPosition);
  }

  void _onPanEnd(DragEndDetails d, Size size) {
    final local = _posicionDedo;
    setState(() {
      _mostrandoLupa = false;
      _posicionGlobalPuntero = null;
    });
    if (local != null) {
      _impactoRegistradoEnPan = true;
      _registrarImpacto(local, size);
    }
  }

  void _onTapUp(TapUpDetails d, Size size) {
    if (_impactoRegistradoEnPan) {
      _impactoRegistradoEnPan = false;
      return;
    }
    final local = _localEnDiana(d.globalPosition);
    if (local != null) _registrarImpacto(local, size);
  }


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
                  title: TiroAmgAppBarTitle(
                    section: widget.tituloSerie ?? widget.plantilla.nombreDisciplina,
                  ),
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  iconTheme: const IconThemeData(color: Colors.white),
                  actionsIconTheme: const IconThemeData(color: Colors.white),
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
        Expanded(
          child: widget.usarEntradaManualPuntos
              ? _buildPanelPuntuacionManual()
              : _buildDianaArea(),
        ),
        _buildControlesBar(),
      ],
    );
  }

  Widget _buildLandscapeBody() {
    return SafeArea(
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: widget.usarEntradaManualPuntos
                ? _buildPanelPuntuacionManual()
                : _buildDianaArea(),
          ),
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
          _chipContadorTiros(),
          const SizedBox(width: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      color: Colors.grey[900],
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.red, size: 26),
            onPressed: _reiniciarSerie,
            tooltip: 'Reiniciar',
          ),
          if (!widget.usarEntradaManualPuntos) _botonLupaInspeccion(),
          _botonModoSerieLibre(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onPressed: _iniciarSecuencia,
                child: Text(_enCurso ? 'PAUSA' : 'INICIAR'),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.undo, color: Colors.white, size: 26),
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
          const SizedBox(height: 4),
          Center(child: _chipContadorTiros(compact: true)),
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
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.red),
                  onPressed: _reiniciarSerie,
                  tooltip: 'Reiniciar',
                ),
                if (!widget.usarEntradaManualPuntos) _botonLupaInspeccion(),
                _botonModoSerieLibre(compact: true),
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
      final size = Size(diametro, diametro);

      final dianaCore = Center(
        child: SizedBox(
          width: diametro,
          height: diametro,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                key: _dianaPaintKey,
                size: size,
                painter: DianaPainter(
                  impactos: _puntosVisuales,
                  valorMinimo: _valorMinimo,
                  anilloNegroInicio: _anilloNegroInicio,
                  esFondoNegro: _esFondoNegro,
                  tieneMosca: _tieneMosca,
                  tieneGuias: _tieneGuias,
                  esEstiloDuelo: _esEstiloDuelo,
                  nombreCalibre: widget.equipo.nombreCalibre,
                ),
              ),
              if (_faseActual == FaseSesion.fuego)
                IgnorePointer(
                  child: CustomPaint(
                    size: size,
                    painter: _BordeFuegoPainter(
                      color: _cuentaAtrasFinal
                          ? (_pulsoFinal
                              ? Colors.orangeAccent
                              : Colors.greenAccent)
                          : Colors.greenAccent,
                      grosor: _cuentaAtrasFinal
                          ? (_pulsoFinal ? 8.0 : 5.0)
                          : 5.0,
                      pulso: _pulsoFinal,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

      return Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          if (_modoInspeccion)
            InteractiveViewer(
              transformationController: _inspeccionController,
              minScale: 1.0,
              maxScale: 6.0,
              boundaryMargin: const EdgeInsets.all(160),
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: dianaCore,
              ),
            )
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _onPanStart(d, size),
              onPanUpdate: (d) => _onPanUpdate(d, size),
              onPanEnd: (d) => _onPanEnd(d, size),
              onTapUp: (d) => _onTapUp(d, size),
              child: Stack(
                key: _dianaStackKey,
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  dianaCore,
                  if (_mostrandoLupa &&
                      _posicionDedo != null &&
                      _posicionGlobalPuntero != null &&
                      !_dianaCerrada)
                    Builder(
                      builder: (context) {
                        final enStack =
                            _localEnStack(_posicionGlobalPuntero!);
                        final stackBox = _dianaStackKey.currentContext
                            ?.findRenderObject() as RenderBox?;
                        if (enStack == null ||
                            stackBox == null ||
                            !stackBox.hasSize) {
                          return const SizedBox.shrink();
                        }

                        final stackSize = stackBox.size;
                        final margen = _lupaRadio + _lupaDesfaseY + 8;
                        final ponerAbajo = enStack.dy < margen;
                        final ponerArribaBorde =
                            enStack.dy > stackSize.height - margen;
                        final dyLoupe = (ponerAbajo && !ponerArribaBorde)
                            ? _lupaDesfaseY
                            : -_lupaDesfaseY;

                        var dxLoupe = 0.0;
                        if (enStack.dx < margen) {
                          dxLoupe = _lupaDesfaseY * 0.55;
                        } else if (enStack.dx >
                            stackSize.width - margen) {
                          dxLoupe = -_lupaDesfaseY * 0.55;
                        }

                        return Positioned(
                          left: enStack.dx + dxLoupe - _lupaRadio,
                          top: enStack.dy + dyLoupe - _lupaRadio,
                          child: IgnorePointer(
                            child: RawMagnifier(
                              size: const Size(
                                  _lupaRadio * 2, _lupaRadio * 2),
                              magnificationScale: 2.5,
                              focalPointOffset:
                                  Offset(-dxLoupe, -dyLoupe),
                              decoration: MagnifierDecoration(
                                shape: CircleBorder(
                                  side: BorderSide(
                                    color: Colors.white
                                        .withValues(alpha: 0.95),
                                    width: 2.5,
                                  ),
                                ),
                                shadows: const [
                                  BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 8,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const CustomPaint(
                                size: Size(_lupaRadio * 2, _lupaRadio * 2),
                                painter: _CruzLupaPainter(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          if (_modoInspeccion)
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.amberAccent.withValues(alpha: 0.7),
                      ),
                    ),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      child: Text(
                        'INSPECCIÓN · pellizca o arrastra',
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (overlayOnDiana && _faseActual == FaseSesion.fuego && !_modoInspeccion)
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
        ],
      );
    });
  }
}

/// Solo el anillo de “fuego” (trazo + glow); no rellena la diana.
class _BordeFuegoPainter extends CustomPainter {
  final Color color;
  final double grosor;
  final bool pulso;

  const _BordeFuegoPainter({
    required this.color,
    required this.grosor,
    required this.pulso,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - grosor / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = color.withValues(alpha: pulso ? 0.45 : 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = grosor + (pulso ? 14 : 10)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, pulso ? 16 : 10),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = grosor,
    );
  }

  @override
  bool shouldRepaint(covariant _BordeFuegoPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.grosor != grosor ||
      oldDelegate.pulso != pulso;
}

/// Cruz de mira en el centro exacto de la lupa (sin icono Material descentrado).
class _CruzLupaPainter extends CustomPainter {
  const _CruzLupaPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    const half = 10.0;
    final paint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(c.dx - half, c.dy), Offset(c.dx + half, c.dy), paint);
    canvas.drawLine(Offset(c.dx, c.dy - half), Offset(c.dx, c.dy + half), paint);
    canvas.drawCircle(
      c,
      2.2,
      Paint()..color = Colors.redAccent,
    );
  }

  @override
  bool shouldRepaint(covariant _CruzLupaPainter oldDelegate) => false;
}

class DianaPainter extends CustomPainter {
  final List<Offset> impactos;
  final int valorMinimo;
  final int anilloNegroInicio;
  final bool esFondoNegro;
  final bool tieneMosca;
  final bool tieneGuias;
  final bool esEstiloDuelo;
  final String? nombreCalibre;

  DianaPainter({
    required this.impactos,
    required this.valorMinimo,
    required this.anilloNegroInicio,
    required this.esFondoNegro,
    required this.tieneMosca,
    required this.tieneGuias,
    required this.esEstiloDuelo,
    this.nombreCalibre,
  });

  /// Radio del impacto respecto al ancho de un anillo de puntuación.
  /// (vía ImpactoVisual, misma referencia que historial/análisis)

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Fondo
    final paintFondo = Paint()
      ..color =
          esFondoNegro ? const Color(0xFF1A1A1A) : const Color(0xFFF5F3E0)
      ..style = PaintingStyle.fill;
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
    
    // 5. Impactos encima de números (tapa local + doble contraste)
    final radioImpacto = ImpactoVisual.radioPx(
      anchoZona: anchoZona,
      nombreCalibre: nombreCalibre,
    );
    for (final p in impactos) {
      ImpactoVisual.dibujar(canvas, p, radioImpacto);
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
  bool shouldRepaint(covariant DianaPainter oldDelegate) =>
      oldDelegate.impactos != impactos ||
      oldDelegate.nombreCalibre != nombreCalibre ||
      oldDelegate.valorMinimo != valorMinimo ||
      oldDelegate.anilloNegroInicio != anilloNegroInicio ||
      oldDelegate.esFondoNegro != esFondoNegro ||
      oldDelegate.tieneMosca != tieneMosca ||
      oldDelegate.tieneGuias != tieneGuias ||
      oldDelegate.esEstiloDuelo != esEstiloDuelo;
}