import 'package:flutter/material.dart';
import '../models/competicion_model.dart';
import '../services/competicion_service.dart';
import '../theme/app_theme.dart';
import 'fase_form_screen.dart';
import '../widgets/tiro_amg_app_bar.dart';

class CompeticionDetalleScreen extends StatefulWidget {
  final Modalidad modalidad;

  const CompeticionDetalleScreen({super.key, required this.modalidad});

  @override
  State<CompeticionDetalleScreen> createState() =>
      _CompeticionDetalleScreenState();
}

class _CompeticionDetalleScreenState extends State<CompeticionDetalleScreen> {
  final CompeticionService _service = CompeticionService();
  List<FaseDetalle> _fases = [];

  @override
  void initState() {
    super.initState();
    _cargarFases();
  }

  void _cargarFases() async {
    final datos = await _service.obtenerFasesDetalladas(widget.modalidad.id!);
    setState(() => _fases = datos);
  }

  void _abrirFormulario([FaseModalidad? faseAEditar]) async {
    int ordenSugerido = 1;
    if (_fases.isNotEmpty) {
      ordenSugerido = _fases.last.fase.orden + 1;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FaseFormScreen(
          idModalidad: widget.modalidad.id!,
          ordenSugerido: faseAEditar == null ? ordenSugerido : null,
          fase: faseAEditar,
        ),
      ),
    );
    _cargarFases();
  }

  // Función de confirmar y borrar (usada por icono y long press)
  void _borrarFase(FaseDetalle item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar Fase'),
        content: Text('¿Eliminar la fase "${item.fase.descripcionFase}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _service.borrarFase(item.fase.id!);
              _cargarFases();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Fase eliminada')),
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
      backgroundColor: AppColors.background,
      appBar: TiroAmgAppBar(section: widget.modalidad.nombre),
      body: Column(
        children: [
          // Cabecera informativa
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  widget.modalidad.descripcion ??
                      'Configura las fases de tu competición.',
                  style: TextStyle(color: AppColors.subtitle),
                ),
              ),
            ),
          ),

          // Lista de fases
          Expanded(
            child: _fases.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No hay fases configuradas. Añade la primera.',
                        style: TextStyle(color: AppColors.subtitle),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                        itemCount: _fases.length,
                        itemBuilder: (context, index) {
                          final detalle = _fases[index];
                          final fase = detalle.fase;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadii.card),
                              side: BorderSide(
                                color: fase.esEnsayo
                                    ? AppColors.accentCompetition
                                    : AppColors.border,
                                width: fase.esEnsayo ? 1.5 : 1,
                              ),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.accentCompetition
                                    .withValues(alpha: 0.12),
                                child: Text(
                                  '${fase.orden}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.accentCompetition,
                                  ),
                                ),
                              ),
                              title: Text(
                                fase.descripcionFase,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.title,
                                ),
                              ),
                              subtitle: Text(
                                '${detalle.nombrePlantilla}\n'
                                '${fase.repeticiones} ${fase.repeticiones == 1 ? "Serie" : "Series"} • ${fase.esEnsayo ? "ENSAYO" : "PUNTÚA"}',
                                style: TextStyle(color: AppColors.subtitleSoft),
                              ),
                              isThreeLine: true,
                              // --- FUNCIONALIDAD COMPLETA ---
                              // 1. Long Press para borrar
                              onLongPress: () => _borrarFase(detalle),
                              // 2. Iconos Editar y Borrar
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.edit,
                                      color: AppColors.primary,
                                    ),
                                    onPressed: () => _abrirFormulario(fase),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: AppColors.accentDanger,
                                    ),
                                    onPressed: () => _borrarFase(detalle),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Añadir Fase'),
      ),
    );
  }
}
