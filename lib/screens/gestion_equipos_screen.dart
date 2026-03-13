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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Mis Armas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      body: _lista.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hardware_rounded, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text('No tienes armas registradas', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16, fontWeight: FontWeight.w500)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _lista.length,
              itemBuilder: (context, index) {
                final item = _lista[index];
                final esAire = item.nombreTipo.toLowerCase().contains('aire');
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                      radius: 24,
                      child: Icon(
                        esAire ? Icons.air_rounded : Icons.local_fire_department_rounded, 
                        color: colorScheme.primary,
                      ),
                    ),
                    title: Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text('${item.nombreTipo} • ${item.nombreCalibre}\n${item.marca ?? ""}', style: TextStyle(color: colorScheme.onSurfaceVariant, height: 1.3)),
                    ),
                    isThreeLine: true,
                    onLongPress: () => _confirmarBorrado(item),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit_rounded, color: colorScheme.primary),
                          onPressed: () => _abrirFormulario(item.id),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
                          onPressed: () => _confirmarBorrado(item),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 4,
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add_rounded),
        label: const Text("Nueva Arma", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}