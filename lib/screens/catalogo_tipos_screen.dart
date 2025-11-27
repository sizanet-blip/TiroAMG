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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await _service.crearTipoArma(TipoArma(nombre: controller.text));
                _cargarDatos(); // Recargar lista
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _borrarTipo(int id) async {
    await _service.borrarTipoArma(id);
    _cargarDatos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo: Tipos de Arma')),
      body: ListView.builder(
        itemCount: _lista.length,
        itemBuilder: (context, index) {
          final item = _lista[index];
          return ListTile(
            leading: const Icon(Icons.category, color: Colors.blueGrey),
            title: Text(item.nombre),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: () => _borrarTipo(item.id!),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarTipo,
        child: const Icon(Icons.add),
      ),
    );
  }
}