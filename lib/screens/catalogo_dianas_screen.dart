import 'package:flutter/material.dart';
import '../models/tipo_diana_model.dart';
import '../services/catalogo_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import 'tipo_diana_form_screen.dart'; // Crearemos este formulario ahora
import '../widgets/tiro_amg_app_bar.dart';

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
      builder: (ctx) => AppDialog(
        title: 'Eliminar diana',
        icon: Icons.delete_outline,
        iconColor: AppColors.accentDanger,
        content: Text('¿Borrar «${item.nombre}»? Esta acción no se puede deshacer.'),
        actions: appDialogActions(
          context: ctx,
          confirmLabel: 'Borrar',
          danger: true,
          onConfirm: () async {
            Navigator.pop(ctx);
            await _service.borrarTipoDiana(item.id!);
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
      appBar: const TiroAmgAppBar(section: 'Catálogo de Dianas'),
      body: _lista.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.adjust,
                      size: 60,
                      color: AppColors.subtitleSoft,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No hay dianas definidas',
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
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = _lista[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.12),
                          child: Icon(
                            Icons.adjust,
                            color: AppColors.primary,
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
                          'Negro desde el ${item.anilloNegroInicio} • ${item.tieneMosca ? "Con Mosca" : "Sin Mosca"}',
                          style: TextStyle(color: AppColors.subtitleSoft),
                        ),
                        onLongPress: () => _borrarDiana(item),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit, color: AppColors.primary),
                              onPressed: () => _abrirFormulario(item),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppColors.accentDanger,
                              ),
                              onPressed: () => _borrarDiana(item),
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
