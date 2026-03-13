import 'package:flutter/material.dart';
import '../models/competicion_model.dart';
import '../services/competicion_service.dart';
// Importamos las pantallas de destino
import 'competicion_detalle_screen.dart'; // Para editar
import 'competicion_setup_screen.dart';   // Para empezar (Setup)

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
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
              alignment: Alignment.center,
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: item.esOficial ? Colors.amber.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    item.esOficial ? Icons.emoji_events_rounded : Icons.edit_note_rounded,
                    color: item.esOficial ? Colors.amber[800] : Colors.blue,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.nombre, 
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.onSurface), 
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.descripcion ?? 'Selecciona una acción',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            
            Row(
              children: [
                // BOTÓN EDITAR
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.edit_rounded, color: colorScheme.primary),
                    label: Text('EDITAR', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: colorScheme.outlineVariant),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context, 
                        MaterialPageRoute(builder: (_) => CompeticionDetalleScreen(modalidad: item))
                      ).then((_) => _cargarDatos());
                    },
                  ),
                ),
                const SizedBox(width: 16),
                
                // BOTÓN EMPEZAR
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded, size: 24),
                    label: const Text('EMPEZAR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context, 
                        MaterialPageRoute(builder: (_) => CompeticionSetupScreen(modalidad: item))
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // Crear nueva modalidad
  void _crearModalidad() {
    final controller = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.add_circle_outline_rounded, color: colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Nueva Competición', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Nombre del Torneo', 
            hintText: 'Ej: Entrenamiento Mixto',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.outlineVariant), borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.primary, width: 2), borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx), 
            child: Text('Cancelar', style: TextStyle(color: colorScheme.onSurfaceVariant))
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
            ),
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await _service.crearModalidad(Modalidad(
                  nombre: controller.text.trim(),
                  descripcion: 'Personalizado',
                  esOficial: false, 
                ));
                _cargarDatos();
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              }
            },
            child: const Text('Crear', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _borrarModalidad(Modalidad item) {
    final colorScheme = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_rounded, color: Colors.red),
            const SizedBox(width: 8),
            const Text('Borrar Competición', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('¿Eliminar definitivamente "${item.nombre}" y todos sus datos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: Text('Cancelar', style: TextStyle(color: colorScheme.onSurfaceVariant))
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600, 
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 20),
            onPressed: () async {
              Navigator.pop(ctx);
              await _service.borrarModalidadCompleta(item.id!);
              _cargarDatos();
            },
            label: const Text('Borrar Todo'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            pinned: true,
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            elevation: 0,
            title: const Text('Competiciones', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (_lista.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 16),
                    Text('Cargando competiciones...', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 100), // Padding extra abajo para el FAB
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = _lista[index];
                    final isOficial = item.esOficial;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _mostrarOpciones(item),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isOficial 
                                    ? Colors.amber.withValues(alpha: isDark ? 0.2 : 0.15) 
                                    : Colors.blue.withValues(alpha: isDark ? 0.2 : 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isOficial ? Icons.emoji_events_rounded : Icons.edit_note_rounded,
                                  color: isOficial ? Colors.amber.shade700 : Colors.blue.shade600,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.nombre, 
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold, 
                                        fontSize: 16,
                                        color: colorScheme.onSurface,
                                      )
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isOficial ? 'Oficial ISSF' : 'Personalizada',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isOficial)
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(Icons.lock_outline_rounded, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5), size: 20),
                                )
                              else
                                IconButton(
                                  icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
                                  onPressed: () => _borrarModalidad(item),
                                  tooltip: 'Borrar',
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: _lista.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.amber.shade700,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: _crearModalidad,
        icon: const Icon(Icons.add_rounded),
        label: const Text('NUEVA', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}