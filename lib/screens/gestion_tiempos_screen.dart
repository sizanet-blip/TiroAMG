import 'package:flutter/material.dart';
import '../models/plantilla_tiempos_model.dart';
import '../services/plantilla_tiempos_service.dart';
import 'plantilla_tiempos_form_screen.dart'; // Importaremos el formulario aquí

class GestionTiemposScreen extends StatefulWidget {
  const GestionTiemposScreen({super.key});

  @override
  State<GestionTiemposScreen> createState() => _GestionTiemposScreenState();
}

class _GestionTiemposScreenState extends State<GestionTiemposScreen> {
  final PlantillaTiemposService _service = PlantillaTiemposService();
  List<PlantillaTiempos> _lista = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() async {
    final datos = await _service.obtenerTodas();
    setState(() => _lista = datos);
  }

  // Navegar al formulario (Nuevo o Editar)
  void _abrirFormulario([int? id]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlantillaTiemposFormScreen(plantillaId: id),
      ),
    );
    _cargarDatos(); // Recargar al volver
  }

  void _confirmarBorrado(PlantillaTiempos item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar borrado'),
        content: Text('¿Eliminar la plantilla "${item.nombreDisciplina}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await _service.borrar(item.id!);
              _cargarDatos();
            },
            child: const Text('Borrar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plantillas de Tiempos'), backgroundColor: Colors.indigo),
      body: _lista.isEmpty
          ? const Center(child: Text('No hay plantillas creadas', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              itemCount: _lista.length,
              itemBuilder: (context, index) {
                final item = _lista[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    // Icono diferente según el modo (Duelo o Fijo)
                    leading: CircleAvatar(
                      backgroundColor: item.esDuel ? Colors.orange.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                      child: Icon(
                        item.esDuel ? Icons.timer : Icons.ads_click, // Icono visual
                        color: item.esDuel ? Colors.deepOrange : Colors.blue,
                      ),
                    ),
                    title: Text(item.nombreDisciplina, style: const TextStyle(fontWeight: FontWeight.bold)),

                    onLongPress: () => _confirmarBorrado(item),

                    subtitle: Text(
                      item.esDuel
                          ? '${item.seriesPorSesion} series de ${item.disparosPorSerie} tiros (3s/7s)'
                          : '${item.seriesPorSesion} series en ${item.tiempoExposicion} seg',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.edit, color: Colors.indigo), onPressed: () => _abrirFormulario(item.id)),
                        IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _confirmarBorrado(item)),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.indigo,
        onPressed: () => _abrirFormulario(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}