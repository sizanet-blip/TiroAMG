import 'package:flutter/material.dart';
// Modelos
import '../models/equipo_model.dart';
import '../models/plantilla_tiempos_model.dart';
import '../models/municion_model.dart';
// Servicios
import '../services/equipo_service.dart';
import '../services/plantilla_tiempos_service.dart';
import '../services/municion_service.dart';
// Pantalla de Destino (La Diana)
import 'sesion_disparo_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/tiro_amg_app_bar.dart';

class EntrenamientoScreen extends StatefulWidget {
  const EntrenamientoScreen({super.key});

  @override
  State<EntrenamientoScreen> createState() => _EntrenamientoScreenState();
}

class _EntrenamientoScreenState extends State<EntrenamientoScreen> {
  // Servicios
  final _equipoService = EquipoService();
  final _plantillaService = PlantillaTiemposService();
  final _municionService = MunicionService();

  // Listas de Datos
  List<EquipoDetalle> _equipos = [];
  List<PlantillaTiempos> _plantillas = [];
  List<MunicionDetalle> _municiones = [];

  // Selecciones del Usuario
  EquipoDetalle? _equipoSeleccionado;
  PlantillaTiempos? _plantillaSeleccionada;
  MunicionDetalle? _municionSeleccionada;
  final _lugarController = TextEditingController();
  final _distanciaController = TextEditingController();
  final _tempController = TextEditingController();
  final _humedadController = TextEditingController();
  final _presionController = TextEditingController();
  final _vientoController = TextEditingController();
  final _vientoDirController = TextEditingController();
  String? _posicionTiro;
  String? _iluminacion;
  bool _esInterior = true;
  bool _usarEntradaManualPuntos = false;
  /// false = entrenar (defecto); true = sesión para corregir miras.
  bool _esCorreccionMira = false;

  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final equipos = await _equipoService.obtenerEquiposDetallados();
    final plantillas = await _plantillaService.obtenerTodas();
    final municiones = await _municionService.obtenerMunicionDetallada();

