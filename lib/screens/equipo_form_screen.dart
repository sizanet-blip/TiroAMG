import 'package:flutter/material.dart';
import '../models/equipo_model.dart';
import '../models/catalogo_model.dart';
import '../services/equipo_service.dart';
import '../services/catalogo_service.dart';

class EquipoFormScreen extends StatefulWidget {
  final int? equipoId;
  const EquipoFormScreen({super.key, this.equipoId});

  @override
  State<EquipoFormScreen> createState() => _EquipoFormScreenState();
}

class _EquipoFormScreenState extends State<EquipoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _equipoService = EquipoService();
  final _catalogoService = CatalogoService();

  final _nombreController = TextEditingController();
  final _marcaController = TextEditingController();
  final _modeloController = TextEditingController();
  final _clicController = TextEditingController(); // ¡NUEVO!

  List<TipoArma> _tipos = [];
  List<Calibre> _calibres = [];
  int? _selectedTipo;
  int? _selectedCalibre;

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

  void _cargarDatosIniciales() async {
    final tipos = await _catalogoService.obtenerTiposArma();
    final calibres = await _catalogoService.obtenerCalibres();

    setState(() {
      _tipos = tipos;
      _calibres = calibres;
    });

    if (widget.equipoId != null) {
      final equipo = await _equipoService.obtenerPorId(widget.equipoId!);
      if (equipo != null) {
        setState(() {
          _nombreController.text = equipo.nombre;
          _marcaController.text = equipo.marca ?? '';
          _modeloController.text = equipo.modelo ?? '';
          _clicController.text = equipo.correccionClick > 0 ? equipo.correccionClick.toString() : '';
          _selectedTipo = equipo.idTipoArma;
          _selectedCalibre = equipo.idCalibre;
        });
      }
    }
  }

  void _guardar() async {
    if (_formKey.currentState!.validate()) {
      double clics = double.tryParse(_clicController.text.replaceAll(',', '.')) ?? 0.0;

      final nuevoEquipo = Equipo(
        id: widget.equipoId,
        nombre: _nombreController.text,
        idTipoArma: _selectedTipo!,
        idCalibre: _selectedCalibre!,
        marca: _marcaController.text,
        modelo: _modeloController.text,
        correccionClick: clics,
      );

      if (widget.equipoId == null) {
        await _equipoService.crear(nuevoEquipo);
      } else {
        await _equipoService.actualizar(nuevoEquipo);
      }
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.equipoId == null ? 'Nueva Arma' : 'Editar Arma'),
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(labelText: 'Nombre (Ej: Mi Pardini)', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Tipo de Arma', border: OutlineInputBorder()),
                initialValue: _selectedTipo,
                items: _tipos.map((e) => DropdownMenuItem(value: e.id, child: Text(e.nombre))).toList(),
                onChanged: (val) => setState(() => _selectedTipo = val),
                validator: (v) => v == null ? 'Selecciona un tipo' : null,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Calibre', border: OutlineInputBorder()),
                initialValue: _selectedCalibre,
                items: _calibres.map((e) => DropdownMenuItem(value: e.id, child: Text(e.nombre))).toList(),
                onChanged: (val) => setState(() => _selectedCalibre = val),
                validator: (v) => v == null ? 'Selecciona un calibre' : null,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: TextFormField(controller: _marcaController, decoration: const InputDecoration(labelText: 'Marca', border: OutlineInputBorder()))),
                  const SizedBox(width: 10),
                  Expanded(child: TextFormField(controller: _modeloController, decoration: const InputDecoration(labelText: 'Modelo', border: OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 20),
              
              // --- SECCIÓN TÉCNICA (CLICS) ---
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.teal[50], borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Configuración de Miras", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _clicController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Corrección por Clic (mm)', 
                        hintText: 'Ej: 5 (para 5mm a 25m)',
                        border: OutlineInputBorder(),
                        suffixText: 'mm/clic'
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      "Consulta el manual de tu arma. Valor típico a 25m: 5mm o 10mm.", 
                      style: TextStyle(fontSize: 11, color: Colors.grey)
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('GUARDAR ARMA'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.all(15)),
                  onPressed: _guardar,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}