import 'package:flutter/material.dart';
import '../models/competicion_model.dart';
import '../models/equipo_model.dart';
import '../models/municion_model.dart';
import '../models/plantilla_tiempos_model.dart';
import '../models/sesion_model.dart';
import '../models/disparo_model.dart';
import '../services/competicion_service.dart';
import '../services/entrenamiento_service.dart';
import '../services/plantilla_tiempos_service.dart';
import '../utils/responsive_layout.dart';
import 'sesion_disparo_screen.dart'; // La pantalla de la diana

class CompeticionRunnerScreen extends StatefulWidget {
  final Modalidad modalidad;
  final EquipoDetalle equipo;
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
  final bool usarPuntuacionDecimal;
  final bool usarEntradaManualPuntos;

  const CompeticionRunnerScreen({
    super.key,
    required this.modalidad,
    required this.equipo,
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
  });

  @override
  State<CompeticionRunnerScreen> createState() =>
      _CompeticionRunnerScreenState();
}

class _CompeticionRunnerScreenState extends State<CompeticionRunnerScreen> {
  // Servicios
  final _compService = CompeticionService();
  final _plantillaService = PlantillaTiemposService();
  final _entrenamientoService = EntrenamientoService();

  // Estado del Torneo
  List<FaseDetalle> _fases = [];
  bool _cargando = true;
  bool _torneoFinalizado = false;

  // Control de Progreso
  int _indiceFase = 0; // En qué fase estamos (0, 1, 2...)
  int _indiceRepeticion = 0; // En qué serie de esa fase estamos (0, 1, 2...)

  // Puntuación
  double _puntosTotales = 0;

  // Historial visual para mostrar en la lista de abajo
  final List<String> _logEventos = [];

  @override
  void initState() {
    super.initState();
    _cargarEstructuraTorneo();
  }

  String _formatearPuntos(double value) {
    if (!widget.usarPuntuacionDecimal) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }

  void _cargarEstructuraTorneo() async {
    final fases =
        await _compService.obtenerFasesDetalladas(widget.modalidad.id!);
    if (mounted) {
      setState(() {
        _fases = fases;
        _cargando = false;
      });
    }
  }

  // --- LÓGICA PRINCIPAL DEL BUCLE ---

  void _lanzarSiguienteSerie() async {
    if (_torneoFinalizado) return;
    if (_fases.isEmpty || _indiceFase >= _fases.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No hay fases disponibles para esta modalidad.')),
      );
      return;
    }

    // 1. Obtener la configuración de la fase actual
    final faseActual = _fases[_indiceFase];

    // 2. Necesitamos el objeto Plantilla completo para configurar la diana
    final plantilla = await _plantillaService
        .obtenerPorId(faseActual.fase.idPlantillaTiempos);
    if (!mounted) return;

    if (plantilla == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Error cargando la plantilla de tiempos")));
      return;
    }

    // Datos informativos para la pantalla de disparo
    int numSerie = _indiceRepeticion + 1;
    int totalSeries = faseActual.fase.repeticiones;

    // 3. LANZAR PANTALLA DE DISPARO (ESPERANDO RESPUESTA)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SesionDisparoScreen(
          equipo: widget.equipo,
          plantilla: plantilla,
          municion: widget.municion,
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

          // PARÁMETROS NUEVOS PARA INFORMACIÓN VISUAL
          tituloSerie:
              "${faseActual.fase.descripcionFase} - Serie $numSerie/$totalSeries",
          numeroSerie: numSerie,
          totalSeries: totalSeries,

