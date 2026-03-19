import 'package:sqflite/sqflite.dart';
import '../database/database_provider.dart';
import '../models/plantilla_tiempos_model.dart';

class PlantillaTiemposService {
  final dbProvider = DatabaseProvider.instance;
  final String _tabla = 'PlantillasTiempos';

  // Obtener todas las plantillas
  Future<List<PlantillaTiempos>> obtenerTodas() async {
    final db = await dbProvider.database;
    final res = await db.query(_tabla, orderBy: 'nombre_disciplina');
    return res.map((e) => PlantillaTiempos.fromMap(e)).toList();
  }

  // ¡NUEVO! Obtener por ID (Necesario para editar)
  Future<PlantillaTiempos?> obtenerPorId(int id) async {
    final db = await dbProvider.database;
    final res = await db.query(_tabla, where: 'id = ?', whereArgs: [id], limit: 1);
    return res.isNotEmpty ? PlantillaTiempos.fromMap(res.first) : null;
  }

  // Crear nueva
  Future<int> crear(PlantillaTiempos plantilla) async {
    final db = await dbProvider.database;
    return await db.insert(_tabla, plantilla.toMap());
  }

  // Actualizar
  Future<int> actualizar(PlantillaTiempos plantilla) async {
    final db = await dbProvider.database;
    return await db.update(_tabla, plantilla.toMap(), where: 'id = ?', whereArgs: [plantilla.id]);
  }

  // Borrar
  Future<int> borrar(int id) async {
    final db = await dbProvider.database;
    return await db.delete(_tabla, where: 'id = ?', whereArgs: [id]);
  }
}