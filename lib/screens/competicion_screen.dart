import 'package:flutter/material.dart';
import '../models/competicion_model.dart';
import '../services/competicion_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tiro_amg_app_bar_title.dart';
// Importamos las pantallas de destino
import 'competicion_detalle_screen.dart'; // Para editar
import 'competicion_setup_screen.dart'; // Para empezar (Setup)

class CompeticionScreen extends StatefulWidget {
  const CompeticionScreen({super.key});

  @override
  State<CompeticionScreen> createState() => _CompeticionScreenState();
}

class _CompeticionScreenState extends State<CompeticionScreen> {
  final CompeticionService _service = CompeticionService();
  List<Modalidad> _lista = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() async {
    final datos = await _service.obtenerModalidades();
    setState(() => _lista = datos);
  }

  // --- MENÚ DE ACCIÓN (EMPEZAR O EDITAR) ---
  void _mostrarOpciones(Modalidad item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        height: 220, // Altura del panel
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item.nombre,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.title,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              item.descripcion ?? 'Selecciona una acción',
              style: TextStyle(color: AppColors.subtitle),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                // BOTÓN EDITAR
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.edit, color: AppColors.primary),
                    label: Text(
                      'EDITAR FASES',
                      style: TextStyle(color: AppColors.primary),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      side: BorderSide(color: AppColors.primary),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx); // Cerrar menú
                      // Ir al editor de fases
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CompeticionDetalleScreen(modalidad: item),
                        ),
                      ).then((_) => _cargarDatos());
                    },
                  ),
                ),
                const SizedBox(width: 15),
                // BOTÓN EMPEZAR
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('EMPEZAR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      elevation: 5,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx); // Cerrar menú
                      // Ir al Setup para elegir arma y empezar
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CompeticionSetupScreen(modalidad: item),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Crear nueva modalidad
  void _crearModalidad() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva Competición'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nombre del Torneo',
            hintText: 'Ej: Mi Entrenamiento Mixto',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await _service.crearModalidad(
                  Modalidad(
                    nombre: controller.text.trim(),
                    descripcion: 'Personalizado',
                    esOficial: false,
                  ),
                );
                _cargarDatos();
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _borrarModalidad(Modalidad item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar Competición'),
        content: Text('¿Eliminar "${item.nombre}"?'),
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
              await _service.borrarModalidadCompleta(item.id!);
              _cargarDatos();
            },
            child: const Text('Borrar Todo'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const TiroAmgAppBarTitle(section: 'Competiciones'),
      ),
      body: _lista.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Cargando competiciones...',
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
                    final accent = item.esOficial
                        ? AppColors.accentCompetition
                        : AppColors.accentAnalytics;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: accent.withValues(alpha: 0.12),
                          child: Icon(
                            item.esOficial
                                ? Icons.emoji_events
                                : Icons.edit_note,
                            color: accent,
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
                          item.esOficial ? 'Oficial ISSF' : 'Personalizada',
                          style: TextStyle(color: AppColors.subtitleSoft),
                        ),
                        // Solo permitimos borrar si NO es oficial
                        trailing: item.esOficial
                            ? Icon(
                                Icons.lock_outline,
                                color: AppColors.chevron,
                                size: 20,
                              )
                            : IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.accentDanger,
                                ),
                                onPressed: () => _borrarModalidad(item),
                              ),
                        // AQUÍ ESTÁ LA CLAVE: Al tocar, abre el menú de opciones
                        onTap: () => _mostrarOpciones(item),
                      ),
                    );
                  },
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _crearModalidad,
        child: const Icon(Icons.add),
      ),
    );
  }
}
