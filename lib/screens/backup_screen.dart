import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/data_seeder_service.dart';
import '../services/backup_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _seederService = DataSeederService();
  final _backupService = BackupService();
  
  bool _procesando = false;

  // --- FUNCIONES DE PRUEBA ---
  void _generarDatos() async {
    setState(() => _procesando = true);
    await _seederService.generarDatosPrueba();
    setState(() => _procesando = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Datos de prueba generados.')));
  }

  void _borrarSoloPruebas() async {
    setState(() => _procesando = true);
    int borrados = await _seederService.borrarSoloDatosPrueba();
    setState(() => _procesando = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🧹 Se han eliminado $borrados sesiones de prueba.')));
  }

  void _borrarTodo() async {
    setState(() => _procesando = true);
    await _seederService.borrarTodosLosDatos();
    setState(() => _procesando = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑️ TODOS los registros han sido eliminados.')));
  }

  // --- FUNCIONES DE BACKUP REAL ---
  void _exportarBD() async {
    await _backupService.exportarBaseDatos();
  }

  void _importarBD() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Restaurar copia?'),
        content: Text(
          '⚠️ CUIDADO: Esta acción BORRARÁ todos los datos actuales y los reemplazará por los de la copia de seguridad.\n\nEsta acción es irreversible.',
          style: TextStyle(color: AppColors.accentDanger),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentDanger),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _procesando = true);
              
              bool exito = await _backupService.importarBaseDatos();
              
              setState(() => _procesando = false);
              
              if (mounted) {
                if (exito) {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('¡Restauración completada!'),
                      content: const Text(
                        'La base de datos ha sido restaurada.\n'
                        'Vuelve al inicio y abre Historial u otra pantalla para ver los datos restaurados.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context); // cierra el diálogo
                            Navigator.pop(context); // vuelve atrás (p. ej. al home)
                          },
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Importación cancelada o fallida')));
                }
              }
            }, 
            child: const Text('Sí, Restaurar'),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Herramientas y Backup',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Copia de Seguridad',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.title,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Guarda tus datos en un lugar seguro (Google Drive, Email, etc.) para no perderlos.',
            style: TextStyle(color: AppColors.subtitle),
          ),
          const SizedBox(height: 20),

          AppNavGroup(
            children: [
              AppNavTile(
                title: 'Exportar Base de Datos',
                subtitle: 'Crear copia de seguridad',
                icon: Icons.upload,
                color: AppColors.accentAnalytics,
                onTap: _exportarBD,
              ),
              AppNavTile(
                title: 'Importar Base de Datos',
                subtitle: 'Restaurar desde un archivo',
                icon: Icons.download,
                color: AppColors.accentCompetition,
                onTap: _importarBD,
              ),
            ],
          ),

          if (kDebugMode) ...[
            const SizedBox(height: 28),
            AppSectionCard(
              title: 'Zona de Pruebas (Developer)',
              titleIcon: Icons.build,
              titleIconColor: AppColors.subtitle,
              child: _procesando
                  ? const Center(child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          onPressed: _generarDatos,
                          child: const Text('GENERAR DATOS DE PRUEBA'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _borrarSoloPruebas,
                          child: const Text('BORRAR SOLO DATOS DE PRUEBA'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('⚠️ ¿BORRAR TODO?'),
                                content: const Text('Se eliminarán tus entrenamientos REALES. No se puede deshacer.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                                  FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: AppColors.accentDanger),
                                    onPressed: () { Navigator.pop(ctx); _borrarTodo(); }, 
                                    child: const Text('Borrar Todo'),
                                  ),
                                ],
                              )
                            );
                          },
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentDanger),
                          child: const Text('BORRAR ABSOLUTAMENTE TODO'),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
