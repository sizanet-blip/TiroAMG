import 'package:flutter/material.dart';
import '../models/plantilla_tiempos_model.dart';
import '../services/plantilla_tiempos_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import 'plantilla_tiempos_form_screen.dart'; // Importaremos el formulario aquí
import '../widgets/tiro_amg_app_bar.dart';

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
      builder: (ctx) => AppDialog(
        title: 'Eliminar plantilla',
        icon: Icons.delete_outline,
        iconColor: AppColors.accentDanger,
        content: Text(
          '¿Borrar «${item.nombreDisciplina}»? Esta acción no se puede deshacer.',
        ),
        actions: appDialogActions(
          context: ctx,
          confirmLabel: 'Borrar',
          danger: true,
          onConfirm: () async {
            Navigator.pop(ctx);
            await _service.borrar(item.id!);
            _cargarDatos();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const TiroAmgAppBar(section: 'Plantillas de Tiempos'),
      body: _lista.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No hay plantillas creadas',
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
                    final accent = item.esDuel
                        ? AppColors.accentCompetition
                        : AppColors.accentAnalytics;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        // Icono diferente según el modo (Duelo o Fijo)
                        leading: CircleAvatar(
                          backgroundColor: accent.withValues(alpha: 0.12),
                          child: Icon(
                            item.esDuel ? Icons.timer : Icons.ads_click,
                            color: accent,
                          ),
                        ),
                        title: Text(
                          item.nombreDisciplina,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.title,
                          ),
                        ),
                        onLongPress: () => _confirmarBorrado(item),
                        subtitle: Text(
                          item.esDuel
                              ? '${item.seriesPorSesion} series de ${item.disparosPorSerie} tiros (3s/7s)'
                              : '${item.seriesPorSesion} series en ${item.tiempoExposicion} seg',
                          style: TextStyle(color: AppColors.subtitleSoft),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.edit,
                                color: AppColors.accentAnalytics,
                              ),
                              onPressed: () => _abrirFormulario(item.id),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
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
