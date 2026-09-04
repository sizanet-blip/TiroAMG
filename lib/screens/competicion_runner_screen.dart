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
    this.usarEntradaManualPuntos = false,
  });

  @override
  State<CompeticionRunnerScreen> createState() => _CompeticionRunnerScreenState();
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
  int _indiceFase = 0;       // En qué fase estamos (0, 1, 2...)
  int _indiceRepeticion = 0; // En qué serie de esa fase estamos (0, 1, 2...)
  
  // Puntuación
  int _puntosTotales = 0;
  int _puntosFaseActual = 0;
  
  // Historial visual para mostrar en la lista de abajo
  final List<String> _logEventos = [];

  @override
  void initState() {
    super.initState();
    _cargarEstructuraTorneo();
  }

  void _cargarEstructuraTorneo() async {
    final fases = await _compService.obtenerFasesDetalladas(widget.modalidad.id!);
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
        const SnackBar(content: Text('No hay fases disponibles para esta modalidad.')),
      );
      return;
    }

    // 1. Obtener la configuración de la fase actual
    final faseActual = _fases[_indiceFase];
    
    // 2. Necesitamos el objeto Plantilla completo para configurar la diana
    final plantilla = await _plantillaService.obtenerPorId(faseActual.fase.idPlantillaTiempos);
    
    if (plantilla == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error cargando la plantilla de tiempos")));
      return;
    }

    if (!mounted) return;

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
          usarEntradaManualPuntos: widget.usarEntradaManualPuntos,
          
          // PARÁMETROS NUEVOS PARA INFORMACIÓN VISUAL
          tituloSerie: "${faseActual.fase.descripcionFase} - Serie $numSerie/$totalSeries",
          numeroSerie: numSerie,
          totalSeries: totalSeries,

          // CALLBACK: Esto se ejecuta cuando terminas la serie y pulsas "FIN"
          onCompletar: (disparos, puntos) {
            _procesarResultadosSerie(disparos, puntos, faseActual, plantilla);
          },
        ),
      ),
    );
  }

  void _procesarResultadosSerie(List<Disparo> disparos, int puntos, FaseDetalle fase, PlantillaTiempos plantilla) async {
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
      nota: 'Torneo: ${widget.modalidad.nombre} | ${fase.fase.descripcionFase} | Serie ${_indiceRepeticion + 1}',
    );
    await _entrenamientoService.guardarSesionCompleta(nuevaSesion, disparos);

    // 2. Actualizar Marcador del Torneo
    setState(() {
      String tipoSerie = fase.fase.esEnsayo ? "ENSAYO" : "COMPETICIÓN";
      
      if (!fase.fase.esEnsayo) {
        _puntosTotales += puntos;
        _puntosFaseActual += puntos;
      }

      // Añadir al log visual
      _logEventos.insert(0, 
        "${fase.fase.descripcionFase} (Serie ${_indiceRepeticion + 1}): $puntos pts [$tipoSerie]"
      );

      // 3. AVANZAR CONTADORES
      _indiceRepeticion++;

      // ¿Hemos terminado las repeticiones de esta fase?
      if (_indiceRepeticion >= fase.fase.repeticiones) {
        // Fin de la fase -> Pasar a la siguiente
        _indiceRepeticion = 0; // Reset contador de series
        _puntosFaseActual = 0; // Reset puntos parciales
        _indiceFase++;         // Siguiente fase en la lista

        // ¿Hemos terminado todas las fases?
        if (_indiceFase >= _fases.length) {
          _torneoFinalizado = true;
          _mostrarFinTorneo();
        }
      }
    });
  }

  void _mostrarFinTorneo() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('🏆 ¡Torneo Finalizado!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events, size: 60, color: Colors.amber),
            const SizedBox(height: 20),
            Text('Puntuación Total:', style: Theme.of(context).textTheme.titleMedium),
            Text('$_puntosTotales', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx); // Cerrar alerta
              Navigator.pop(context); // Salir del Runner
            },
            child: const Text('SALIR'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_fases.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.modalidad.nombre),
          backgroundColor: Colors.blueGrey[900],
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Esta modalidad no tiene fases configuradas.\nRevisa la modalidad en configuración.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    // Si terminamos, mostramos pantalla final estática
    if (_torneoFinalizado) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Resultados'),
          backgroundColor: Colors.blueGrey,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('TORNEO COMPLETADO', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Text('$_puntosTotales Puntos', style: const TextStyle(fontSize: 48, color: Colors.amber)),
              const SizedBox(height: 40),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('VOLVER AL MENÚ'))
            ],
          ),
        ),
      );
    }

    // Datos del paso actual
    final faseActual = _fases[_indiceFase];
    final esEnsayo = faseActual.fase.esEnsayo;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(widget.modalidad.nombre),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 1. MARCADOR GENERAL
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PUNTUACIÓN TOTAL', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text('$_puntosTotales', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('FASE ${_indiceFase + 1} / ${_fases.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Serie ${_indiceRepeticion + 1} de ${faseActual.fase.repeticiones}'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 2. TARJETA DE PRÓXIMA ACCIÓN
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              color: esEnsayo ? Colors.orange[50] : Colors.green[50], // Color según si puntúa
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text(
                      esEnsayo ? "FASE DE ENSAYO" : "FASE DE COMPETICIÓN",
                      style: TextStyle(
                        color: esEnsayo ? Colors.orange[800] : Colors.green[800],
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      faseActual.fase.descripcionFase,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      faseActual.nombrePlantilla,
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    
                    // BOTÓN GIGANTE DE ACCIÓN
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: esEnsayo ? Colors.orange : Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.play_circle_fill, size: 28),
                        label: Text(
                          'TIRAR SERIE ${_indiceRepeticion + 1}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _lanzarSiguienteSerie,
                      ),
                    ),
                    
                    if (esEnsayo)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          "⚠️ Los puntos de esta serie NO se sumarán al total.",
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 3. HISTORIAL DE EVENTOS (LOG)
          Expanded(
            child: Container(
              color: Colors.white,
              child: _logEventos.isEmpty 
              ? const Center(child: Text("Esperando inicio...", style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _logEventos.length,
                  separatorBuilder: (_,__) => const Divider(),
                  itemBuilder: (context, index) {
                    return Text(
                      _logEventos[index], 
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
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