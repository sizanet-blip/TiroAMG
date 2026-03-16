import 'package:flutter/material.dart';
import '../models/competicion_model.dart';
import '../models/equipo_model.dart';
import '../models/municion_model.dart';
import '../services/equipo_service.dart';
import '../services/municion_service.dart';
import 'competicion_runner_screen.dart'; // El Director de Orquesta

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
  bool _usarPuntuacionDecimal = false;
  bool _usarEntradaManualPuntos = false;
  bool _mostrarCondicionesTiro = false;
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
          usarPuntuacionDecimal: _usarPuntuacionDecimal,
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
          title: Text(widget.modalidad.nombre),
          backgroundColor: Colors.amber[700]),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Prepara tu equipo',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),

          // Selector Arma
          DropdownButtonFormField<EquipoDetalle>(
            decoration: const InputDecoration(
                labelText: 'Arma', border: OutlineInputBorder()),
            isExpanded: true,
            initialValue: _equipoSeleccionado,
            items: _equipos
                .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(e.nombre,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _equipoSeleccionado = v),
          ),
          const SizedBox(height: 20),

          // Selector Munición
          DropdownButtonFormField<MunicionDetalle>(
            decoration: const InputDecoration(
                labelText: 'Munición (Opcional)', border: OutlineInputBorder()),
            isExpanded: true,
            initialValue: _municionSeleccionada,
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Sin especificar',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
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
          const SizedBox(height: 20),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Usar puntuación decimal'),
            subtitle: const Text('Por defecto se usa puntuación entera'),
            value: _usarPuntuacionDecimal,
            onChanged: (v) => setState(() => _usarPuntuacionDecimal = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Usar teclado de puntuación (X, 10 a 0)'),
            subtitle: const Text(
              'Activado: introduces cada tiro con botones.\n'
              'Desactivado: puntúas tocando la diana.',
            ),
            value: _usarEntradaManualPuntos,
            onChanged: (v) => setState(() => _usarEntradaManualPuntos = v),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() {
                _mostrarCondicionesTiro = !_mostrarCondicionesTiro;
              }),
              icon: Icon(_mostrarCondicionesTiro
                  ? Icons.expand_less
                  : Icons.expand_more),
              label: Text(_mostrarCondicionesTiro
                  ? 'Ocultar condiciones de tiro'
                  : 'Mostrar condiciones de tiro'),
            ),
          ),
          if (_mostrarCondicionesTiro) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _lugarController,
              decoration: const InputDecoration(
                  labelText: 'Lugar / Campo', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _distanciaController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Distancia (m)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Interior'),
                Switch(
                  value: _esInterior,
                  onChanged: (v) => setState(() => _esInterior = v),
                ),
                Text(_esInterior ? 'Si' : 'No'),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: _posicionTiro,
              decoration: const InputDecoration(
                  labelText: 'Posicion de tiro', border: OutlineInputBorder()),
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
              initialValue: _iluminacion,
              decoration: const InputDecoration(
                  labelText: 'Iluminacion', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                    value: 'Artificial', child: Text('Artificial')),
                DropdownMenuItem(value: 'Natural', child: Text('Natural')),
                DropdownMenuItem(value: 'Mixta', child: Text('Mixta')),
              ],
              onChanged: (v) => setState(() => _iluminacion = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tempController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Temperatura (°C)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _humedadController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Humedad (%)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _presionController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Presion (hPa)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _vientoController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Viento (m/s)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _vientoDirController,
              decoration: const InputDecoration(
                  labelText: 'Direccion del viento',
                  border: OutlineInputBorder()),
            ),
          ],

          const SizedBox(height: 20),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(15)),
            icon: const Icon(Icons.play_circle_filled, size: 30),
            label:
                const Text('COMENZAR TORNEO', style: TextStyle(fontSize: 18)),
            onPressed: _empezar,
          )
        ],
      ),
    );
  }
}
