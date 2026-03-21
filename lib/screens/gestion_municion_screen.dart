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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Mis Municiones', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                  Icon(Icons.local_fire_department_rounded, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text('No tienes munición registrada', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16, fontWeight: FontWeight.w500)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _lista.length,
              itemBuilder: (context, index) {
                final item = _lista[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                              radius: 20,
                              child: Icon(Icons.inventory_2_rounded, color: colorScheme.primary, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${item.marca} (${item.nombreCalibre})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text('Lote: ${item.lote}', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${item.cantidadActual} ud.',
                                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, rowConstraints) {
                            final isNarrow = rowConstraints.maxWidth < 420;
                            final acciones = Wrap(
                              spacing: 2,
                              runSpacing: 2,
                              children: [
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(8),
                                  tooltip: 'Historial de uso',
                                  icon: Icon(
                                    Icons.history_rounded,
                                    color: colorScheme.onSurfaceVariant,
                                    size: 20,
                                  ),
                                  onPressed: () => _verDondeSeUso(item),
                                ),
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(8),
                                  tooltip: 'Comprar (+)',
                                  icon: const Icon(
                                    Icons.add_shopping_cart_rounded,
                                    color: Colors.green,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _registrarMovimiento(item, esCompra: true),
                                ),
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(8),
                                  tooltip: 'Restar (-)',
                                  icon: const Icon(
                                    Icons.remove_circle_outline_rounded,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _registrarMovimiento(item, esCompra: false),
                                ),
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(8),
                                  icon: Icon(
                                    Icons.edit_rounded,
                                    color: colorScheme.primary,
                                    size: 20,
                                  ),
                                  onPressed: () => _abrirFormulario(item.id),
                                ),
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(8),
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: colorScheme.error,
                                    size: 20,
                                  ),
                                  onPressed: () => _borrarMunicion(item),
                                ),
                              ],
                            );

                            if (isNarrow) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.local_fire_department_rounded,
                                        size: 14,
                                        color: colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.7),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Disparada: ${item.totalDisparada}',
                                        style: TextStyle(
                                          color: colorScheme.onSurfaceVariant
                                              .withValues(alpha: 0.8),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  acciones,
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Icon(
                                  Icons.local_fire_department_rounded,
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Disparada: ${item.totalDisparada}',
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.8),
                                    fontSize: 12,
                                  ),
                                ),
                                const Spacer(),
                                acciones,
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  )
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 4,
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add_rounded),
        label: const Text("Nueva Munición", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}