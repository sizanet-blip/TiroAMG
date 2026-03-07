import 'package:flutter/material.dart';
import '../models/plantilla_tiempos_model.dart';
import '../models/tipo_diana_model.dart';
import '../services/plantilla_tiempos_service.dart';
import '../services/catalogo_service.dart'; // Necesario para cargar las dianas

class PlantillaTiemposFormScreen extends StatefulWidget {
  final int? plantillaId;
  const PlantillaTiemposFormScreen({super.key, this.plantillaId});

  @override
  State<PlantillaTiemposFormScreen> createState() => _PlantillaTiemposFormScreenState();
}

class _PlantillaTiemposFormScreenState extends State<PlantillaTiemposFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = PlantillaTiemposService();
  final _catalogoService = CatalogoService();

  // Controladores
  final _nombreController = TextEditingController();
  final _seriesController = TextEditingController(text: '6');
  final _disparosController = TextEditingController(text: '5');
  final _prepController = TextEditingController(text: '60');
  
  // Tiempos
  final _tiempoExpController = TextEditingController(text: '300'); 
  final _tiempoOcultacionController = TextEditingController(text: '7');

  bool _esDuelo = false;
  bool _puntuacionDecimal = false;
  
  // Listas y Selecciones
  List<TipoDiana> _dianas = [];
  int? _selectedDianaId;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() async {
    // 1. Cargar el catálogo de dianas
    final dianas = await _catalogoService.obtenerTiposDiana();
    setState(() => _dianas = dianas);

    // 2. Si es edición, cargar datos de la plantilla
    if (widget.plantillaId != null) {
      final item = await _service.obtenerPorId(widget.plantillaId!);
      if (item != null) {
        setState(() {
          _nombreController.text = item.nombreDisciplina;
          _seriesController.text = item.seriesPorSesion.toString();
          _disparosController.text = item.disparosPorSerie.toString();
          _prepController.text = item.tiempoPreparacion.toString();
          
          _esDuelo = item.esDuel;
          _puntuacionDecimal = item.puntuacionDecimal;
          _tiempoExpController.text = item.tiempoExposicion.toString();
          _tiempoOcultacionController.text = item.tiempoOcultacion.toString();
          
          _selectedDianaId = item.idTipoDiana; // Cargamos la diana seleccionada
        });
      }
    } else {
        // Si es nueva, preseleccionamos la primera diana si existe
        if (_dianas.isNotEmpty) {
            setState(() => _selectedDianaId = _dianas.first.id);
        }
    }
  }

  void _guardar() async {
    if (_formKey.currentState!.validate()) {
      final nuevaPlantilla = PlantillaTiempos(
        id: widget.plantillaId,
        nombreDisciplina: _nombreController.text,
        seriesPorSesion: int.parse(_seriesController.text),
        disparosPorSerie: int.parse(_disparosController.text),
        tiempoPreparacion: int.parse(_prepController.text),
        puntuacionDecimal: _puntuacionDecimal,
        esDuel: _esDuelo,
        tiempoExposicion: int.parse(_tiempoExpController.text),
        tiempoOcultacion: _esDuelo ? int.parse(_tiempoOcultacionController.text) : 0,
        idTipoDiana: _selectedDianaId, // Guardamos la diana
      );

      if (widget.plantillaId == null) {
        await _service.crear(nuevaPlantilla);
      } else {
        await _service.actualizar(nuevaPlantilla);
      }
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.plantillaId == null ? 'Nueva Regla' : 'Editar Regla'),
        backgroundColor: Colors.indigo,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Nombre
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(labelText: 'Nombre de la Disciplina', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 20),

              // 2. SELECCIÓN DE DIANA (IMPORTANTE)
              // Si la lista está vacía, mostramos un aviso
              _dianas.isEmpty 
              ? Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.amber[100],
                  child: const Row(
                      children: [
                          Icon(Icons.warning, color: Colors.orange),
                          SizedBox(width: 10),
                          Expanded(child: Text("No hay dianas definidas en el catálogo. Ve a Configuración > Catálogo Dianas.")),
                      ],
                  ),
              )
              : DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Tipo de Diana a usar', border: OutlineInputBorder()),
                initialValue: _selectedDianaId,
                items: _dianas.map((d) => DropdownMenuItem(value: d.id, child: Text(d.nombre))).toList(),
                onChanged: (val) => setState(() => _selectedDianaId = val),
                validator: (v) => v == null ? 'Selecciona una diana' : null,
              ),
              const SizedBox(height: 20),

              // 3. Interruptor Duelo
              SwitchListTile(
                title: const Text('¿Es Modalidad Duelo / Fase?', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Actívalo si la diana aparece y desaparece (Ej: 3s/7s).'),
                value: _esDuelo,
                activeThumbColor: Colors.deepOrange,
                onChanged: (val) {
                  setState(() {
                    _esDuelo = val;
                    if (_esDuelo) {
                      _tiempoExpController.text = "3"; 
                    } else {
                      _tiempoExpController.text = "150"; 
                    }
                  });
                },
              ),
              const Divider(),

              // 4. Tiempos
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tiempoExpController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _esDuelo ? 'Tiempo Visible (Verde)' : 'Tiempo Límite Total',
                        suffixText: 'seg',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  if (_esDuelo) ...[
                    const SizedBox(width: 15),
                    Expanded(
                      child: TextFormField(
                        controller: _tiempoOcultacionController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Tiempo Oculto (Rojo)',
                          suffixText: 'seg',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ]
                ],
              ),
              const SizedBox(height: 15),
              
              // 5. Preparación
              TextFormField(
                controller: _prepController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tiempo de Preparación', suffixText: 'seg', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),

              // 6. Series y Disparos
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _disparosController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Disparos/Serie'),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: TextFormField(
                      controller: _seriesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Nº Series'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 7. Puntuación Decimal
              CheckboxListTile(
                title: const Text('Usar Puntuación Decimal (10.9)'),
                value: _puntuacionDecimal,
                onChanged: (val) => setState(() => _puntuacionDecimal = val!),
              ),

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('GUARDAR REGLAS', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
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