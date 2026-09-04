import 'package:flutter/material.dart';
import '../models/competicion_model.dart';
import '../models/equipo_model.dart';
import '../models/municion_model.dart';
import '../services/equipo_service.dart';
import '../services/municion_service.dart';
import 'competicion_runner_screen.dart'; // El Director de Orquesta
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

class CompeticionSetupScreen extends StatefulWidget {
  final Modalidad modalidad;
  const CompeticionSetupScreen({super.key, required this.modalidad});

  @override
  State<CompeticionSetupScreen> createState() => _CompeticionSetupScreenState();
}

class _CompeticionSetupScreenState extends State<CompeticionSetupScreen> {
  final _equipoService = EquipoService();
  final _municionService = MunicionService();

  List<EquipoDetalle> _equipos = [];
  List<MunicionDetalle> _municiones = [];
  
  EquipoDetalle? _equipoSeleccionado;
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
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() async {
    final e = await _equipoService.obtenerEquiposDetallados();
    final m = await _municionService.obtenerMunicionDetallada();
    setState(() {
      _equipos = e;
      _municiones = m;
      if (e.isNotEmpty) _equipoSeleccionado = e.first;
      _cargando = false;
    });
  }

  void _empezar() {
    if (_equipoSeleccionado == null) return;
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CompeticionRunnerScreen(
          modalidad: widget.modalidad,
          equipo: _equipoSeleccionado!,
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

    return AppPageScaffold(
      title: widget.modalidad.nombre,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Prepara tu equipo',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.title,
            ),
          ),
          const SizedBox(height: 16),

          AppSectionCard(
            title: 'Sesión',
            titleIcon: Icons.emoji_events_outlined,
            titleIconColor: AppColors.accentCompetition,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<EquipoDetalle>(
                  decoration: const InputDecoration(labelText: 'Arma'),
                  isExpanded: true,
                  value: _equipoSeleccionado,
                  items: _equipos
                      .map((e) => DropdownMenuItem(
                            value: e,
                            child: Text(e.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _equipoSeleccionado = v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<MunicionDetalle>(
                  decoration: const InputDecoration(labelText: 'Munición (opcional)'),
                  isExpanded: true,
                  value: _municionSeleccionada,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Sin especificar', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    ..._municiones.map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(
                          '${m.marca} (${m.lote}) - Stock ${m.cantidadActual}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _municionSeleccionada = v),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _usarEntradaManualPuntos
                        ? 'Puntuar por números'
                        : 'Puntuar tocando diana',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _usarEntradaManualPuntos
                        ? 'Botones X (mosca) y 10…0. Sin marcar impactos en diana.'
                        : 'Marcas el impacto tocando la diana.',
                  ),
                  secondary: Icon(
                    _usarEntradaManualPuntos ? Icons.pin : Icons.adjust,
                    color: AppColors.primary,
                  ),
                  value: _usarEntradaManualPuntos,
                  onChanged: (v) =>
                      setState(() => _usarEntradaManualPuntos = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          AppSectionCard(
            title: 'Condiciones de tiro',
            titleIcon: Icons.thermostat_outlined,
            titleIconColor: AppColors.subtitle,
            child: Column(
              children: [
                TextFormField(
                  controller: _lugarController,
                  decoration: const InputDecoration(labelText: 'Lugar / Campo'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _distanciaController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Distancia (m)'),
                ),
                const SizedBox(height: 8),
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
                DropdownButtonFormField<String>(
                  value: _posicionTiro,
                  decoration: const InputDecoration(labelText: 'Posicion de tiro'),
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
                  decoration: const InputDecoration(labelText: 'Iluminacion'),
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
                  decoration: const InputDecoration(labelText: 'Temperatura (°C)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _humedadController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Humedad (%)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _presionController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Presion (hPa)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _vientoController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Viento (m/s)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _vientoDirController,
                  decoration: const InputDecoration(labelText: 'Direccion del viento'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          AppPrimaryButton(
            label: 'Comenzar torneo',
            icon: Icons.play_circle_filled,
            onPressed: _empezar,
          ),
        ],
      ),
    );
  }
}
