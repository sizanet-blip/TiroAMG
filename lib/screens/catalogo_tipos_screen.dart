import 'package:flutter/material.dart';
import '../models/catalogo_model.dart';
import '../services/catalogo_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/tiro_amg_app_bar.dart';

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
      builder: (context) => AppDialog(
        title: 'Nuevo tipo de arma',
        icon: Icons.category_outlined,
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            hintText: 'Ej: Rifle aire',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _guardarNuevo(controller, context),
        ),
        actions: appDialogActions(
          context: context,
          confirmLabel: 'Guardar',
          onConfirm: () => _guardarNuevo(controller, context),
        ),
      ),
    );
  }

  Future<void> _guardarNuevo(
      TextEditingController controller, BuildContext dialogContext) async {
    if (controller.text.trim().isEmpty) return;
    await _service.crearTipoArma(TipoArma(nombre: controller.text.trim()));
    _cargarDatos();
    if (dialogContext.mounted) Navigator.pop(dialogContext);
  }

  void _editarTipo(TipoArma item) {
    final controller = TextEditingController(text: item.nombre);
    showDialog(
      context: context,
      builder: (context) => AppDialog(
        title: 'Editar tipo de arma',
        icon: Icons.edit_outlined,
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nombre'),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _guardarEdicion(item, controller, context),
        ),
        actions: appDialogActions(
          context: context,
          confirmLabel: 'Guardar',
          onConfirm: () => _guardarEdicion(item, controller, context),
        ),
      ),
    );
  }

  Future<void> _guardarEdicion(TipoArma item, TextEditingController controller,
      BuildContext dialogContext) async {
    if (controller.text.trim().isEmpty) return;
    await _service.actualizarTipoArma(
      TipoArma(id: item.id, nombre: controller.text.trim()),
    );
    _cargarDatos();
    if (dialogContext.mounted) Navigator.pop(dialogContext);
  }

  void _confirmarBorrado(TipoArma item) {
    showDialog(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Eliminar tipo',
        icon: Icons.delete_outline,
        iconColor: AppColors.accentDanger,
        content: Text('¿Borrar «${item.nombre}»? Esta acción no se puede deshacer.'),
        actions: appDialogActions(
          context: ctx,
          confirmLabel: 'Borrar',
          danger: true,
          onConfirm: () async {
            Navigator.of(ctx).pop();
            await _service.borrarTipoArma(item.id!);
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
      appBar: const TiroAmgAppBar(section: 'Catálogo: Tipos de Arma'),
      body: _lista.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.category_outlined,
                      size: 60,
                      color: AppColors.subtitleSoft,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No hay tipos definidos',
                      style: TextStyle(color: AppColors.subtitle),
                    ),
                  ],
                ),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: _lista.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = _lista[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.12),
                          child: Icon(
                            Icons.category,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          item.nombre,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: AppColors.title,
                          ),
                        ),
                        onLongPress: () => _confirmarBorrado(item),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit, color: AppColors.primary),
                              onPressed: () => _editarTipo(item),
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
        onPressed: _agregarTipo,
        child: const Icon(Icons.add),
      ),
    );
  }
}
