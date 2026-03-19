import 'package:flutter/material.dart';
import '../models/competicion_model.dart';
import '../models/plantilla_tiempos_model.dart';
import '../services/competicion_service.dart';
import '../services/plantilla_tiempos_service.dart'; // Necesario para el desplegable

class FaseFormScreen extends StatefulWidget {
  final int idModalidad; // A qué torneo pertenece esta fase
  final int? ordenSugerido; // Para ponerlo al final de la lista automáticamente
  final FaseModalidad? fase; // Si no es null, estamos EDITANDO

  const FaseFormScreen({
    super.key,
    required this.idModalidad,
    this.ordenSugerido,
    this.fase,
  });

  @override
  State<FaseFormScreen> createState() => _FaseFormScreenState();
}

class _FaseFormScreenState extends State<FaseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _competicionService = CompeticionService();
  final _plantillaService = PlantillaTiemposService();

  // Controladores
  final _descripcionController = TextEditingController();
  final _repeticionesController = TextEditingController(text: '1');
  final _ordenController = TextEditingController();

  // Estado
  List<PlantillaTiempos> _plantillasDisponibles = [];
  int? _selectedPlantillaId;
  bool _esEnsayo = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() async {
    // 1. Cargar las reglas de tiempo disponibles (Duelo, Precisión...)
    final plantillas = await _plantillaService.obtenerTodas();
    
    setState(() {
      _plantillasDisponibles = plantillas;
      
      // 2. Si estamos EDITANDO, rellenar el formulario
      if (widget.fase != null) {
        _descripcionController.text = widget.fase!.descripcionFase;
        _repeticionesController.text = widget.fase!.repeticiones.toString();
        _ordenController.text = widget.fase!.orden.toString();
        _esEnsayo = widget.fase!.esEnsayo;
        _selectedPlantillaId = widget.fase!.idPlantillaTiempos;
      } else {
        // 3. Si es NUEVO, poner valores por defecto
        _ordenController.text = widget.ordenSugerido?.toString() ?? '1';
        if (plantillas.isNotEmpty) {
          _selectedPlantillaId = plantillas.first.id;
        }
      }
    });
  }

  void _guardar() async {
    if (_formKey.currentState!.validate() && _selectedPlantillaId != null) {
      final nuevaFase = FaseModalidad(
        id: widget.fase?.id, // Null si es nuevo, ID si es editar
        idModalidad: widget.idModalidad,
        orden: int.parse(_ordenController.text),
        idPlantillaTiempos: _selectedPlantillaId!,
        repeticiones: int.parse(_repeticionesController.text),
        esEnsayo: _esEnsayo,
        descripcionFase: _descripcionController.text,
      );

      if (widget.fase == null) {
        await _competicionService.agregarFase(nuevaFase);
      } else {
        await _competicionService.actualizarFase(nuevaFase);
      }
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fase == null ? 'Añadir Fase' : 'Editar Fase'),
        backgroundColor: Colors.amber[700],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. DESCRIPCIÓN
              TextFormField(
                controller: _descripcionController,
                decoration: const InputDecoration(labelText: 'Nombre de la Fase', hintText: 'Ej: Serie de Ensayo'),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 20),

              // 2. SELECCIÓN DE REGLA (PLANTILLA)
              _plantillasDisponibles.isEmpty
                  ? const Text('¡No hay plantillas de tiempo creadas! Ve a Configuración.', style: TextStyle(color: Colors.red))
                  : DropdownButtonFormField<int>(
                      decoration: const InputDecoration(labelText: 'Regla de Tiempo a usar', border: OutlineInputBorder()),
                      value: _selectedPlantillaId,
                      items: _plantillasDisponibles.map((p) => DropdownMenuItem(value: p.id, child: Text(p.nombreDisciplina))).toList(),
                      onChanged: (val) => setState(() => _selectedPlantillaId = val),
                    ),
              const SizedBox(height: 20),

              // 3. OPCIONES DE EJECUCIÓN
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _repeticionesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Repeticiones', helperText: '¿Cuántas series?', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: TextFormField(
                      controller: _ordenController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Orden', helperText: 'Posición en la lista', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 4. SWITCH ENSAYO
              SwitchListTile(
                title: const Text('¿Es fase de Ensayo (Sighters)?'),
                subtitle: const Text('Si activo, los puntos no sumarán al total del torneo.'),
                value: _esEnsayo,
                activeColor: Colors.amber,
                onChanged: (val) => setState(() => _esEnsayo = val),
              ),

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('GUARDAR FASE'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber[700],
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