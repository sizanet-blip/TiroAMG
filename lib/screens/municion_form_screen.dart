import 'package:flutter/material.dart';
import '../models/municion_model.dart';
import '../models/catalogo_model.dart'; // Para cargar los calibres
import '../services/municion_service.dart';
import '../services/catalogo_service.dart'; // Necesitamos el servicio de catálogos

class MunicionFormScreen extends StatefulWidget {
  final int? municionId;
  const MunicionFormScreen({super.key, this.municionId});

  @override
  State<MunicionFormScreen> createState() => _MunicionFormScreenState();
}

class _MunicionFormScreenState extends State<MunicionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _municionService = MunicionService();
  final _catalogoService = CatalogoService();

  final _marcaController = TextEditingController();
  final _loteController = TextEditingController();
  final _cantidadController = TextEditingController(text: '0');

  List<Calibre> _calibres = [];
  int? _selectedCalibre;
  Municion? _municionOriginal;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() async {
    // 1. Cargar lista de calibres para el desplegable
    final calibres = await _catalogoService.obtenerCalibres();
    setState(() => _calibres = calibres);

    // 2. Si es edición, cargar datos de la munición
    if (widget.municionId != null) {
      final item = await _municionService.obtenerPorId(widget.municionId!);
      if (item != null) {
        setState(() {
          _municionOriginal = item;
          _marcaController.text = item.marca;
          _loteController.text = item.lote;
          _cantidadController.text = item.cantidadActual.toString();
          _selectedCalibre = item.idCalibre;
        });
      }
    }
  }

  void _guardar() async {
    if (_formKey.currentState!.validate()) {
      final cantidad = int.tryParse(_cantidadController.text) ?? 0;
      final nuevaMunicion = Municion(
        id: widget.municionId,
        marca: _marcaController.text,
        lote: _loteController.text,
        idCalibre: _selectedCalibre,
        cantidadInicial: widget.municionId == null ? cantidad : (_municionOriginal?.cantidadInicial ?? 0),
        cantidadActual: cantidad,
        totalDisparada: _municionOriginal?.totalDisparada ?? 0,
      );

      if (widget.municionId == null) {
        await _municionService.crear(nuevaMunicion);
      } else {
        await _municionService.actualizar(nuevaMunicion);
      }
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.municionId == null ? 'Nueva Munición' : 'Editar Munición'),
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Marca
              TextFormField(
                controller: _marcaController,
                decoration: const InputDecoration(labelText: 'Marca (Ej: Eley, SK)', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 20),

              // Lote
              TextFormField(
                controller: _loteController,
                decoration: const InputDecoration(labelText: 'Número de Lote', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _cantidadController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cantidad de cartuchos (stock actual)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 0) return 'Introduce un numero valido';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Desplegable de Calibres
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Calibre', border: OutlineInputBorder()),
                initialValue: _selectedCalibre,
                items: _calibres.map((e) => DropdownMenuItem(value: e.id, child: Text(e.nombre))).toList(),
                onChanged: (val) => setState(() => _selectedCalibre = val),
                validator: (v) => v == null ? 'Selecciona un calibre' : null,
              ),

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(15),
                  ),
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