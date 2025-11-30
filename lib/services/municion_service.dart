import 'package:sqflite/sqflite.dart';
import '../database/database_provider.dart';
import '../models/municion_model.dart';

class MunicionService {
  final dbProvider = DatabaseProvider.instance;
  final String _tabla = 'Municion';

  // Obtener lista con detalles (JOIN)
  Future<List<MunicionDetalle>> obtenerMunicionDetallada() async {
    final db = await dbProvider.database;
    final res = await db.rawQuery('''
      SELECT m.id, m.marca, m.lote, c.nombre as nombre_calibre
      FROM Municion m
      LEFT JOIN CatalogoCalibres c ON m.id_calibre = c.id
      ORDER BY m.marca
    ''');
    return res.map((e) => MunicionDetalle.fromMap(e)).toList();
  }

  Future<Municion?> obtenerPorId(int id) async {
    final db = await dbProvider.database;
    final res = await db.query(_tabla, where: 'id = ?', whereArgs: [id]);
    return res.isNotEmpty ? Municion.fromMap(res.first) : null;
  }

  Future<int> crear(Municion item) async {
    final db = await dbProvider.database;
    return await db.insert(_tabla, item.toMap());
  }

  Future<int> actualizar(Municion item) async {
    final db = await dbProvider.database;
    return await db.update(_tabla, item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }

  Future<int> borrar(int id) async {
    final db = await dbProvider.database;
    return await db.delete(_tabla, where: 'id = ?', whereArgs: [id]);
  }
}