import 'package:sqflite/sqflite.dart';
import '../database/database_provider.dart';
import '../models/catalogo_model.dart';

class CatalogoService {
  final dbProvider = DatabaseProvider.instance;

  // --- GESTIÓN DE TIPOS DE ARMA ---

  // Obtener todos
  Future<List<TipoArma>> obtenerTiposArma() async {
    final db = await dbProvider.database;
    final res = await db.query('CatalogoTiposArma', orderBy: 'nombre');
    return res.map((e) => TipoArma.fromMap(e)).toList();
  }

  // Crear nuevo
  Future<int> crearTipoArma(TipoArma tipo) async {
    final db = await dbProvider.database;
    return await db.insert('CatalogoTiposArma', tipo.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Borrar
  Future<int> borrarTipoArma(int id) async {
    final db = await dbProvider.database;
    return await db.delete('CatalogoTiposArma', where: 'id = ?', whereArgs: [id]);
  }
  
  // --- GESTIÓN DE CALIBRES (Similar) ---
  
  Future<List<Calibre>> obtenerCalibres() async {
    final db = await dbProvider.database;
    final res = await db.query('CatalogoCalibres', orderBy: 'nombre');
    return res.map((e) => Calibre.fromMap(e)).toList();
  }
}