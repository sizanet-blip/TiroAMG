import 'package:flutter/material.dart';
import '../models/catalogo_model.dart';
import '../services/catalogo_service.dart';

class CatalogoTiposScreen extends StatefulWidget {
  const CatalogoTiposScreen({super.key});

  @override
  State<CatalogoTiposScreen> createState() => _CatalogoTiposScreenState();
}

class _CatalogoTiposScreenState extends State<CatalogoTiposScreen> {
  final CatalogoService _service = CatalogoService();
  List<TipoArma> _lista = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() async {
    final datos = await _service.obtenerTiposArma();
    setState(() {
      _lista = datos;
    });
  }

  // Función para agregar un nuevo tipo
  void _agregarTipo() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo Tipo de Arma'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Ej: Rifle Aire'),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await _service.crearTipoArma(TipoArma(nombre: controller.text.trim()));
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

  // --- NUEVA FUNCIÓN: EDITAR ---
  void _editarTipo(TipoArma item) {
    // Pre-llenamos el texto con el nombre actual
    final controller = TextEditingController(text: item.nombre);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Tipo de Arma'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nombre'),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                // Llamamos a actualizar pasando el mismo ID pero el nuevo nombre
                await _service.actualizarTipoArma(
                  TipoArma(id: item.id, nombre: controller.text.trim())
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

  void _confirmarBorrado(TipoArma item) {
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
              await _service.borrarTipoArma(item.id!);
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
        title: const Text('Catálogo: Tipos de Arma'),
        backgroundColor: Colors.blueGrey,
      ),
      body: _lista.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.category_outlined, size: 60, color: Colors.grey),
                  SizedBox(height: 10),
                  Text('No hay tipos definidos', style: TextStyle(color: Colors.grey)),
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
                    child: const Icon(Icons.category, color: Colors.blueGrey, size: 20),
                  ),
                  title: Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.w500)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min, // Ocupa solo el espacio necesario
                    children: [
                      // BOTÓN EDITAR (Lápiz)
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _editarTipo(item),
                      ),
                      // BOTÓN BORRAR (Papelera)
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
        onPressed: _agregarTipo,
        child: const Icon(Icons.add),
      ),
    );
  }
}