import 'package:flutter/material.dart';
import '../models/equipo_model.dart';
import '../services/equipo_service.dart';
import 'equipo_form_screen.dart'; 

class GestionEquiposScreen extends StatefulWidget {
  const GestionEquiposScreen({super.key});

  @override
  State<GestionEquiposScreen> createState() => _GestionEquiposScreenState();
}

class _GestionEquiposScreenState extends State<GestionEquiposScreen> {
  final EquipoService _service = EquipoService();
  List<EquipoDetalle> _lista = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() async {
    final datos = await _service.obtenerEquiposDetallados();
    setState(() => _lista = datos);
  }

  void _abrirFormulario([int? id]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EquipoFormScreen(equipoId: id)),
    );
    _cargarDatos();
  }

  // Función de confirmar y borrar
  void _confirmarBorrado(EquipoDetalle item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar borrado'),
        content: Text('¿Eliminar el arma "${item.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text('Cancelar')
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx); // Cerrar alerta
              await _service.borrar(item.id); // Borrar en BD
              _cargarDatos(); // Refrescar lista
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${item.nombre} eliminado')),
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
        title: const Text('Mis Armas'), 
        backgroundColor: Colors.teal,
      ),
      body: _lista.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.hardware, size: 60, color: Colors.grey),
                  SizedBox(height: 10),
                  Text('No tienes armas registradas', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _lista.length,
              itemBuilder: (context, index) {
                final item = _lista[index];
                // Lógica visual simple para el icono
                final esAire = item.nombreTipo.toLowerCase().contains('aire');
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.teal.withValues(alpha: 0.1),
                      child: Icon(
                        esAire ? Icons.air : Icons.local_fire_department, 
                        color: Colors.teal,
                      ),
                    ),
                    title: Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${item.nombreTipo} • ${item.nombreCalibre}\n${item.marca ?? ""}'),
                    isThreeLine: true,
                    
                    onLongPress: () => _confirmarBorrado(item),

                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.teal),
                          onPressed: () => _abrirFormulario(item.id),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _confirmarBorrado(item),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal,
        onPressed: () => _abrirFormulario(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}