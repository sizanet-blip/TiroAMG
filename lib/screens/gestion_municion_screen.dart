import 'package:flutter/material.dart';
import '../models/municion_model.dart';
import '../services/municion_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
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
      builder: (ctx) => AppDialog(
        title: 'Eliminar munición',
        icon: Icons.delete_outline,
        iconColor: AppColors.accentDanger,
        content: Text(
          '¿Borrar «${item.marca} - ${item.lote}»? Esta acción no se puede deshacer.',
        ),
        actions: appDialogActions(
          context: ctx,
          confirmLabel: 'Borrar',
          danger: true,
          onConfirm: () async {
            Navigator.pop(ctx);
            await _service.borrar(item.id);
            _cargarDatos();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Munición eliminada')),
              );
            }
          },
        ),
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
      builder: (ctx) => AppDialog(
        title: 'Uso de ${item.marca}',
        icon: Icons.history,
        iconColor: AppColors.accentTraining,
        content: SizedBox(
          width: 420,
          child: usos.isEmpty
              ? Text(
                  'Aún no hay sesiones con esta munición.',
                  style: TextStyle(color: AppColors.subtitle),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: usos.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, i) {
                    final u = usos[i];
                    final lugar = (u.lugar == null || u.lugar!.trim().isEmpty)
                        ? 'Sin lugar'
                        : u.lugar!;
                    final meteo =
                        'T ${u.temperaturaC?.toStringAsFixed(1) ?? '-'}°C · '
                        'H ${u.humedadPct?.toStringAsFixed(0) ?? '-'}% · '
                        'V ${u.vientoMs?.toStringAsFixed(1) ?? '-'} m/s ${u.vientoDireccion ?? ''}';
                    final entorno =
                        '${u.esInterior == null ? '-' : (u.esInterior! ? 'Interior' : 'Exterior')}'
                        '${u.distanciaMetros == null ? '' : ' · ${u.distanciaMetros} m'}';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.place,
                        color: AppColors.accentTraining,
                      ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cerrar',
              style: TextStyle(color: AppColors.subtitle),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _registrarMovimiento(
    MunicionDetalle item, {
    required bool esCompra,
  }) async {
    final controller = TextEditingController();
    final notaController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: esCompra ? 'Registrar compra' : 'Registrar uso manual',
        icon: esCompra ? Icons.add_shopping_cart : Icons.remove_circle_outline,
        iconColor: AppColors.accentTraining,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cantidad'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: notaController,
              decoration: const InputDecoration(labelText: 'Nota (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: AppColors.subtitle),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final cantidad = int.tryParse(controller.text) ?? 0;
    if (cantidad <= 0) return;

    if (esCompra) {
      await _service.registrarCompra(
        item.id,
        cantidad,
        nota: notaController.text.trim().isEmpty
            ? null
            : notaController.text.trim(),
      );
    } else {
      await _service.registrarUso(
        item.id,
        cantidad,
        nota: notaController.text.trim().isEmpty
            ? null
            : notaController.text.trim(),
      );
    }
    _cargarDatos();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(esCompra ? 'Compra registrada' : 'Uso registrado'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Mis Municiones')),
      body: _lista.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No hay munición registrada',
                  style: TextStyle(color: AppColors.subtitle),
                ),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: _lista.length,
                  itemBuilder: (context, index) {
                    final item = _lista[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.accentTraining.withValues(alpha: 0.12),
                          child: const Icon(
                            Icons.apps,
                            color: AppColors.accentTraining,
                          ),
                        ),
                        title: Text(
                          '${item.marca} (${item.nombreCalibre})',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.title,
                          ),
                        ),
                        subtitle: Text(
                          'Lote: ${item.lote}\nStock: ${item.cantidadActual} | Disparada: ${item.totalDisparada}',
                          style: TextStyle(color: AppColors.subtitleSoft),
                        ),
                        onLongPress: () => _borrarMunicion(item),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Donde se uso',
                              icon: Icon(
                                Icons.map_outlined,
                                color: AppColors.primary,
                              ),
                              onPressed: () => _verDondeSeUso(item),
                            ),
                            IconButton(
                              tooltip: 'Compra',
                              icon: const Icon(
                                Icons.add_circle_outline,
                                color: Colors.green,
                              ),
                              onPressed: () =>
                                  _registrarMovimiento(item, esCompra: true),
                            ),
                            IconButton(
                              tooltip: 'Uso manual',
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.orange,
                              ),
                              onPressed: () =>
                                  _registrarMovimiento(item, esCompra: false),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.edit,
                                color: AppColors.accentTraining,
                              ),
                              onPressed: () => _abrirFormulario(item.id),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppColors.accentDanger,
                              ),
                              onPressed: () => _borrarMunicion(item),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _abrirFormulario(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
