import 'package:flutter/material.dart';
import '../models/catalogo_model.dart';
import '../services/catalogo_service.dart';

class CatalogoCalibresScreen extends StatefulWidget {
  const CatalogoCalibresScreen({super.key});

  @override
  State<CatalogoCalibresScreen> createState() => _CatalogoCalibresScreenState();
}

class _CatalogoCalibresScreenState extends State<CatalogoCalibresScreen> {
  final CatalogoService _service = CatalogoService();
  List<Calibre> _lista = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() async {
    final datos = await _service.obtenerCalibres();
    setState(() {
      _lista = datos;
    });
  }

  // --- AGREGAR ---
  void _agregarCalibre() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo Calibre'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Ej: .38 Special'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await _service.crearCalibre(Calibre(nombre: controller.text.trim()));
                _cargarDatos();
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  // --- EDITAR ---
  void _editarCalibre(Calibre item) {
    final controller = TextEditingController(text: item.nombre);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Calibre'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nombre'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await _service.actualizarCalibre(
                  Calibre(id: item.id, nombre: controller.text.trim())
                );
                _cargarDatos();
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
  }

  // --- BORRAR CON CONFIRMACIÓN ---
  void _confirmarBorrado(Calibre item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Estás seguro de que quieres borrar "${item.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _service.borrarCalibre(item.id!);
              _cargarDatos();
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
        title: const Text('Catálogo: Calibres'),
        backgroundColor: Colors.blueGrey,
      ),
      body: _lista.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.straighten, size: 60, color: Colors.grey),
                  SizedBox(height: 10),
                  Text('No hay calibres definidos', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.separated(
              itemCount: _lista.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _lista[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blueGrey.withOpacity(0.1),
                    child: const Icon(Icons.straighten, color: Colors.blueGrey, size: 20),
                  ),
                  title: Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.w500)),

                  onLongPress: () => _confirmarBorrado(item),

                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _editarCalibre(item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _confirmarBorrado(item),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueGrey,
        onPressed: _agregarCalibre,
        child: const Icon(Icons.add),
      ),
    );
  }
}