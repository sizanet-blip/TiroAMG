import 'dart:convert';
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
      // Checkpoint WAL para que el .db exportado esté completo y consistente.
      final db = await DatabaseProvider.instance.database;
      await db.rawQuery('PRAGMA wal_checkpoint(FULL)');

      String dbPath = await getDatabasesPath();
      String path = join(dbPath, 'tiro_deportivo.db');
      File dbFile = File(path);

      if (!await dbFile.exists()) {
        return false;
      }

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
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null && result.files.single.path != null) {
        File fileSeleccionado = File(result.files.single.path!);

        // Conservar aceptación legal de esta instalación (no viene en backups antiguos).
        final legalMeta = await _leerMetaLegalActual();

        String dbPath = await getDatabasesPath();
        String pathDestino = join(dbPath, 'tiro_deportivo.db');

        // Cerrar y anular el singleton; si no, las pantallas reutilizan un handle cerrado.
        await DatabaseProvider.instance.closeAndReset();

        // Eliminar restos de WAL/SHM del proceso anterior.
        await _eliminarSiExiste('$pathDestino-wal');
        await _eliminarSiExiste('$pathDestino-shm');

        await fileSeleccionado.copy(pathDestino);

        // Reabrir ya sobre el archivo restaurado.
        final db = await DatabaseProvider.instance.database;
        if (legalMeta.isNotEmpty) {
          await _aplicarMetaLegal(db, legalMeta);
        }

        return true;
      } else {
        return false;
      }
    } catch (e) {
      print("Error importando: $e");
      // Intentar recuperar conexión si el restore falló a medias.
      try {
        await DatabaseProvider.instance.database;
      } catch (_) {}
      return false;
    }
  }

  Future<Map<String, dynamic>> _leerMetaLegalActual() async {
    try {
      final db = await DatabaseProvider.instance.database;
      final rows = await db.query('Licencias', where: 'id = 1', limit: 1);
      if (rows.isEmpty) return {};
      final raw = rows.first['features_json']?.toString();
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final src = Map<String, dynamic>.from(decoded);
      final out = <String, dynamic>{};
      for (final key in const [
        'privacy_accepted',
        'privacy_version',
        'privacy_accepted_at',
        'terms_accepted',
        'terms_version',
        'terms_accepted_at',
        'contact_email',
      ]) {
        if (src.containsKey(key)) out[key] = src[key];
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _aplicarMetaLegal(Database db, Map<String, dynamic> legalMeta) async {
    try {
      final rows = await db.query('Licencias', where: 'id = 1', limit: 1);
      Map<String, dynamic> features = {};
      if (rows.isNotEmpty) {
        final raw = rows.first['features_json']?.toString();
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            features = Map<String, dynamic>.from(decoded);
          }
        }
      }
      features.addAll(legalMeta);
      if (rows.isEmpty) {
        await db.insert('Licencias', {
          'id': 1,
          'license_key': '',
          'estado': 'active',
          'features_json': jsonEncode(features),
        });
      } else {
        await db.update(
          'Licencias',
          {'features_json': jsonEncode(features)},
          where: 'id = ?',
          whereArgs: const [1],
        );
      }
    } catch (e) {
      print('Error aplicando meta legal tras restore: $e');
    }
  }

  Future<void> _eliminarSiExiste(String path) async {
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
  }
}
