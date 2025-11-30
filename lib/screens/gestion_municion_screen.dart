import 'package:flutter/material.dart';
import '../models/municion_model.dart';
import '../services/municion_service.dart';
import 'municion_form_screen.dart'; // Importamos el formulario

class GestionMunicionScreen extends StatefulWidget {
  const GestionMunicionScreen({super.key});

  @override
  State<GestionMunicionScreen> createState() => _GestionMunicionScreenState();
}

class _GestionMunicionScreenState extends State<GestionMunicionScreen> {
  final MunicionService _service = MunicionService();
  List<MunicionDetalle> _lista = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() async {
    final datos = await _service.obtenerMunicionDetallada();
    setState(() => _lista = datos);
  }

  void _abrirFormulario([int? id]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MunicionFormScreen(municionId: id)),
    );
    _cargarDatos();
  }

  void _borrarMunicion(MunicionDetalle item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar borrado'),
        content: Text('¿Eliminar la munición "${item.marca} - ${item.lote}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text('Cancelar')
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await _service.borrar(item.id);
              _cargarDatos();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Munición eliminada')),
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
      appBar: AppBar(title: const Text('Mis Municiones'), backgroundColor: Colors.teal),
      body: _lista.isEmpty
          ? const Center(child: Text('No hay munición registrada', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              itemCount: _lista.length,
              itemBuilder: (context, index) {
                final item = _lista[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.teal.withOpacity(0.1),
                      child: const Icon(Icons.apps, color: Colors.teal), // Icono de caja/lote
                    ),
                    title: Text('${item.marca} (${item.nombreCalibre})', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Lote: ${item.lote}'),
                    
                    onLongPress: () => _borrarMunicion(item),
                    
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.teal),
                          onPressed: () => _abrirFormulario(item.id),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _borrarMunicion(item),
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