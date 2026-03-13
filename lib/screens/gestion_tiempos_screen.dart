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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Plantillas de Tiempos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                  Icon(Icons.timer_rounded, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text('No hay plantillas creadas', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16, fontWeight: FontWeight.w500)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _lista.length,
              itemBuilder: (context, index) {
                final item = _lista[index];
                final iconColor = item.esDuel ? Colors.deepOrange : colorScheme.primary;
                final bgColor = item.esDuel ? Colors.deepOrange.withValues(alpha: 0.1) : colorScheme.primary.withValues(alpha: 0.1);

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
                      backgroundColor: bgColor,
                      radius: 24,
                      child: Icon(
                        item.esDuel ? Icons.timer_rounded : Icons.ads_click_rounded,
                        color: iconColor,
                      ),
                    ),
                    title: Text(item.nombreDisciplina, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        item.esDuel
                            ? '${item.seriesPorSesion} series de ${item.disparosPorSerie} tiros (3s/7s)'
                            : '${item.seriesPorSesion} series en ${item.tiempoExposicion} seg',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, height: 1.3),
                      ),
                    ),
                    onLongPress: () => _confirmarBorrado(item),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: Icon(Icons.edit_rounded, color: colorScheme.primary), onPressed: () => _abrirFormulario(item.id)),
                        IconButton(icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error), onPressed: () => _confirmarBorrado(item)),
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
        label: const Text("Nueva Plantilla", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}