import 'package:flutter/material.dart';
import '../models/equipo_model.dart';
import '../services/equipo_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
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

  void _confirmarBorrado(EquipoDetalle item) {
    showDialog(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Eliminar arma',
        icon: Icons.delete_outline,
        iconColor: AppColors.accentDanger,
        content: Text('¿Borrar «${item.nombre}»? Esta acción no se puede deshacer.'),
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
                SnackBar(content: Text('${item.nombre} eliminado')),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mis Armas'),
      ),
      body: _lista.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.hardware, size: 60, color: AppColors.subtitleSoft),
                    const SizedBox(height: 10),
                    Text(
                      'No tienes armas registradas',
                      style: TextStyle(color: AppColors.subtitle),
                    ),
                  ],
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
                    // Lógica visual simple para el icono
                    final esAire = item.nombreTipo.toLowerCase().contains('aire');

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.accentTraining.withValues(alpha: 0.12),
                          child: Icon(
                            esAire ? Icons.air : Icons.local_fire_department,
                            color: AppColors.accentTraining,
                          ),
                        ),
                        title: Text(
                          item.nombre,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.title,
                          ),
                        ),
                        subtitle: Text(
                          '${item.nombreTipo} • ${item.nombreCalibre}\n${item.marca ?? ""}',
                          style: TextStyle(color: AppColors.subtitleSoft),
                        ),
                        isThreeLine: true,
                        onLongPress: () => _confirmarBorrado(item),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
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
                              onPressed: () => _confirmarBorrado(item),
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
