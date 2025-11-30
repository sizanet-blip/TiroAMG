import 'package:flutter/material.dart';
import '../models/tipo_diana_model.dart';
import '../services/catalogo_service.dart';
import 'tipo_diana_form_screen.dart'; // Crearemos este formulario ahora

class CatalogoDianasScreen extends StatefulWidget {
  const CatalogoDianasScreen({super.key});

  @override
  State<CatalogoDianasScreen> createState() => _CatalogoDianasScreenState();
}

class _CatalogoDianasScreenState extends State<CatalogoDianasScreen> {
  final CatalogoService _service = CatalogoService();
  List<TipoDiana> _lista = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() async {
    final datos = await _service.obtenerTiposDiana();
    setState(() => _lista = datos);
  }

  void _abrirFormulario([TipoDiana? diana]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TipoDianaFormScreen(diana: diana)),
    );
    _cargarDatos();
  }

  void _borrarDiana(TipoDiana item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar borrado'),
        content: Text('¿Eliminar la diana "${item.nombre}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await _service.borrarTipoDiana(item.id!);
              _cargarDatos();
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
      appBar: AppBar(title: const Text('Catálogo de Dianas'), backgroundColor: Colors.blueGrey),
      body: ListView.separated(
        itemCount: _lista.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _lista[index];
          return ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.black12,
              child: Icon(Icons.adjust, color: Colors.black),
            ),
            title: Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Negro desde el ${item.anilloNegroInicio} • ${item.tieneMosca ? "Con Mosca" : "Sin Mosca"}'),
            
            onLongPress: () => _borrarDiana(item),
            
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _abrirFormulario(item)),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _borrarDiana(item)),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueGrey,
        onPressed: () => _abrirFormulario(),
        child: const Icon(Icons.add),
      ),
    );
  }
}