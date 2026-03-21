import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../constants/diana_layout.dart';
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
  final Function(List<Disparo> disparos, double puntos)? onCompletar;
  final bool usarPuntuacionDecimal;
  final bool usarEntradaManualPuntos;

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
    this.usarPuntuacionDecimal = false,
    this.usarEntradaManualPuntos = false,
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

  double _puntosTotal = 0;

  // Configuración Diana
  int _valorMinimo = 1;
  int _anilloNegroInicio = 7;
  bool _esFondoNegro = false;
  bool _tieneMosca = true;
  bool _tieneGuias = false;
  bool _esEstiloDuelo = false;
  double? _dianaAnchoExteriorMm;
  double? _calibreMm;
  bool _mostrarCartulina = false;
  bool _cargando = true;

  // Estado Crono
  Timer? _timer;
  FaseSesion _faseActual = FaseSesion.stop;
  String _mensajeEstado = "LISTO";
  int _segundosRestantes = 0;
  Color _colorEstado = Colors.grey;
  bool _haIniciado = false;
  bool _estaPausado = false;

  // Control de Duelo
  int _contadorSeriesDuelo = 0;

  // Lupa
  Offset? _posicionDedo;
  bool _mostrandoLupa = false;
  int? _indiceTiroEnAjuste;
  double _pasoAjuste = 0.01;
  bool _recalcularPuntosAjuste = true;

  bool get _enCurso =>
      !_estaPausado &&
      _faseActual != FaseSesion.stop &&
      _faseActual != FaseSesion.fin;
  bool get _puedeReanudar =>
      _estaPausado &&
      _faseActual != FaseSesion.stop &&
      _faseActual != FaseSesion.fin;
  bool get _ajusteActivo =>
      _indiceTiroEnAjuste != null &&
      _indiceTiroEnAjuste! >= 0 &&
      _indiceTiroEnAjuste! < _listaDisparos.length;

  /// Tiros previstos por la plantilla (una serie en esta pantalla).
  int get _tirosPrevistos => widget.plantilla.disparosPorSerie;

  int get _tirosRegistrados => _listaDisparos.length;

  /// Progreso de la serie (0–1); con tiros extra se mantiene en 1.
  double get _progresoTirosSerie {
    final m = _tirosPrevistos;
    if (m <= 0) return 0;
    return (_tirosRegistrados / m).clamp(0.0, 1.0);
  }

  Color get _colorBarraProgresoSerie {
    final m = _tirosPrevistos;
    final n = _tirosRegistrados;
    if (m <= 0) return Colors.tealAccent.shade200;
    if (n > m) return Colors.orange.shade400;
    if (n >= m) return Colors.lightGreenAccent;
    return Colors.tealAccent.shade200;
  }

  void _mostrarFeedbackConteoTiros(int totalTrasAnadir) {
    final m = _tirosPrevistos;
    if (m <= 0 || !mounted) return;
    if (totalTrasAnadir == m) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Serie completada: $m/$m disparos.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (totalTrasAnadir == m + 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tiro extra: la plantilla prevé $m disparos por serie. Puedes seguir registrando.',
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildContadorTirosSerie(bool narrow) {
    final m = _tirosPrevistos;
    final n = _tirosRegistrados;
    if (m <= 0) {
      return Row(
        children: [
          Icon(Icons.adjust, size: narrow ? 16 : 18, color: Colors.white54),
          const SizedBox(width: 8),
          Text(
            '$n tiros registrados',
            style: TextStyle(
              color: Colors.white70,
              fontSize: narrow ? 12 : 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    final filaSerie = Row(
      children: [
        Icon(Icons.adjust, size: narrow ? 16 : 18, color: Colors.white54),
        const SizedBox(width: 8),
        Text(
          'SERIE',
          style: TextStyle(
            color: Colors.white54,
            fontSize: narrow ? 10 : 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const Spacer(),
        Text(
          '$n / $m',
          style: TextStyle(
            color: Colors.white,
            fontSize: narrow ? 16 : 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );

    // En curso: solo N/M (evita redundancia con "Quedan X").
    if (n < m) {
      return filaSerie;
    }

    final extras = n - m;
    final String estado;
    final Color estadoColor;
    if (n == m) {
      estado = 'Serie completa';
      estadoColor = Colors.lightGreenAccent;
    } else {
      estado = extras == 1 ? '1 tiro extra' : '$extras tiros extra';
      estadoColor = Colors.orange.shade200;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        filaSerie,
        const SizedBox(height: 4),
        Text(
          estado,
          style: TextStyle(
            color: estadoColor,
            fontSize: narrow ? 11 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _formatearPuntos(double value) {
    if (!widget.usarPuntuacionDecimal) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }

  double? _resolverCalibreMm(String? calibreMunicion, String? calibreEquipo) {
    final fromMunicion = _extraerCalibreMm(calibreMunicion);
    if (fromMunicion != null) {
      return fromMunicion;
    }
    return _extraerCalibreMm(calibreEquipo);
  }

  double? _extraerCalibreMm(String? texto) {
    if (texto == null || texto.trim().isEmpty) {
      return null;
    }
    final source = texto.toLowerCase().replaceAll(',', '.');

    final mmMatch = RegExp(r'(\d+(?:\.\d+)?)\s*mm').firstMatch(source);
    if (mmMatch != null) {
      final value = double.tryParse(mmMatch.group(1)!);
      if (value != null && value >= 2.0 && value <= 20.0) {
        return value;
      }
    }

    final inchMatch = RegExp(r'(?<!\d)\.(\d{2,3})(?!\d)').firstMatch(source);
    if (inchMatch != null) {
      final raw = inchMatch.group(1)!;
      final inches =
          raw.length == 2 ? int.parse(raw) / 100.0 : int.parse(raw) / 1000.0;
      final mm = inches * 25.4;
      if (mm >= 2.0 && mm <= 20.0) {
        return mm;
      }
    }

    return null;
  }

  double _calcularPuntuacionDesdeXY(double x, double y) {
    final distNorm = sqrt((x * x) + (y * y));
    if (distNorm > 1.0) {
      return 0;
    }

    // Compensación por calibre: si el borde del impacto toca la línea del anillo,
    // debe contar como el anillo superior.
    final radioCalibreNorm = _radioCalibreNormalizado();
    final distCompensada = (distNorm - radioCalibreNorm).clamp(0.0, 1.0);

    int totalZonas = 11 - _valorMinimo;
    double calculo = 11 - (distCompensada * totalZonas);
    if (widget.usarPuntuacionDecimal) {
      if (calculo < _valorMinimo) {
        return 0;
      }
      final decimal = (calculo.clamp(0, 10.9) * 10).round() / 10.0;
      return decimal;
    }

    int entero = calculo.floor();
    if (entero < _valorMinimo) {
      entero = 0;
    }
    if (entero > 10) {
      entero = 10;
    }
    return entero.toDouble();
  }

  double _radioCalibreNormalizado() {
    if (_calibreMm == null ||
        _dianaAnchoExteriorMm == null ||
        _calibreMm! <= 0 ||
        _dianaAnchoExteriorMm! <= 0) {
      return 0.0;
    }
    // radioNorm = (diamImpacto/2) / (diamDiana/2) = diamImpacto/diamDiana
    return (_calibreMm! / _dianaAnchoExteriorMm!).clamp(0.0, 0.2);
  }

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
        final dianaConfig =
            dianas.firstWhere((d) => d.id == widget.plantilla.idTipoDiana);
        setState(() {
          _valorMinimo = dianaConfig.valorMinimo;
          _anilloNegroInicio = dianaConfig.anilloNegroInicio;
          _esFondoNegro = dianaConfig.esFondoNegro;
          _tieneMosca = dianaConfig.tieneMosca;
          _tieneGuias = dianaConfig.tieneGuias;
          _esEstiloDuelo = _valorMinimo >= 5;
          _dianaAnchoExteriorMm = dianaConfig.anchoExteriorMm;
          _mostrarCartulina = dianaConfig.mostrarCartulina;
          _calibreMm = _resolverCalibreMm(
            widget.municion?.nombreCalibre,
            widget.equipo.nombreCalibre,
          );
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
    _estaPausado = false;
    _contadorSeriesDuelo = 0;
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

    if (_puedeReanudar) {
      _reanudar();
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
      _estaPausado = true;
      _mensajeEstado = "PAUSADO";
      _colorEstado = Colors.orange;
    });
  }

  void _reanudar() {
    if (!_puedeReanudar) return;
    setState(() {
      _estaPausado = false;
      if (_faseActual == FaseSesion.preparacion) {
        _mensajeEstado = "PREPARACIÓN";
        _colorEstado = Colors.amber[800]!;
      } else if (_faseActual == FaseSesion.espera) {
        _mensajeEstado = "ATENCIÓN (ESPERA)";
        _colorEstado = Colors.red[700]!;
      } else if (_faseActual == FaseSesion.fuego) {
        _mensajeEstado = "¡FUEGO!";
        _colorEstado = Colors.green[600]!;
      }
    });
    _iniciarTicker();
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
    _estaPausado = false;
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
  bool _puedeRegistrarDisparoConFeedback() {
    if (!_haIniciado) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Inicia la serie para poder puntuar.'),
        duration: Duration(milliseconds: 700),
      ));
      return false;
    }

    // En pausa se permite puntuar para cargar impactos manualmente.
    if (_estaPausado) {
      return true;
    }

    if (_faseActual != FaseSesion.fuego) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ahora no se puede puntuar.'),
          duration: Duration(milliseconds: 500),
          backgroundColor: Colors.red));
      return false;
    }

    return true;
  }

  void _registrarImpacto(Offset localPosition, Size tamanoDiana) {
    if (widget.usarEntradaManualPuntos) return;
    if (_ajusteActivo) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Finaliza el ajuste para poder registrar nuevos impactos.'),
        duration: Duration(milliseconds: 700),
      ));
      return;
    }
    if (!_puedeRegistrarDisparoConFeedback()) return;

    final centro = Offset(tamanoDiana.width / 2, tamanoDiana.height / 2);
    final radioMax =
        radioPuntuacionPx(tamanoDiana.width / 2, _mostrarCartulina);
    final pos = _normalizarPosicionEnDiana(localPosition, tamanoDiana);
    final xn = (pos.dx - centro.dx) / radioMax;
    final yn = (pos.dy - centro.dy) / radioMax;
    final distNorm = sqrt(xn * xn + yn * yn);
    final valor = _calcularPuntuacionDesdeXY(xn, yn);
    final esFuera = distNorm > 1.0;

    setState(() {
      _puntosTotal += valor;

      _listaDisparos.add(Disparo(
        numero: _listaDisparos.length + 1,
        x: xn,
        y: yn,
        puntuacion: valor,
        esMosca: false,
        esFuera: esFuera,
      ));
    });
    final n = _listaDisparos.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mostrarFeedbackConteoTiros(n);
      if (esFuera) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fuera del blanco: 0 puntos.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  /// Registra un tiro explícitamente fuera del círculo de puntuación (0, marcado como F).
  void _registrarDisparoFuera() {
    if (widget.usarEntradaManualPuntos) return;
    if (_ajusteActivo) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Finaliza el ajuste para registrar nuevos tiros.'),
        duration: Duration(milliseconds: 700),
      ));
      return;
    }
    if (!_puedeRegistrarDisparoConFeedback()) return;

    const xFuera = 1.45;
    const yFuera = 0.0;

    setState(() {
      _listaDisparos.add(Disparo(
        numero: _listaDisparos.length + 1,
        x: xFuera,
        y: yFuera,
        puntuacion: 0,
        esMosca: false,
        esFuera: true,
      ));
    });
    final n = _listaDisparos.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mostrarFeedbackConteoTiros(n);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tiro fuera del blanco registrado (0).'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  void _agregarDisparoManual(double puntuacion, {bool esMosca = false}) {
    if (!_puedeRegistrarDisparoConFeedback()) return;
    final valor = puntuacion.clamp(0.0, 10.0);
    setState(() {
      _puntosTotal += valor;
      _listaDisparos.add(Disparo(
        numero: _listaDisparos.length + 1,
        x: 0,
        y: 0,
        puntuacion: valor,
        esMosca: esMosca,
        esFuera: false,
      ));
    });
    final n = _listaDisparos.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mostrarFeedbackConteoTiros(n);
    });
  }

  String _formatearMarcaDisparo(Disparo disparo) {
    if (disparo.esFuera) return 'F';
    if (disparo.esMosca) return 'X';
    if (disparo.puntuacion % 1 == 0) return disparo.puntuacion.toInt().toString();
    return disparo.puntuacion.toStringAsFixed(1);
  }

  void _borrarUltimo() {
    if (_listaDisparos.isNotEmpty) {
      setState(() {
        _puntosTotal -= _listaDisparos.last.puntuacion;
        _listaDisparos.removeLast();
        if (_indiceTiroEnAjuste != null) {
          if (_listaDisparos.isEmpty) {
            _indiceTiroEnAjuste = null;
          } else if (_indiceTiroEnAjuste! >= _listaDisparos.length) {
            _indiceTiroEnAjuste = _listaDisparos.length - 1;
          }
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

    final notaBase = widget.municion != null
        ? "${widget.municion!.marca} (${widget.municion!.lote})"
        : null;
    final notaFinal = widget.usarEntradaManualPuntos
        ? (notaBase == null || notaBase.isEmpty
            ? 'Entrada: Manual'
            : '$notaBase | Entrada: Manual')
        : notaBase;

    final sesion = Sesion(
      fecha: DateTime.now(),
      idEquipo: widget.equipo.id,
      idPlantilla: widget.plantilla.id!,
      idMunicion: widget.municion?.id,
      nota: notaFinal,
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Guardado")));
    }
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
              _pausar();
              setState(() {
                _listaDisparos.clear();
                _puntosTotal = 0.0;
                _indiceTiroEnAjuste = null;
                _resetearValoresTiempo();
              });
            },
            child:
                const Text('Reiniciar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Gestos Lupa
  Offset _normalizarPosicionEnDiana(Offset p, Size size) {
    final x = p.dx.clamp(0.0, size.width);
    final y = p.dy.clamp(0.0, size.height);
    return Offset(x, y);
  }

  void _onPanStart(DragStartDetails d, Offset offset, Size size) {
    if (widget.usarEntradaManualPuntos) return;
    final pos = _normalizarPosicionEnDiana(d.localPosition - offset, size);
    setState(() {
      _mostrandoLupa = true;
      _posicionDedo = pos;
    });
    if (_ajusteActivo) {
      _ajustarTiroEnAjusteDesdePosicion(pos, size);
    }
  }

  void _onPanUpdate(DragUpdateDetails d, Offset offset, Size size) {
    if (widget.usarEntradaManualPuntos) return;
    final pos = _normalizarPosicionEnDiana(d.localPosition - offset, size);
    setState(() {
      _posicionDedo = pos;
    });
    if (_ajusteActivo) {
      _ajustarTiroEnAjusteDesdePosicion(pos, size);
    }
  }

  void _onPanEnd(DragEndDetails d, Offset offset, Size size) {
    if (widget.usarEntradaManualPuntos) return;
    final pos = _posicionDedo;
    setState(() {
      _mostrandoLupa = false;
    });
    if (pos == null) return;
    if (_ajusteActivo) {
      _ajustarTiroEnAjusteDesdePosicion(pos, size);
      return;
    }
    _registrarImpacto(pos, size);
  }

  void _onTapUp(TapUpDetails d, Offset offset, Size size) {
    if (widget.usarEntradaManualPuntos) return;
    final pos = _normalizarPosicionEnDiana(d.localPosition - offset, size);
    if (_ajusteActivo) {
      _ajustarTiroEnAjusteDesdePosicion(pos, size);
      return;
    }
    _registrarImpacto(pos, size);
  }

  Future<void> _seleccionarTiroParaAjuste() async {
    if (_listaDisparos.isEmpty) {
      return;
    }

    var tiroSeleccionadoNumero = _listaDisparos.last.numero;
    final elegido = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Seleccionar tiro a ajustar'),
          content: DropdownButtonFormField<int>(
            initialValue: tiroSeleccionadoNumero,
            decoration: const InputDecoration(
              labelText: 'Tiro',
              border: OutlineInputBorder(),
            ),
            items: _listaDisparos.reversed
                .map(
                  (d) => DropdownMenuItem<int>(
                    value: d.numero,
                    child: Text(
                        '#${d.numero} · ${_formatearPuntos(d.puntuacion)} pts'),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) {
                return;
              }
              setDialogState(() => tiroSeleccionadoNumero = v);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, tiroSeleccionadoNumero),
              child: const Text('Ajustar'),
            ),
          ],
        ),
      ),
    );

    if (elegido == null) {
      return;
    }
    final index = _listaDisparos.indexWhere((d) => d.numero == elegido);
    if (index < 0) {
      return;
    }
    setState(() => _indiceTiroEnAjuste = index);
  }

  void _ajustarUltimoTiroDirecto() {
    if (_listaDisparos.isEmpty) {
      return;
    }
    setState(() => _indiceTiroEnAjuste = _listaDisparos.length - 1);
  }

  void _moverTiroEnAjuste(double dx, double dy) {
    final idx = _indiceTiroEnAjuste;
    if (idx == null || idx < 0 || idx >= _listaDisparos.length) {
      return;
    }
    final tiro = _listaDisparos[idx];
    final x = tiro.x + dx;
    final y = tiro.y + dy;
    final nuevaPuntuacion = _recalcularPuntosAjuste
        ? _calcularPuntuacionDesdeXY(x, y)
        : tiro.puntuacion;
    final esFuera = _recalcularPuntosAjuste
        ? (sqrt(x * x + y * y) > 1.0)
        : tiro.esFuera;
    setState(() {
      _listaDisparos[idx] = Disparo(
        id: tiro.id,
        idSesion: tiro.idSesion,
        numero: tiro.numero,
        x: x,
        y: y,
        puntuacion: nuevaPuntuacion,
        esMosca: tiro.esMosca,
        esFuera: esFuera,
      );
      _puntosTotal += (nuevaPuntuacion - tiro.puntuacion);
    });
  }

  void _ajustarTiroEnAjusteDesdePosicion(Offset localPosition, Size tamanoDiana) {
    final idx = _indiceTiroEnAjuste;
    if (idx == null || idx < 0 || idx >= _listaDisparos.length) {
      return;
    }

    final centro = Offset(tamanoDiana.width / 2, tamanoDiana.height / 2);
    final radioMax =
        radioPuntuacionPx(tamanoDiana.width / 2, _mostrarCartulina);
    final pos = _normalizarPosicionEnDiana(localPosition, tamanoDiana);
    final x = (pos.dx - centro.dx) / radioMax;
    final y = (pos.dy - centro.dy) / radioMax;

    final tiro = _listaDisparos[idx];
    final nuevaPuntuacion = _recalcularPuntosAjuste
        ? _calcularPuntuacionDesdeXY(x, y)
        : tiro.puntuacion;
    final esFuera = _recalcularPuntosAjuste
        ? (sqrt(x * x + y * y) > 1.0)
        : tiro.esFuera;

    setState(() {
      _listaDisparos[idx] = Disparo(
        id: tiro.id,
        idSesion: tiro.idSesion,
        numero: tiro.numero,
        x: x,
        y: y,
        puntuacion: nuevaPuntuacion,
        esMosca: tiro.esMosca,
        esFuera: esFuera,
      );
      _puntosTotal += (nuevaPuntuacion - tiro.puntuacion);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        backgroundColor: Colors.grey[900],
        body: const Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }
    
    final colorScheme = Theme.of(context).colorScheme;
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final usarControlesSuperpuestos =
        isLandscape && !widget.usarEntradaManualPuntos && !_ajusteActivo;
    final screenW = MediaQuery.sizeOf(context).width;
    // En apaisado/tablet ancho antes se ocultaban arma y cronómetro → parecían “desaparecer”.
    final compactLandscapeBars = isLandscape;
    final appBarUltraNarrow = screenW < 340;
    final appBarNarrow = screenW < 400;

    return Scaffold(
      backgroundColor: Colors.black, // Fondo ultra oscuro para contraste con la diana
      appBar: AppBar(
        title: Text(
          widget.tituloSerie ?? widget.plantilla.nombreDisciplina,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: appBarNarrow ? 15 : 18,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: screenW > 420,
        actions: [
          Padding(
            padding: EdgeInsets.only(
              right: appBarUltraNarrow ? 4 : 8,
              top: 8,
              bottom: 8,
            ),
            child: appBarUltraNarrow
                ? IconButton.filled(
                    onPressed: _guardarYSalir,
                    tooltip: 'Finalizar',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.stop_circle_rounded, size: 22),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _guardarYSalir,
                      icon: const Icon(Icons.stop_circle_rounded, size: 18),
                      label: const Text(
                        'FINALIZAR',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: appBarNarrow ? 10 : 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // BARRA SUPERIOR DE INFO (PUNTOS Y ARMA) — siempre en sesión (también apaisado)
            if (!_ajusteActivo)
              LayoutBuilder(
                builder: (context, c) {
                  final narrowCard = c.maxWidth < 400;
                  final ptsChip = Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: narrowCard ? 10 : 16,
                      vertical: narrowCard ? 6 : 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.stars_rounded,
                          color: Colors.amber,
                          size: narrowCard ? 18 : 20,
                        ),
                        SizedBox(width: narrowCard ? 6 : 8),
                        Text(
                          '${_formatearPuntos(_puntosTotal)} pts',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: narrowCard ? 17 : 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  );
                  const double kSerieBarHeight = 3;
                  final cardPadH = narrowCard ? 12.0 : 20.0;
                  final cardPadV = narrowCard
                      ? (compactLandscapeBars ? 8.0 : 12.0)
                      : (compactLandscapeBars ? 10.0 : 16.0);
                  final showSerieBar = _tirosPrevistos > 0;
                  final innerTopPad = showSerieBar
                      ? max(4.0, cardPadV - kSerieBarHeight)
                      : cardPadV;

                  return Container(
                    margin: EdgeInsets.symmetric(
                      horizontal: narrowCard ? 8 : 16,
                      vertical: compactLandscapeBars ? 4 : 8,
                    ),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade900.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showSerieBar)
                          LinearProgressIndicator(
                            value: _progresoTirosSerie,
                            minHeight: kSerieBarHeight,
                            backgroundColor: Colors.white.withValues(alpha: 0.07),
                            color: _colorBarraProgresoSerie,
                          ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            cardPadH,
                            innerTopPad,
                            cardPadH,
                            cardPadV,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (narrowCard)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      'ARMA ACTUAL',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.equipo.nombre,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: ptsChip,
                                    ),
                                  ],
                                )
                              else
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'ARMA ACTUAL',
                                            style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            widget.equipo.nombre,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    ptsChip,
                                  ],
                                ),
                              SizedBox(height: narrowCard ? 12 : 10),
                              _buildContadorTirosSerie(narrowCard),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

            // BARRA DEL CRONÓMETRO Y ESTADO M3 — siempre en sesión (también apaisado)
            if (!_ajusteActivo)
              LayoutBuilder(
                builder: (context, c) {
                  final narrowTimer = c.maxWidth < 400;
                  final skipBtn = _enCurso
                      ? IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.skip_next_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: _avanzarFaseManual,
                          tooltip: 'Saltar tiempo actual',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.1),
                            minimumSize: const Size(40, 40),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                      : null;
                  final estadoCol = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _mensajeEstado,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _colorEstado,
                          fontWeight: FontWeight.bold,
                          fontSize: narrowTimer ? 12 : 14,
                          letterSpacing: narrowTimer ? 1.0 : 1.5,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$_segundosRestantes s',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: narrowTimer ? 22 : 28,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ],
                  );
                  return Container(
                    margin: EdgeInsets.symmetric(
                      horizontal: narrowTimer ? 8 : 16,
                      vertical: compactLandscapeBars ? 2 : 4,
                    ),
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: narrowTimer ? 10 : 16,
                      vertical: compactLandscapeBars
                          ? (narrowTimer ? 6 : 8)
                          : (narrowTimer ? 10 : 12),
                    ),
                    decoration: BoxDecoration(
                      color: _colorEstado.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _colorEstado.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: narrowTimer
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: _colorEstado,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _estaPausado
                                          ? Icons.pause_rounded
                                          : _faseActual == FaseSesion.fuego
                                              ? Icons.whatshot_rounded
                                              : _faseActual == FaseSesion.preparacion
                                                  ? Icons.build_rounded
                                                  : _faseActual == FaseSesion.espera
                                                      ? Icons.pan_tool_rounded
                                                      : Icons.timer_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: estadoCol),
                                ],
                              ),
                              if (skipBtn != null)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: skipBtn,
                                ),
                            ],
                          )
                        : Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _colorEstado,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _estaPausado
                                      ? Icons.pause_rounded
                                      : _faseActual == FaseSesion.fuego
                                          ? Icons.whatshot_rounded
                                          : _faseActual == FaseSesion.preparacion
                                              ? Icons.build_rounded
                                              : _faseActual == FaseSesion.espera
                                                  ? Icons.pan_tool_rounded
                                                  : Icons.timer_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(child: estadoCol),
                              if (skipBtn != null) skipBtn,
                            ],
                          ),
                  );
                },
              ),
            
            Expanded(
              child: widget.usarEntradaManualPuntos
                  ? _buildAreaPuntuacionManual()
                  : Stack(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            isLandscape
                                ? 6.0
                                : (screenW < 400 ? 8.0 : 16.0),
                            isLandscape
                                ? 4.0
                                : (screenW < 400 ? 8.0 : 16.0),
                            isLandscape
                                ? 6.0
                                : (screenW < 400 ? 8.0 : 16.0),
                            usarControlesSuperpuestos
                                ? 86.0
                                : (_ajusteActivo
                                    ? 6.0
                                    : (screenW < 400 ? 8.0 : 16.0)),
                          ),
                          child: LayoutBuilder(builder: (context, constraints) {
                        double diametro =
                            min(constraints.maxWidth, constraints.maxHeight);
                        double offX = (constraints.maxWidth - diametro) / 2;
                        double offY = (constraints.maxHeight - diametro) / 2;
                        Offset offsetCorrection = Offset(offX, offY);
                        Size size = Size(diametro, diametro);
                        final rScore =
                            radioPuntuacionPx(size.width / 2, _mostrarCartulina);
                        final cx = size.width / 2;
                        final cy = size.height / 2;
                        final impactosPixels = _listaDisparos
                            .map((d) =>
                                Offset((d.x * rScore) + cx, (d.y * rScore) + cy))
                            .toList();

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (d) => _onPanStart(d, offsetCorrection, size),
                          onPanUpdate: (d) => _onPanUpdate(d, offsetCorrection, size),
                          onPanEnd: (d) => _onPanEnd(d, offsetCorrection, size),
                          onTapUp: (d) => _onTapUp(d, offsetCorrection, size),
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Center(
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: _mostrarCartulina
                                        ? BoxShape.rectangle
                                        : BoxShape.circle,
                                    borderRadius: _mostrarCartulina
                                        ? BorderRadius.circular(24)
                                        : null,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.white
                                            .withValues(alpha: 0.05),
                                        blurRadius: 30,
                                        spreadRadius: 10,
                                      )
                                    ],
                                  ),
                                  child: CustomPaint(
                                    size: size,
                                    painter: DianaPainter(
                                      impactos: impactosPixels,
                                      valorMinimo: _valorMinimo,
                                      anilloNegroInicio: _anilloNegroInicio,
                                      esFondoNegro: _esFondoNegro,
                                      tieneMosca: _tieneMosca,
                                      tieneGuias: _tieneGuias,
                                      esEstiloDuelo: _esEstiloDuelo,
                                      diametroImpactoMm: _calibreMm,
                                      diametroDianaMm: _dianaAnchoExteriorMm,
                                      mostrarCartulina: _mostrarCartulina,
                                    ),
                                  ),
                                ),
                              ),

                              // LUPA
                              if (_mostrandoLupa && _posicionDedo != null)
                                Positioned(
                                  left: _posicionDedo!.dx + offX - 60,
                                  top: _posicionDedo!.dy + offY - 140,
                                  child: Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.black,
                                        border: Border.all(
                                            color: Colors.tealAccent, width: 3),
                                        boxShadow: [
                                          BoxShadow(
                                              color: Colors.tealAccent
                                                  .withValues(alpha: 0.3),
                                              blurRadius: 20,
                                              spreadRadius: 5)
                                        ]),
                                    child: ClipOval(
                                      child: OverflowBox(
                                        minWidth: 0,
                                        minHeight: 0,
                                        maxWidth: size.width,
                                        maxHeight: size.height,
                                        alignment: Alignment.topLeft,
                                        child: Transform(
                                          transform: Matrix4.identity()
                                            ..translateByDouble(60.0, 60.0, 0, 1)
                                            ..scaleByDouble(2.0, 2.0, 1.0, 1.0)
                                            ..translateByDouble(
                                                -_posicionDedo!.dx, -_posicionDedo!.dy, 0, 1),
                                          child: SizedBox(
                                            width: size.width,
                                            height: size.height,
                                            child: CustomPaint(
                                              size: size,
                                              painter: DianaPainter(
                                                impactos: impactosPixels,
                                                valorMinimo: _valorMinimo,
                                                anilloNegroInicio:
                                                    _anilloNegroInicio,
                                                esFondoNegro: _esFondoNegro,
                                                tieneMosca: _tieneMosca,
                                                tieneGuias: _tieneGuias,
                                                esEstiloDuelo: _esEstiloDuelo,
                                                diametroImpactoMm: _calibreMm,
                                                diametroDianaMm:
                                                    _dianaAnchoExteriorMm,
                                                mostrarCartulina:
                                                    _mostrarCartulina,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              if (_mostrandoLupa && _posicionDedo != null)
                                Positioned(
                                    left: _posicionDedo!.dx + offX - 60,
                                    top: _posicionDedo!.dy + offY - 140,
                                    child: const SizedBox(
                                        width: 120,
                                        height: 120,
                                        child: Center(
                                            child: Icon(Icons.add,
                                                color: Colors.redAccent,
                                                size: 24))))
                              ,
                              if (_mostrandoLupa && _posicionDedo != null)
                                Positioned(
                                  left: _posicionDedo!.dx + offX - 10,
                                  top: _posicionDedo!.dy + offY - 10,
                                  child: const Icon(
                                    Icons.add,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                )
                            ],
                          ),
                        );
                      }),
                        ),
                        if (usarControlesSuperpuestos)
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 8,
                            child: _buildBottomControlsBar(
                              colorScheme,
                              compact: true,
                              superpuesto: true,
                            ),
                          ),
                      ],
                    ),
            ),

            // PANEL DE LUPA ESTÁTICO DE AJUSTE
            if (!widget.usarEntradaManualPuntos &&
                _indiceTiroEnAjuste != null &&
                _indiceTiroEnAjuste! >= 0 &&
                _indiceTiroEnAjuste! < _listaDisparos.length)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade900,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              const TextSpan(text: 'Ajustando Tiro ', style: TextStyle(color: Colors.white70)),
                              TextSpan(text: '#${_listaDisparos[_indiceTiroEnAjuste!].numero}', style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                            ]
                          )
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            '${_formatearPuntos(_listaDisparos[_indiceTiroEnAjuste!].puntuacion)} pts',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 16),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _indiceTiroEnAjuste = null),
                          icon: const Icon(Icons.close_rounded, color: Colors.white54),
                          visualDensity: VisualDensity.compact,
                        )
                      ],
                    ),
                    const Divider(color: Colors.white24),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: Colors.tealAccent,
                      checkColor: Colors.black,
                      title: const Text('Autocalcular puntos al mover', style: TextStyle(fontSize: 13, color: Colors.white)),
                      value: _recalcularPuntosAjuste,
                      onChanged: (v) => setState(() => _recalcularPuntosAjuste = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 8),
                    // Controles de ajuste integrados (DPad)
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _buildStepButton('2%', 0.02),
                              _buildStepButton('1%', 0.01),
                              _buildStepButton('0.5%', 0.005),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _moverTiroEnAjuste(0, -_pasoAjuste),
                                icon: const Icon(Icons.arrow_drop_up_rounded, color: Colors.white, size: 32),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _moverTiroEnAjuste(-_pasoAjuste, 0),
                                    icon: const Icon(Icons.arrow_left_rounded, color: Colors.white, size: 32),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _moverTiroEnAjuste(_pasoAjuste, 0),
                                    icon: const Icon(Icons.arrow_right_rounded, color: Colors.white, size: 32),
                                  ),
                                ],
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _moverTiroEnAjuste(0, _pasoAjuste),
                                icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white, size: 32),
                              ),
                            ]
                          ),
                        )
                      ],
                    ),
                  ],
                ),
              ),

            // BOTONERA INFERIOR (CONTROLES DE SESIÓN)
            if (!_ajusteActivo && !usarControlesSuperpuestos)
              _buildBottomControlsBar(
                colorScheme,
                compact: isLandscape,
              )
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControlsBar(
    ColorScheme colorScheme, {
    required bool compact,
    bool superpuesto = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 400;
        final twoRows = constraints.maxWidth < 420;
        final tightIcons = compact || narrow;
        final microIcons = constraints.maxWidth < 320;
        final hPad = superpuesto
            ? (narrow ? 4.0 : 8.0)
            : (narrow ? 8.0 : 16.0);
        final gapCenter = narrow ? 4.0 : 8.0;

        final playButton = FilledButton.icon(
          onPressed: _iniciarSecuencia,
          icon: Icon(
            _enCurso ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: microIcons ? 20 : 22,
          ),
          label: Text(
            _enCurso
                ? 'PAUSA'
                : (_puedeReanudar ? 'CONTINUAR' : 'INICIAR'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: microIcons ? 0.5 : 1.0,
              fontSize: microIcons ? 12 : 14,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: _enCurso
                ? Colors.orange.shade700
                : (_puedeReanudar
                    ? Colors.green.shade700
                    : colorScheme.primary),
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: microIcons ? 8 : (narrow ? 10 : 16),
              vertical: compact ? 8 : (microIcons ? 10 : 16),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );

        Widget mainRow() => Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBottomButton(
                  icon: Icons.refresh_rounded,
                  color: Colors.redAccent,
                  onPressed: _reiniciarSerie,
                  tooltip: 'Reiniciar',
                  compact: tightIcons,
                  micro: microIcons,
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gapCenter),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: playButton,
                    ),
                  ),
                ),
                _buildBottomButton(
                  icon: Icons.undo_rounded,
                  color: Colors.white,
                  onPressed: _borrarUltimo,
                  tooltip: 'Deshacer último tiro',
                  compact: tightIcons,
                  micro: microIcons,
                ),
              ],
            );

        Widget secondRow() => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildBottomButton(
                  icon: Icons.my_location_rounded,
                  color: Colors.amberAccent,
                  onPressed: widget.usarEntradaManualPuntos
                      ? null
                      : (_listaDisparos.isEmpty
                          ? null
                          : _ajustarUltimoTiroDirecto),
                  tooltip: 'Ajustar último tiro',
                  compact: tightIcons,
                  micro: microIcons,
                ),
                SizedBox(width: microIcons ? 8 : 16),
                _buildBottomButton(
                  icon: Icons.format_list_bulleted_rounded,
                  color: const Color(0xFF00E5FF),
                  onPressed: widget.usarEntradaManualPuntos
                      ? null
                      : (_listaDisparos.isEmpty
                          ? null
                          : _seleccionarTiroParaAjuste),
                  tooltip: 'Lista de tiros a ajustar',
                  compact: tightIcons,
                  micro: microIcons,
                ),
                SizedBox(width: microIcons ? 8 : 16),
                _buildBottomButton(
                  icon: Icons.highlight_off_rounded,
                  color: Colors.orangeAccent,
                  onPressed:
                      widget.usarEntradaManualPuntos ? null : _registrarDisparoFuera,
                  tooltip: 'Fuera del blanco (0)',
                  compact: tightIcons,
                  micro: microIcons,
                ),
              ],
            );

        return Container(
          margin: superpuesto
              ? EdgeInsets.zero
              : EdgeInsets.fromLTRB(
                  narrow ? 8 : 16,
                  compact ? 4 : 8,
                  narrow ? 8 : 16,
                  compact ? 8 : 16,
                ),
          padding: EdgeInsets.symmetric(
            horizontal: hPad,
            vertical: compact ? 6 : (twoRows ? 8 : 12),
          ),
          decoration: BoxDecoration(
            color: Colors.blueGrey.shade900
                .withValues(alpha: superpuesto ? 0.9 : 0.8),
            borderRadius: BorderRadius.circular(24),
            border: superpuesto
                ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                : null,
          ),
          child: twoRows
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    mainRow(),
                    SizedBox(height: compact ? 4 : 6),
                    secondRow(),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildBottomButton(
                      icon: Icons.refresh_rounded,
                      color: Colors.redAccent,
                      onPressed: _reiniciarSerie,
                      tooltip: 'Reiniciar',
                      compact: tightIcons,
                      micro: microIcons,
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: gapCenter),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.center,
                          child: playButton,
                        ),
                      ),
                    ),
                    _buildBottomButton(
                      icon: Icons.my_location_rounded,
                      color: Colors.amberAccent,
                      onPressed: widget.usarEntradaManualPuntos
                          ? null
                          : (_listaDisparos.isEmpty
                              ? null
                              : _ajustarUltimoTiroDirecto),
                      tooltip: 'Ajustar último tiro',
                      compact: tightIcons,
                      micro: microIcons,
                    ),
                    _buildBottomButton(
                      icon: Icons.format_list_bulleted_rounded,
                      color: const Color(0xFF00E5FF),
                      onPressed: widget.usarEntradaManualPuntos
                          ? null
                          : (_listaDisparos.isEmpty
                              ? null
                              : _seleccionarTiroParaAjuste),
                      tooltip: 'Lista de tiros a ajustar',
                      compact: tightIcons,
                      micro: microIcons,
                    ),
                    _buildBottomButton(
                      icon: Icons.highlight_off_rounded,
                      color: Colors.orangeAccent,
                      onPressed: widget.usarEntradaManualPuntos
                          ? null
                          : _registrarDisparoFuera,
                      tooltip: 'Fuera del blanco (0)',
                      compact: tightIcons,
                      micro: microIcons,
                    ),
                    _buildBottomButton(
                      icon: Icons.undo_rounded,
                      color: Colors.white,
                      onPressed: _borrarUltimo,
                      tooltip: 'Deshacer último tiro',
                      compact: tightIcons,
                      micro: microIcons,
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildAreaPuntuacionManual() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade900.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Puntuación por números',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              Text(
                _tirosPrevistos > 0
                    ? 'Tiros: ${_listaDisparos.length} / $_tirosPrevistos'
                    : 'Tiros: ${_listaDisparos.length}',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 12, // X + 10..0
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 56, // alto fijo para evitar overflow en horizontal
            ),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildManualScoreButton(
                  label: 'X',
                  background: Colors.amber.shade700,
                  onTap: () => _agregarDisparoManual(10, esMosca: true),
                );
              }
              final score = 11 - index; // 10..0
              return _buildManualScoreButton(
                label: '$score',
                background: Colors.blueGrey.shade700,
                onTap: () => _agregarDisparoManual(score.toDouble()),
              );
            },
          ),
          const SizedBox(height: 6),
          Container(
            height: 92,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: _listaDisparos.isEmpty
                ? const Center(
                    child: Text(
                      'Sin marcas todavía',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _listaDisparos.map((disparo) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Text(
                              '${disparo.numero}: ${_formatearMarcaDisparo(disparo)}',
                              style: TextStyle(
                                color: disparo.esFuera
                                    ? Colors.orangeAccent
                                    : disparo.esMosca
                                        ? Colors.amberAccent
                                        : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualScoreButton({
    required String label,
    required Color background,
    required VoidCallback onTap,
  }) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _buildStepButton(String text, double value) {
    final isSelected = _pasoAjuste == value;
    return InkWell(
      onTap: () => setState(() => _pasoAjuste = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.tealAccent.withValues(alpha: 0.2) : Colors.transparent,
          border: Border.all(color: isSelected ? Colors.tealAccent : Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(color: isSelected ? Colors.tealAccent : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _buildBottomButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    required String tooltip,
    bool compact = false,
    bool micro = false,
  }) {
    final pad = micro ? 4.0 : (compact ? 6.0 : 12.0);
    final minSide = micro ? 36.0 : (compact ? 40.0 : 48.0);
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: onPressed == null ? Colors.white24 : color),
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.05),
        padding: EdgeInsets.all(pad),
        minimumSize: Size(minSide, minSide),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
  final double? diametroImpactoMm;
  final double? diametroDianaMm;
  final bool mostrarCartulina;

  DianaPainter({
    required this.impactos,
    required this.valorMinimo,
    required this.anilloNegroInicio,
    required this.esFondoNegro,
    required this.tieneMosca,
    required this.tieneGuias,
    required this.esEstiloDuelo,
    this.diametroImpactoMm,
    this.diametroDianaMm,
    this.mostrarCartulina = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    final radius = radioPuntuacionPx(maxR, mostrarCartulina);

    if (mostrarCartulina) {
      final cartulina = Paint()
        ..color = const Color(0xFFFFFEF5)
        ..style = PaintingStyle.fill;
      canvas.drawRect(Offset.zero & size, cartulina);
      final bordePapel = Paint()
        ..color = Colors.grey.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRect(Offset.zero & size, bordePapel);
    }

    // 1. Fondo del disco de puntuación
    final paintFondo = Paint()
      ..color = esFondoNegro ? const Color(0xFF1A1A1A) : const Color(0xFFF5F3E0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paintFondo);
    if (mostrarCartulina) {
      final bordeDisco = Paint()
        ..color = Colors.grey.shade500
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(center, radius, bordeDisco);
    }

    // 2. Anillos y Números
    int totalZonas = 11 - valorMinimo;
    double anchoZona = radius / totalZonas;

    final paintNegro = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    final paintLineaClara = Paint()
      ..color = Colors.grey[400]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final paintLineaBlanca = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // En dianas muy pequeñas, fuente y ejes reducidos para evitar solapamiento.
    final fontNumeros = (radius * 0.072).clamp(6.0, 14.0);
    final cuatroEjes = radius >= 34;

    for (int i = 0; i < totalZonas; i++) {
      int numeroAnillo = valorMinimo + i;
      double r = radius - (i * anchoZona);

      // Zona Negra
      if (numeroAnillo >= anilloNegroInicio) {
        canvas.drawCircle(center, r, paintNegro);
        canvas.drawCircle(center, r, paintLineaBlanca);
        // NÚMEROS BLANCOS EN ZONA NEGRA
        if (numeroAnillo < 10) {
          _dibujarNumerosEjes(
            canvas,
            numeroAnillo.toString(),
            center,
            r - (anchoZona / 2),
            Colors.white,
            fontNumeros,
            cuatroEjes: cuatroEjes,
          );
        }
      }
      // Zona Clara
      else {
        if (i > 0) {
          canvas.drawCircle(
              center, r, esFondoNegro ? paintLineaBlanca : paintLineaClara);
        }
        // NÚMEROS NEGROS EN ZONA CLARA (O BLANCOS SI FONDO NEGRO)
        Color colorNum = esFondoNegro ? Colors.white : Colors.black;
        _dibujarNumerosEjes(
          canvas,
          numeroAnillo.toString(),
          center,
          r - (anchoZona / 2),
          colorNum,
          fontNumeros,
          cuatroEjes: cuatroEjes,
        );
      }
    }

    // 3. Mosca
    if (tieneMosca) {
      double radioMosca = (radius / totalZonas) / 2;
      canvas.drawCircle(center, radioMosca, paintLineaBlanca);
    }

    // 4. Guías
    if (tieneGuias) {
      Paint guia = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.0;
      double largo = radius * 0.3;
      canvas.drawLine(Offset(center.dx - radius, center.dy),
          Offset(center.dx - radius + largo, center.dy), guia);
      canvas.drawLine(Offset(center.dx + radius, center.dy),
          Offset(center.dx + radius - largo, center.dy), guia);
    }

    // 5. Impactos
    final paintImpacto = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    final paintBordeOscuro = Paint()
      ..color = Colors.black.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final paintBordeClaro = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    double radioImpacto = anchoZona * 0.3;
    if (diametroImpactoMm != null &&
        diametroDianaMm != null &&
        diametroImpactoMm! > 0 &&
        diametroDianaMm! > 0) {
      radioImpacto = radius * (diametroImpactoMm! / diametroDianaMm!);
      radioImpacto = radioImpacto.clamp(1.4, radius * 0.14);
    }
    for (var p in impactos) {
      canvas.drawCircle(p, radioImpacto + 0.8, paintBordeOscuro);
      canvas.drawCircle(p, radioImpacto + 0.2, paintBordeClaro);
      canvas.drawCircle(p, radioImpacto, paintImpacto);
    }
  }

  void _dibujarNumerosEjes(
    Canvas canvas,
    String texto,
    Offset center,
    double dist,
    Color color,
    double fontSize, {
    required bool cuatroEjes,
  }) {
    _texto(canvas, texto, Offset(center.dx, center.dy - dist), color, fontSize);
    _texto(canvas, texto, Offset(center.dx, center.dy + dist), color, fontSize);
    if (cuatroEjes) {
      _texto(
          canvas, texto, Offset(center.dx + dist, center.dy), color, fontSize);
      _texto(
          canvas, texto, Offset(center.dx - dist, center.dy), color, fontSize);
    }
  }

  void _texto(
      Canvas canvas, String texto, Offset pos, Color color, double fontSize) {
    final tp = TextPainter(
        text: TextSpan(
            text: texto,
            style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant DianaPainter oldDelegate) => true;
}
