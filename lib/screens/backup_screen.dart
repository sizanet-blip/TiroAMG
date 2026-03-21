import 'package:flutter/material.dart';
import '../services/data_seeder_service.dart';
import '../services/backup_service.dart'; // Importar el nuevo servicio
import 'package:flutter/foundation.dart'; // <--- Agrega esto para usar kDebugMode

class BackupScreen extends StatefulWidget {
  final bool demoToolsOnly;

  const BackupScreen({
    super.key,
    this.demoToolsOnly = false,
  });

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _seederService = DataSeederService();
  final _backupService = BackupService(); // Instancia del servicio
  
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
    // No ponemos _procesando = true aquí porque el diálogo de compartir es nativo y externo
    await _backupService.exportarBaseDatos();
    // No mostramos snackbar porque el propio sistema operativo da feedback visual
  }

  void _importarBD() async {
    // Advertencia de seguridad
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Restaurar copia?'),
        content: const Text(
          '⚠️ CUIDADO: Esta acción BORRARÁ todos los datos actuales y los reemplazará por los de la copia de seguridad.\n\nEsta acción es irreversible.',
          style: TextStyle(color: Colors.red)
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _procesando = true);
              
              bool exito = await _backupService.importarBaseDatos();
              
              setState(() => _procesando = false);
              
              if (mounted) {
                if (exito) {
                  // Sugerimos reiniciar para asegurar que todo cargue bien
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('¡Restauración completada!'),
                      content: const Text('La base de datos ha sido restaurada.\nPor favor, cierra completamente la aplicación y vuélvela a abrir para ver los cambios.'),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                    )
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Importación cancelada o fallida')));
                }
              }
            }, 
            child: const Text('Sí, Restaurar', style: TextStyle(color: Colors.white))
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Herramientas y Backup'),
        backgroundColor: Colors.blueGrey,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Copia de Seguridad', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text('Guarda tus datos en un lugar seguro (Google Drive, Email, etc.) para no perderlos.', style: TextStyle(color: Colors.grey)),
            
            const SizedBox(height: 20),

            // --- SECCIÓN BACKUP REAL ---
            if (!widget.demoToolsOnly) ...[
              ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.upload, color: Colors.white)),
                title: const Text('Exportar Base de Datos'),
                subtitle: const Text('Crear copia de seguridad'),
                onTap: _exportarBD,
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey[300]!)),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.download, color: Colors.white)),
                title: const Text('Importar Base de Datos'),
                subtitle: const Text('Restaurar desde un archivo'),
                onTap: _importarBD,
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey[300]!)),
              ),
            ],

            const SizedBox(height: 40),
            
            // --- SECCIÓN DESARROLLADOR ---
            if (kDebugMode || widget.demoToolsOnly) ...[ 
              const SizedBox(height: 40),
              
              // --- SECCIÓN DESARROLLADOR ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.build, color: Colors.grey),
                        SizedBox(width: 10),
                        Text('Zona de Pruebas', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    
                    if (_procesando)
                      const Center(child: CircularProgressIndicator())
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            onPressed: _generarDatos,
                            child: const Text('REGENERAR DATOS (BORRA ANTERIORES)'),
                          ),
                          if (!widget.demoToolsOnly) ...[
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
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                        onPressed: () { Navigator.pop(ctx); _borrarTodo(); }, 
                                        child: const Text('Borrar Todo')
                                      ),
                                    ],
                                  )
                                );
                              },
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                              child: const Text('BORRAR ABSOLUTAMENTE TODO'),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ], // Fin del bloque if (kDebugMode)

          ],
        ),
      ),
    );
  }
}