    if (mounted) {
      setState(() {
        _equipos = equipos;
        _plantillas = plantillas;
        _municiones = municiones;
        _cargando = false;
        
        // Pre-seleccionar el primero si existe para facilitar
        if (_equipos.isNotEmpty) _equipoSeleccionado = _equipos.first;
        if (_plantillas.isNotEmpty) _plantillaSeleccionada = _plantillas.first;
      });
    }
  }

  void _iniciarSesion() {
    if (_equipoSeleccionado == null || _plantillaSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes seleccionar un Arma y una Disciplina')),
      );
      return;
    }

    // Navegar a la pantalla de disparo enviando los datos configurados
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SesionDisparoScreen(
          equipo: _equipoSeleccionado!,
          plantilla: _plantillaSeleccionada!,
          municion: _municionSeleccionada,
          lugar: _textOrNull(_lugarController.text),
          distanciaMetros: _parseInt(_distanciaController.text),
          posicionTiro: _posicionTiro,
          esInterior: _esInterior,
          temperaturaC: _parseDouble(_tempController.text),
          humedadPct: _parseDouble(_humedadController.text),
          presionHpa: _parseDouble(_presionController.text),
          vientoMs: _parseDouble(_vientoController.text),
          vientoDireccion: _textOrNull(_vientoDirController.text),
          iluminacion: _iluminacion,
          usarEntradaManualPuntos: _usarEntradaManualPuntos,
          esCorreccionMira: _esCorreccionMira,
        ),
      ),
    );
  }

  int? _parseInt(String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    return int.tryParse(v);
  }

  double? _parseDouble(String value) {
    final v = value.trim().replaceAll(',', '.');
    if (v.isEmpty) return null;
    return double.tryParse(v);
  }

  String? _textOrNull(String value) {
    final v = value.trim();
    return v.isEmpty ? null : v;
  }

  @override
  void dispose() {
    _lugarController.dispose();
    _distanciaController.dispose();
    _tempController.dispose();
    _humedadController.dispose();
    _presionController.dispose();
    _vientoController.dispose();
    _vientoDirController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Si no hay datos configurados, avisar al usuario
    if (_equipos.isEmpty || _plantillas.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: const TiroAmgAppBar(section: 'Entrenamiento'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded, size: 60, color: AppColors.accentCompetition),
                const SizedBox(height: 20),
                Text(
                  'Faltan datos de configuración.\nNecesitas crear al menos un Arma y una Plantilla de Tiempos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: AppColors.title),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return AppPageScaffold(
      title: 'Configurar Sesión',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionCard(
            title: 'Sesión',
            titleIcon: Icons.sports_score,
            titleIconColor: AppColors.accentTraining,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<EquipoDetalle>(
                  decoration: const InputDecoration(labelText: 'Arma'),
                  value: _equipoSeleccionado,
                  isExpanded: true,
                  items: _equipos.map((e) {
                    return DropdownMenuItem(
                      value: e,
                      child: Text('${e.nombre} (${e.nombreCalibre})'),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _equipoSeleccionado = val),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<PlantillaTiempos>(
                  decoration: const InputDecoration(labelText: 'Reglas / Disciplina'),
                  value: _plantillaSeleccionada,
                  isExpanded: true,
                  items: _plantillas.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text(
                        p.nombreDisciplina,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _plantillaSeleccionada = val),
                ),
                const SizedBox(height: 8),
                Text(
                  'Objetivo de la sesión',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.subtitle,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Entrenar'),
                      icon: Icon(Icons.sports_score, size: 18),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Corregir miras'),
                      icon: Icon(Icons.tune, size: 18),
                    ),
                  ],
                  selected: {_esCorreccionMira},
                  onSelectionChanged: (sel) {
                    setState(() => _esCorreccionMira = sel.first);
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (_esCorreccionMira)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'El análisis sugerirá clics de mira. No se mostrará el diagnóstico técnico.',
                      style: TextStyle(fontSize: 12, color: AppColors.subtitle),
                    ),
                  ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _usarEntradaManualPuntos
                        ? 'Puntuar por números'
                        : 'Puntuar tocando diana',
                  ),
                  subtitle: Text(
                    _usarEntradaManualPuntos
                        ? 'Botones X (mosca) y 10…0. Sin marcar impactos en diana.'
                        : 'Marcas el impacto tocando la diana.',
                  ),
                  value: _usarEntradaManualPuntos,
                  onChanged: (v) =>
                      setState(() => _usarEntradaManualPuntos = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<MunicionDetalle>(
                  decoration: const InputDecoration(
                    labelText: 'Munición (opcional)',
                  ),
                  value: _municionSeleccionada,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<MunicionDetalle>(
                      value: null,
                      child: Text('Sin especificar'),
                    ),
                    ..._municiones.map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text('${m.marca} - ${m.lote} (Stock: ${m.cantidadActual})'),
                      );
                    }),
                  ],
                  onChanged: (val) => setState(() => _municionSeleccionada = val),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          AppSectionCard(
            title: 'Condiciones de tiro',
            titleIcon: Icons.thermostat_outlined,
            titleIconColor: AppColors.subtitle,
            collapsible: true,
            initiallyExpanded: false,
            child: Column(
              children: [
                TextFormField(
                  controller: _lugarController,
                  decoration: const InputDecoration(
                    labelText: 'Lugar / Campo',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _distanciaController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Distancia (m)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Interior', style: TextStyle(color: AppColors.title)),
                    Switch(
                      value: _esInterior,
                      onChanged: (v) => setState(() => _esInterior = v),
                    ),
                    Text(_esInterior ? 'Si' : 'No', style: TextStyle(color: AppColors.subtitle)),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _posicionTiro,
                  decoration: const InputDecoration(
                    labelText: 'Posicion de tiro',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Pie', child: Text('Pie')),
                    DropdownMenuItem(value: 'Rodilla', child: Text('Rodilla')),
                    DropdownMenuItem(value: 'Tendido', child: Text('Tendido')),
                    DropdownMenuItem(value: 'Banco', child: Text('Banco')),
                  ],
                  onChanged: (v) => setState(() => _posicionTiro = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _iluminacion,
                  decoration: const InputDecoration(
                    labelText: 'Iluminacion',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Artificial', child: Text('Artificial')),
                    DropdownMenuItem(value: 'Natural', child: Text('Natural')),
                    DropdownMenuItem(value: 'Mixta', child: Text('Mixta')),
                  ],
                  onChanged: (v) => setState(() => _iluminacion = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tempController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Temperatura (°C)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _humedadController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Humedad (%)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _presionController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Presion (hPa)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _vientoController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Viento (m/s)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _vientoDirController,
                  decoration: const InputDecoration(
                    labelText: 'Direccion del viento',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          AppPrimaryButton(
            label: 'Empezar entrenamiento',
            icon: Icons.play_arrow,
            onPressed: _iniciarSesion,
          ),
        ],
      ),
    );
  }
}