          // CALLBACK: Esto se ejecuta cuando terminas la serie y pulsas "FIN"
          onCompletar: (disparos, puntos) {
            _procesarResultadosSerie(disparos, puntos, faseActual, plantilla);
          },
          usarPuntuacionDecimal: widget.usarPuntuacionDecimal,
          usarEntradaManualPuntos: widget.usarEntradaManualPuntos,
        ),
      ),
    );
  }

  void _procesarResultadosSerie(List<Disparo> disparos, double puntos,
      FaseDetalle fase, PlantillaTiempos plantilla) async {
    // 1. Guardar en Base de Datos (Para que quede registro histórico)
    final nuevaSesion = Sesion(
      fecha: DateTime.now(),
      idEquipo: widget.equipo.id,
      idPlantilla: plantilla.id!,
      idMunicion: widget.municion?.id,
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
      // Añadimos metadatos del torneo en la nota para identificarlo luego
      nota:
          'Torneo: ${widget.modalidad.nombre} | ${fase.fase.descripcionFase} | Serie ${_indiceRepeticion + 1}'
          '${widget.usarEntradaManualPuntos ? ' | Entrada: Manual' : ''}',
    );
    await _entrenamientoService.guardarSesionCompleta(nuevaSesion, disparos);

    // 2. Actualizar Marcador del Torneo
    setState(() {
      String tipoSerie = fase.fase.esEnsayo ? "ENSAYO" : "COMPETICIÓN";

      if (!fase.fase.esEnsayo) {
        _puntosTotales += puntos;
      }

      // Añadir al log visual
      _logEventos.insert(0,
          "${fase.fase.descripcionFase} (Serie ${_indiceRepeticion + 1}): ${_formatearPuntos(puntos)} pts [$tipoSerie]");

      // 3. AVANZAR CONTADORES
      _indiceRepeticion++;

      // ¿Hemos terminado las repeticiones de esta fase?
      if (_indiceRepeticion >= fase.fase.repeticiones) {
        // Fin de la fase -> Pasar a la siguiente
        _indiceRepeticion = 0; // Reset contador de series
        _indiceFase++; // Siguiente fase en la lista

        // ¿Hemos terminado todas las fases?
        if (_indiceFase >= _fases.length) {
          _torneoFinalizado = true;
          _mostrarFinTorneo();
        }
      }
    });
  }

  void _mostrarFinTorneo() {
    final colorScheme = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.2),
                blurRadius: 30,
                spreadRadius: 5,
              )
            ]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emoji_events_rounded, size: 72, color: Colors.amber),
              ),
              const SizedBox(height: 24),
              Text(
                '¡COMPETICIÓN FINALIZADA!', 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colorScheme.onSurface, letterSpacing: 1.2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text('Puntiación Total Conseguida', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _formatearPuntos(_puntosTotales),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: colorScheme.primary,
                  )
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('SALIR AL MENÚ', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final compactLandscape = ResponsiveLayout.isCompactLandscape(context);

    if (_cargando) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: Center(child: CircularProgressIndicator(color: colorScheme.primary))
      );
    }

    if (_fases.isEmpty) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
            title: Text(widget.modalidad.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_rounded, size: 64, color: colorScheme.error.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text(
                  'Esta modalidad no tiene fases configuradas.\nRevisa la modalidad en Configuración.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_torneoFinalizado) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: const Text('Resultados Finales', style: TextStyle(fontWeight: FontWeight.bold)), 
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emoji_events_rounded, size: 80, color: Colors.amber),
              ),
              const SizedBox(height: 24),
              Text(
                'TORNEO COMPLETADO',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: colorScheme.onSurface, letterSpacing: 1.5)
              ),
              const SizedBox(height: 12),
              Text(
                '${_formatearPuntos(_puntosTotales)} Puntos',
                style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900, letterSpacing: -1.5, color: colorScheme.primary)
              ),
              const SizedBox(height: 48),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('VOLVER AL MENÚ', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                )
              )
            ],
          ),
        ),
      );
    }

    final faseActual = _fases[_indiceFase];
    final esEnsayo = faseActual.fase.esEnsayo;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        toolbarHeight: compactLandscape ? 56 : 64,
        title: Text(
          widget.modalidad.nombre,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: compactLandscape ? 16 : 18,
          ),
        ),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: media.padding.bottom + (compactLandscape ? 8 : 12)),
        children: [
          // 1. MARCADOR GENERAL M3
          Container(
            margin: EdgeInsets.symmetric(
              horizontal: compactLandscape ? 12 : 16,
              vertical: compactLandscape ? 6 : 8,
            ),
            padding: EdgeInsets.all(compactLandscape ? 14 : 20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PUNTUACIÓN TOTAL', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      SizedBox(height: compactLandscape ? 2 : 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _formatearPuntos(_puntosTotales),
                                style: TextStyle(
                                  fontSize: compactLandscape ? 34 : 40,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('pts', style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: compactLandscape ? 6 : 10),
                Flexible(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compactLandscape ? 10 : 14,
                      vertical: compactLandscape ? 10 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'FASE ${_indiceFase + 1} / ${_fases.length}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                            letterSpacing: 0.5,
                            fontSize: compactLandscape ? 12 : 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                        SizedBox(height: compactLandscape ? 2 : 4),
                        Text(
                          'Serie ${_indiceRepeticion + 1} de ${faseActual.fase.repeticiones}',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: compactLandscape ? 11 : 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 2. TARJETA DE PRÓXIMA ACCIÓN M3
          Container(
            margin: EdgeInsets.symmetric(horizontal: compactLandscape ? 12 : 16),
            padding: EdgeInsets.all(compactLandscape ? 16 : 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: esEnsayo 
                    ? [Colors.orange.shade800.withValues(alpha: isDark ? 0.3 : 0.1), Colors.orange.shade600.withValues(alpha: isDark ? 0.1 : 0.05)]
                    : [colorScheme.primary.withValues(alpha: isDark ? 0.3 : 0.1), colorScheme.primary.withValues(alpha: isDark ? 0.1 : 0.02)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(compactLandscape ? 24 : 32),
              border: Border.all(
                color: esEnsayo ? Colors.orange.shade300.withValues(alpha: 0.5) : colorScheme.primary.withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: esEnsayo ? Colors.orange.withValues(alpha: 0.1) : colorScheme.primary.withValues(alpha: 0.1),
                  blurRadius: 20, spreadRadius: 5
                )
              ]
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: esEnsayo ? Colors.orange.withValues(alpha: 0.2) : colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    esEnsayo ? "FASE DE ENSAYO" : "FASE DE COMPETICIÓN",
                    style: TextStyle(
                      color: esEnsayo ? (isDark ? Colors.orange.shade300 : Colors.orange.shade900) : colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      fontSize: 12
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  faseActual.fase.descripcionFase,
                  style: TextStyle(
                    fontSize: compactLandscape ? 23 : 28,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                    color: colorScheme.onSurface,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  faseActual.nombrePlantilla,
                  style: TextStyle(
                    fontSize: compactLandscape ? 14 : 15,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: compactLandscape ? 16 : 24),

                // BOTÓN DE ACCIÓN
                SizedBox(
                  width: double.infinity,
                  height: compactLandscape ? 56 : 64,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: esEnsayo ? Colors.orange.shade600 : colorScheme.primary,
                      foregroundColor: esEnsayo ? Colors.white : colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(compactLandscape ? 16 : 20),
                      ),
                      elevation: 4,
                    ),
                    icon: Icon(
                      Icons.play_circle_fill_rounded,
                      size: compactLandscape ? 24 : 28,
                    ),
                    label: Text(
                      'TIRAR SERIE ${_indiceRepeticion + 1}',
                      style: TextStyle(
                        fontSize: compactLandscape ? 16 : 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    onPressed: _lanzarSiguienteSerie,
                  ),
                ),

                if (esEnsayo) ...[
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(Icons.info_outline_rounded, size: 16, color: isDark ? Colors.orange.shade300 : Colors.orange.shade800),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Los puntos de esta serie NO se sumarán.",
                          style: TextStyle(fontSize: 13, color: isDark ? Colors.orange.shade300 : Colors.orange.shade800, fontWeight: FontWeight.w500),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                ]
              ],
            ),
          ),

          SizedBox(height: compactLandscape ? 16 : 24),
          
          Container(
             alignment: Alignment.centerLeft,
             padding: EdgeInsets.symmetric(horizontal: compactLandscape ? 16 : 24),
             child: Text(
               'HISTORIAL DEL TORNEO',
               style: TextStyle(
                 color: colorScheme.primary,
                 fontSize: compactLandscape ? 11 : 12,
                 fontWeight: FontWeight.bold,
                 letterSpacing: 1.2,
               ),
             ),
          ),
          SizedBox(height: compactLandscape ? 6 : 8),

          // 3. HISTORIAL DE EVENTOS (LOG) M3
          SizedBox(
            height: isLandscape ? (compactLandscape ? 160 : 180) : 320,
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: compactLandscape ? 12 : 16),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  left: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  right: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                )
              ),
              child: _logEventos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_rounded, size: 48, color: colorScheme.surfaceContainerHighest),
                          const SizedBox(height: 16),
                          Text("Esperando a la primera serie...", style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                        ],
                      )
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(compactLandscape ? 12 : 16),
                      itemCount: _logEventos.length,
                      itemBuilder: (context, index) {
                        final isEnsayo = _logEventos[index].contains('[ENSAYO]');
                        
                        return Container(
                          margin: EdgeInsets.only(bottom: compactLandscape ? 6 : 8),
                          padding: EdgeInsets.all(compactLandscape ? 12 : 16),
                          decoration: BoxDecoration(
                            color: isEnsayo ? Colors.orange.withValues(alpha: 0.05) : colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isEnsayo ? Colors.orange.withValues(alpha: 0.2) : Colors.transparent)
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(compactLandscape ? 6 : 8),
                                decoration: BoxDecoration(
                                  color: isEnsayo ? Colors.orange.withValues(alpha: 0.1) : colorScheme.primary.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isEnsayo ? Icons.science_rounded : Icons.sports_score_rounded, 
                                  size: compactLandscape ? 14 : 16, 
                                  color: isEnsayo ? Colors.orange.shade700 : colorScheme.primary
                                ),
                              ),
                              SizedBox(width: compactLandscape ? 10 : 16),
                              Expanded(
                                child: Text(
                                  _logEventos[index].replaceAll(' [ENSAYO]', '').replaceAll(' [COMPETICIÓN]', ''),
                                  style: TextStyle(
                                    fontSize: compactLandscape ? 13 : 14, 
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w500
                                  ),
                                ),
                              ),
                              if (isEnsayo)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                                  child: Text('Ensayo', style: TextStyle(fontSize: 10, color: Colors.orange.shade900, fontWeight: FontWeight.bold)),
                                )
                            ],
                          )
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
