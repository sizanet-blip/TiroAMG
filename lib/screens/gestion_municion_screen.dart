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

  String _fmtFecha(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _verDondeSeUso(MunicionDetalle item) async {
    final usos = await _service.obtenerDondeSeUso(item.id, limite: 200);
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Uso de ${item.marca} (${item.lote})'),
        content: SizedBox(
          width: 420,
          child: usos.isEmpty
              ? const Text('Aun no hay sesiones con esta municion.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: usos.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, i) {
                    final u = usos[i];
                    final lugar = (u.lugar == null || u.lugar!.trim().isEmpty) ? 'Sin lugar' : u.lugar!;
                    final meteo = 'T ${u.temperaturaC?.toStringAsFixed(1) ?? '-'}°C · '
                        'H ${u.humedadPct?.toStringAsFixed(0) ?? '-'}% · '
                        'V ${u.vientoMs?.toStringAsFixed(1) ?? '-'} m/s ${u.vientoDireccion ?? ''}';
                    final entorno = '${u.esInterior == null ? '-' : (u.esInterior! ? 'Interior' : 'Exterior')}'
                        '${u.distanciaMetros == null ? '' : ' · ${u.distanciaMetros} m'}';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.place, color: Colors.teal),
                      title: Text(lugar),
                      subtitle: Text(
                        'Fecha: ${_fmtFecha(u.fecha)}\n'
                        'Disparos: ${u.disparos}\n'
                        '$entorno\n'
                        '$meteo',
                      ),
                      isThreeLine: true,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Future<void> _registrarMovimiento(MunicionDetalle item, {required bool esCompra}) async {
    final controller = TextEditingController();
    final notaController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(esCompra ? 'Registrar compra' : 'Registrar uso manual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cantidad',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: notaController,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (ok != true) return;
    final cantidad = int.tryParse(controller.text) ?? 0;
    if (cantidad <= 0) return;

    if (esCompra) {
      await _service.registrarCompra(item.id, cantidad, nota: notaController.text.trim().isEmpty ? null : notaController.text.trim());
    } else {
      await _service.registrarUso(item.id, cantidad, nota: notaController.text.trim().isEmpty ? null : notaController.text.trim());
    }
    _cargarDatos();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(esCompra ? 'Compra registrada' : 'Uso registrado')),
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
                      backgroundColor: Colors.teal.withValues(alpha: 0.1),
                      child: const Icon(Icons.apps, color: Colors.teal), // Icono de caja/lote
                    ),
                    title: Text('${item.marca} (${item.nombreCalibre})', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      'Lote: ${item.lote}\nStock: ${item.cantidadActual} | Disparada: ${item.totalDisparada}',
                    ),
                    
                    onLongPress: () => _borrarMunicion(item),
                    
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Donde se uso',
                          icon: const Icon(Icons.map_outlined, color: Colors.blueGrey),
                          onPressed: () => _verDondeSeUso(item),
                        ),
                        IconButton(
                          tooltip: 'Compra',
                          icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                          onPressed: () => _registrarMovimiento(item, esCompra: true),
                        ),
                        IconButton(
                          tooltip: 'Uso manual',
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.orange),
                          onPressed: () => _registrarMovimiento(item, esCompra: false),
                        ),
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