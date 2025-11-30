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
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  void _onCreate(Database db, int version) async {
    // Tablas de Catálogo
    await db.execute('CREATE TABLE CatalogoTiposArma (id INTEGER PRIMARY KEY AUTOINCREMENT, nombre TEXT UNIQUE)');
    await db.execute('CREATE TABLE CatalogoCalibres (id INTEGER PRIMARY KEY AUTOINCREMENT, nombre TEXT UNIQUE)');
    await db.execute('''
      CREATE TABLE CatalogoDianas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT UNIQUE,
        anillo_negro_inicio INTEGER,
        valor_minimo INTEGER,
        es_fondo_negro INTEGER,
        tiene_mosca INTEGER,
        tiene_guias INTEGER
      )
    ''');

    // Tablas de Configuración
    await db.execute('''
      CREATE TABLE PlantillasTiempos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre_disciplina TEXT,
        disparos_por_serie INTEGER,
        series_por_sesion INTEGER,
        puntuacion_decimal INTEGER,
        tiempo_preparacion INTEGER,
        es_duelo INTEGER,
        tiempo_exposicion INTEGER,
        tiempo_ocultacion INTEGER,
        id_tipo_diana INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE Equipos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT,
        id_tipo_arma INTEGER,
        id_calibre INTEGER,
        marca TEXT,
        modelo TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE Municion (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        marca TEXT,
        lote TEXT,
        id_calibre INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE PerfilUsuario (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre_tirador TEXT,
        numero_licencia TEXT,
        club TEXT,
        categoria TEXT
      )
    ''');

    // Tablas de Competición
    await db.execute('''
      CREATE TABLE Modalidades (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT UNIQUE,
        descripcion TEXT,
        es_oficial INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE FasesModalidad (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_modalidad INTEGER,
        orden INTEGER,
        id_plantilla_tiempos INTEGER,
        repeticiones INTEGER,
        es_ensayo INTEGER,
        descripcion_fase TEXT
      )
    ''');

    // Tablas de Datos (Registros)
    await db.execute('''
      CREATE TABLE Sesiones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT,
        id_equipo INTEGER,
        id_plantilla_tiempos INTEGER,
        id_modalidad INTEGER,
        nota TEXT,
        lugar TEXT -- ¡NUEVO CAMPO! Para guardar el campo de tiro
      )
    ''');
    await db.execute('''
      CREATE TABLE Disparos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_sesion INTEGER,
        numero_disparo INTEGER,
        coordenada_x REAL,
        coordenada_y REAL,
        puntuacion REAL,
        es_mosca INTEGER
      )
    ''');

    await _insertarDatosIniciales(db);
  }

  Future<void> _insertarDatosIniciales(Database db) async {
    // Perfil vacío
    await db.insert('PerfilUsuario', {'nombre_tirador': '', 'numero_licencia': '', 'club': '', 'categoria': ''});
    
    // Catálogos
    for (var t in ['Pistola Aire', 'Pistola Fuego', 'Carabina Aire', 'Carabina Fuego']) {
      await db.insert('CatalogoTiposArma', {'nombre': t});
    }
    for (var c in ['4.5mm (.177)', '.22 LR', '9mm', '.32 S&W', '.38 Special', '9mm Parabellum']) {
      await db.insert('CatalogoCalibres', {'nombre': c});
    }
    
    // Dianas
    int idDianaPrec = await db.insert('CatalogoDianas', {'nombre': 'ISSF 25m/50m Precisión', 'valor_minimo': 1, 'anillo_negro_inicio': 7, 'es_fondo_negro': 0, 'tiene_mosca': 1, 'tiene_guias': 0});
    int idDianaDuelo = await db.insert('CatalogoDianas', {'nombre': 'ISSF 25m Duelo/Rápido', 'valor_minimo': 5, 'anillo_negro_inicio': 5, 'es_fondo_negro': 1, 'tiene_mosca': 1, 'tiene_guias': 1});
    await db.insert('CatalogoDianas', {'nombre': 'ISSF 10m Aire', 'valor_minimo': 1, 'anillo_negro_inicio': 4, 'es_fondo_negro': 0, 'tiene_mosca': 1, 'tiene_guias': 0});

    // Plantillas
    int idPlantillaP = await db.insert('PlantillasTiempos', {'nombre_disciplina': 'Base Precisión 5min', 'disparos_por_serie': 5, 'series_por_sesion': 1, 'puntuacion_decimal': 0, 'tiempo_preparacion': 60, 'es_duelo': 0, 'tiempo_exposicion': 300, 'tiempo_ocultacion': 0, 'id_tipo_diana': idDianaPrec});
    int idPlantillaD = await db.insert('PlantillasTiempos', {'nombre_disciplina': 'Base Duelo 3s/7s', 'disparos_por_serie': 5, 'series_por_sesion': 1, 'puntuacion_decimal': 0, 'tiempo_preparacion': 60, 'es_duelo': 1, 'tiempo_exposicion': 3, 'tiempo_ocultacion': 7, 'id_tipo_diana': idDianaDuelo});

    // Competición Ejemplo
    int idModalidadFC = await db.insert('Modalidades', {'nombre': 'Pistola Fuego Central (30+30)', 'descripcion': '30 tiros precisión + 30 tiros duelo', 'es_oficial': 1});
    await db.insert('FasesModalidad', {'id_modalidad': idModalidadFC, 'orden': 1, 'id_plantilla_tiempos': idPlantillaP, 'repeticiones': 1, 'es_ensayo': 1, 'descripcion_fase': 'Ensayo Precisión'});
    await db.insert('FasesModalidad', {'id_modalidad': idModalidadFC, 'orden': 2, 'id_plantilla_tiempos': idPlantillaP, 'repeticiones': 6, 'es_ensayo': 0, 'descripcion_fase': 'Competición Precisión'});
    await db.insert('FasesModalidad', {'id_modalidad': idModalidadFC, 'orden': 3, 'id_plantilla_tiempos': idPlantillaD, 'repeticiones': 1, 'es_ensayo': 1, 'descripcion_fase': 'Ensayo Duelo'});
    await db.insert('FasesModalidad', {'id_modalidad': idModalidadFC, 'orden': 4, 'id_plantilla_tiempos': idPlantillaD, 'repeticiones': 6, 'es_ensayo': 0, 'descripcion_fase': 'Competición Duelo'});

    // Equipo
    await db.insert('Equipos', {'nombre': 'Pistola Genérica .22', 'id_tipo_arma': 2, 'id_calibre': 2, 'marca': 'Genérica', 'modelo': 'Club'});
  }
}