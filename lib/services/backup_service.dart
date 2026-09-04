import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../database/database_provider.dart';

class BackupService {
  
  // --- EXPORTAR (Guardar copia) ---
  Future<bool> exportarBaseDatos() async {
    try {
      // 1. Localizar la base de datos actual
      String dbPath = await getDatabasesPath();
      String path = join(dbPath, 'tiro_deportivo.db');
      File dbFile = File(path);

      if (!await dbFile.exists()) {
        return false; // No existe la BD aún
      }

      // 2. Compartir el archivo (esto abre el menú nativo de Android/iOS)
      // Desde ahí puedes guardarlo en Drive, Archivos, Email, etc.
      final result = await Share.shareXFiles(
        [XFile(path)], 
        text: 'Copia de seguridad TiroAMG',
        subject: 'Copia de Seguridad ${DateTime.now().toString().split(' ')[0]}'
      );

      return result.status == ShareResultStatus.success;
    } catch (e) {
      print("Error exportando: $e");
      return false;
    }
  }

  // --- IMPORTAR (Restaurar copia) ---
  Future<bool> importarBaseDatos() async {
    try {
      // 1. Abrir selector de archivos
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null && result.files.single.path != null) {
        File fileSeleccionado = File(result.files.single.path!);

        // 2. Cerrar la conexión actual a la BD para poder sobrescribirla
        // (Si no cerramos, puede dar error de archivo en uso)
        final db = await DatabaseProvider.instance.database;
        if (db.isOpen) {
          await db.close();
        }

        // 3. Sobrescribir el archivo de la BD con el seleccionado
        String dbPath = await getDatabasesPath();
        String pathDestino = join(dbPath, 'tiro_deportivo.db');
        
        await fileSeleccionado.copy(pathDestino);

        // 4. Reiniciar la instancia del Provider (opcional, pero recomendado)
        // En realidad, la próxima vez que se llame a 'database', se reabrirá el archivo nuevo.
        
        return true;
      } else {
        // Usuario canceló
        return false;
      }
    } catch (e) {
      print("Error importando: $e");
      return false;
    }
  }
}