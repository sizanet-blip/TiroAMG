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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Si no hay datos configurados, avisar al usuario
    if (_equipos.isEmpty || _plantillas.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Entrenamiento'), backgroundColor: Colors.teal),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.warning_amber_rounded, size: 60, color: Colors.orange),
                SizedBox(height: 20),
                Text(
                  'Faltan datos de configuración.\nNecesitas crear al menos un Arma y una Plantilla de Tiempos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Sesión'),
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. TARJETA DE ARMA
            _buildSelectionCard(
              title: '1. Elige tu Arma',
              icon: Icons.hardware,
              child: DropdownButtonFormField<EquipoDetalle>(
                decoration: const InputDecoration(border: OutlineInputBorder()),
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
            ),
            
            const SizedBox(height: 20),

            // 2. TARJETA DE DISCIPLINA (PLANTILLA)
            _buildSelectionCard(
              title: '2. Reglas / Disciplina',
              icon: Icons.timer,
              child: DropdownButtonFormField<PlantillaTiempos>(
                decoration: const InputDecoration(border: OutlineInputBorder()),
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
            ),

            const SizedBox(height: 20),

            // 3. TARJETA DE MUNICIÓN (OPCIONAL)
            _buildSelectionCard(
              title: '3. Munición (Opcional)',
              icon: Icons.local_fire_department,
              child: DropdownButtonFormField<MunicionDetalle>(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Seleccionar lote...',
                ),
                value: _municionSeleccionada,
                isExpanded: true,
                items: [
                  // Opción nula para deseleccionar
                  const DropdownMenuItem<MunicionDetalle>(
                    value: null,
                    child: Text('Sin especificar'),
                  ),
                  ..._municiones.map((m) {
                    return DropdownMenuItem(
                      value: m,
                      child: Text('${m.marca} - ${m.lote}'),
                    );
                  }),
                ],
                onChanged: (val) => setState(() => _municionSeleccionada = val),
              ),
            ),

            const SizedBox(height: 40),

            // BOTÓN DE ACCIÓN
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow, size: 30),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 15),
                child: Text('EMPEZAR ENTRENAMIENTO', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                elevation: 5,
              ),
              onPressed: _iniciarSesion,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionCard({required String title, required IconData icon, required Widget child}) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.teal),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
              ],
            ),
            const SizedBox(height: 15),
            child,
          ],
        ),
      ),
    );
  }
}