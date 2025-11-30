import 'package:sqflite/sqflite.dart';
import '../database/database_provider.dart';
import '../models/catalogo_model.dart';
import '../models/tipo_diana_model.dart';

class CatalogoService {
  final dbProvider = DatabaseProvider.instance;

  // ==========================================
  //         GESTIÓN DE TIPOS DE ARMA
  // ==========================================

  Future<List<TipoArma>> obtenerTiposArma() async {
    final db = await dbProvider.database;
    final res = await db.query('CatalogoTiposArma', orderBy: 'nombre');
    return res.map((e) => TipoArma.fromMap(e)).toList();
  }

  Future<int> crearTipoArma(TipoArma tipo) async {
    final db = await dbProvider.database;
    return await db.insert('CatalogoTiposArma', tipo.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> actualizarTipoArma(TipoArma tipo) async {
    final db = await dbProvider.database;
    return await db.update('CatalogoTiposArma', tipo.toMap(), where: 'id = ?', whereArgs: [tipo.id]);
  }

  Future<int> borrarTipoArma(int id) async {
    final db = await dbProvider.database;
    return await db.delete('CatalogoTiposArma', where: 'id = ?', whereArgs: [id]);
  }
  
  // ==========================================
  //           GESTIÓN DE CALIBRES
  // ==========================================
  
  Future<List<Calibre>> obtenerCalibres() async {
    final db = await dbProvider.database;
    final res = await db.query('CatalogoCalibres', orderBy: 'nombre');
    return res.map((e) => Calibre.fromMap(e)).toList();
  }

  // ¡NUEVO! Crear Calibre
  Future<int> crearCalibre(Calibre calibre) async {
    final db = await dbProvider.database;
    return await db.insert('CatalogoCalibres', calibre.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ¡NUEVO! Actualizar Calibre
  Future<int> actualizarCalibre(Calibre calibre) async {
    final db = await dbProvider.database;
    return await db.update('CatalogoCalibres', calibre.toMap(), where: 'id = ?', whereArgs: [calibre.id]);
  }

  // ¡NUEVO! Borrar Calibre
  Future<int> borrarCalibre(int id) async {
    final db = await dbProvider.database;
    return await db.delete('CatalogoCalibres', where: 'id = ?', whereArgs: [id]);
  }

  // ==========================================
  //           GESTIÓN DE TIPOS DE DIANA
  // ==========================================
  
  Future<List<TipoDiana>> obtenerTiposDiana() async {
    final db = await dbProvider.database;
    final res = await db.query('CatalogoDianas', orderBy: 'nombre');
    return res.map((e) => TipoDiana.fromMap(e)).toList();
  }

  Future<int> crearTipoDiana(TipoDiana diana) async {
    final db = await dbProvider.database;
    return await db.insert('CatalogoDianas', diana.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  
  // Actualizar
  Future<int> actualizarTipoDiana(TipoDiana diana) async {
    final db = await dbProvider.database;
    return await db.update('CatalogoDianas', diana.toMap(), where: 'id = ?', whereArgs: [diana.id]);
  }

  Future<int> borrarTipoDiana(int id) async {
    final db = await dbProvider.database;
    return await db.delete('CatalogoDianas', where: 'id = ?', whereArgs: [id]);
  }
}