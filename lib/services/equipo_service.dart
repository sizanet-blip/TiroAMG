import '../database/database_provider.dart';
import '../models/equipo_model.dart';

class EquipoService {
  final dbProvider = DatabaseProvider.instance;
  final String _tabla = 'Equipos';

  // 1. Lista Detallada
  Future<List<EquipoDetalle>> obtenerEquiposDetallados() async {
    final db = await dbProvider.database;
    final res = await db.rawQuery('''
      SELECT e.id, e.nombre, e.marca, e.correccion_click_mm, -- ¡NUEVO!
             t.nombre AS nombre_tipo, 
             c.nombre AS nombre_calibre
      FROM Equipos e
      LEFT JOIN CatalogoTiposArma t ON e.id_tipo_arma = t.id
      LEFT JOIN CatalogoCalibres c ON e.id_calibre = c.id
      ORDER BY e.nombre
    ''');
    return res.map((e) => EquipoDetalle.fromMap(e)).toList();
  }

  // 2. Obtener uno
  Future<Equipo?> obtenerPorId(int id) async {
    final db = await dbProvider.database;
    final res = await db.query(_tabla, where: 'id = ?', whereArgs: [id]);
    return res.isNotEmpty ? Equipo.fromMap(res.first) : null;
  }

  // 3. Crear
  Future<int> crear(Equipo equipo) async {
    final db = await dbProvider.database;
    return await db.insert(_tabla, equipo.toMap());
  }

  // 4. Actualizar
  Future<int> actualizar(Equipo equipo) async {
    final db = await dbProvider.database;
    return await db.update(_tabla, equipo.toMap(), where: 'id = ?', whereArgs: [equipo.id]);
  }

  // 5. Borrar
  Future<int> borrar(int id) async {
    final db = await dbProvider.database;
    return await db.delete(_tabla, where: 'id = ?', whereArgs: [id]);
  }
}