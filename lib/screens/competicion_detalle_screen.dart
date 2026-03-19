import 'package:flutter/material.dart';
import '../models/competicion_model.dart';
import '../services/competicion_service.dart';
import 'fase_form_screen.dart'; 

class CompeticionDetalleScreen extends StatefulWidget {
  final Modalidad modalidad;

  const CompeticionDetalleScreen({super.key, required this.modalidad});

  @override
  State<CompeticionDetalleScreen> createState() => _CompeticionDetalleScreenState();
}

class _CompeticionDetalleScreenState extends State<CompeticionDetalleScreen> {
  final CompeticionService _service = CompeticionService();
  List<FaseDetalle> _fases = [];

  @override
  void initState() {
    super.initState();
    _cargarFases();
  }

  void _cargarFases() async {
    final datos = await _service.obtenerFasesDetalladas(widget.modalidad.id!);
    setState(() => _fases = datos);
  }

  void _abrirFormulario([FaseModalidad? faseAEditar]) async {
    int ordenSugerido = 1;
    if (_fases.isNotEmpty) {
      ordenSugerido = _fases.last.fase.orden + 1;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FaseFormScreen(
          idModalidad: widget.modalidad.id!,
          ordenSugerido: faseAEditar == null ? ordenSugerido : null,
          fase: faseAEditar,
        ),
      ),
    );
    _cargarFases();
  }

  // Función de confirmar y borrar (usada por icono y long press)
  void _borrarFase(FaseDetalle item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar Fase'),
        content: Text('¿Eliminar la fase "${item.fase.descripcionFase}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text('Cancelar')
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, 
              foregroundColor: Colors.white
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _service.borrarFase(item.fase.id!);
              _cargarFases();
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Fase eliminada')),
                );
              }
            },
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.modalidad.nombre),
        backgroundColor: Colors.amber[700],
      ),
      body: Column(
        children: [
          // Cabecera informativa
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.amber[50],
            width: double.infinity,
            child: Text(
              widget.modalidad.descripcion ?? 'Configura las fases de tu competición.',
              style: TextStyle(color: Colors.amber[900]),
            ),
          ),
          
          // Lista de fases
          Expanded(
            child: _fases.isEmpty
                ? const Center(child: Text('No hay fases configuradas. Añade la primera.'))
                : ListView.builder(
                    itemCount: _fases.length,
                    itemBuilder: (context, index) {
                      final detalle = _fases[index];
                      final fase = detalle.fase;
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        shape: fase.esEnsayo 
                            ? RoundedRectangleBorder(side: const BorderSide(color: Colors.orange, width: 2), borderRadius: BorderRadius.circular(10)) 
                            : null,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey[200],
                            child: Text('${fase.orden}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                          ),
                          title: Text(fase.descripcionFase, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '${detalle.nombrePlantilla}\n'
                            '${fase.repeticiones} ${fase.repeticiones == 1 ? "Serie" : "Series"} • ${fase.esEnsayo ? "ENSAYO" : "PUNTÚA"}',
                          ),
                          isThreeLine: true,
                          
                          // --- FUNCIONALIDAD COMPLETA ---
                          // 1. Long Press para borrar
                          onLongPress: () => _borrarFase(detalle),
                          
                          // 2. Iconos Editar y Borrar
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _abrirFormulario(fase),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _borrarFase(detalle),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.amber[700],
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Añadir Fase', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}