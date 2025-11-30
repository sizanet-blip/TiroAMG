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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: Text(widget.modalidad.nombre), backgroundColor: Colors.amber[700]),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Prepara tu equipo', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            // Selector Arma
            DropdownButtonFormField<EquipoDetalle>(
              decoration: const InputDecoration(labelText: 'Arma', border: OutlineInputBorder()),
              value: _equipoSeleccionado,
              items: _equipos.map((e) => DropdownMenuItem(value: e, child: Text(e.nombre))).toList(),
              onChanged: (v) => setState(() => _equipoSeleccionado = v),
            ),
            const SizedBox(height: 20),

            // Selector Munición
            DropdownButtonFormField<MunicionDetalle>(
              decoration: const InputDecoration(labelText: 'Munición (Opcional)', border: OutlineInputBorder()),
              value: _municionSeleccionada,
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin especificar')),
                ..._municiones.map((m) => DropdownMenuItem(value: m, child: Text('${m.marca} (${m.lote})'))),
              ],
              onChanged: (v) => setState(() => _municionSeleccionada = v),
            ),
            
            const Spacer(),
            
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, 
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(15)
              ),
              icon: const Icon(Icons.play_circle_filled, size: 30),
              label: const Text('COMENZAR TORNEO', style: TextStyle(fontSize: 18)),
              onPressed: _empezar,
            )
          ],
        ),
      ),
    );
  }
}