import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseProvider {
  static Database? _database;
  static final DatabaseProvider instance = DatabaseProvider._constructor();

  DatabaseProvider._constructor();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path = await getDatabasesPath();
    path = join(path, 'tiro_deportivo.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  // AQUÍ CREAMOS LAS TABLAS
  void _onCreate(Database db, int version) async {
    // Tabla para Tipos de Arma (Ej: Pistola, Carabina)
    await db.execute('''
      CREATE TABLE CatalogoTiposArma (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT UNIQUE
      )
    ''');

    // Tabla para Calibres (Ej: .22, 4.5mm)
    await db.execute('''
      CREATE TABLE CatalogoCalibres (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT UNIQUE
      )
    ''');
    
    // Precarga de datos básicos para que no empiece vacío
    await _insertarDatosIniciales(db);
  }

  Future<void> _insertarDatosIniciales(Database db) async {
    // Tipos por defecto
    List<String> tipos = ['Pistola Aire', 'Pistola Fuego', 'Carabina Aire', 'Carabina Fuego'];
    for (var tipo in tipos) {
      await db.insert('CatalogoTiposArma', {'nombre': tipo});
    }
    
    // Calibres por defecto
    List<String> calibres = ['4.5mm (.177)', '.22 LR', '9mm', '.32 S&W'];
    for (var cal in calibres) {
      await db.insert('CatalogoCalibres', {'nombre': cal});
    }
  }
}