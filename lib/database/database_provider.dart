import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseProvider {
  static const int schemaVersion = 7;
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
      version: schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  void _onCreate(Database db, int version) async {
    // --- 1. ESTRUCTURA DE TABLAS ---
    
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
        tiene_guias INTEGER,
        ancho_exterior_mm REAL,
        alto_exterior_mm REAL
      )
    ''');

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
    
    // TABLA EQUIPOS (Con corrección de clics)
    await db.execute('''
      CREATE TABLE Equipos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT,
        id_tipo_arma INTEGER,
        id_calibre INTEGER,
        marca TEXT,
        modelo TEXT,
        correccion_click_mm REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE Municion (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        marca TEXT,
        lote TEXT,
        id_calibre INTEGER,
        cantidad_inicial INTEGER NOT NULL DEFAULT 0,
        cantidad_actual INTEGER NOT NULL DEFAULT 0,
        total_disparada INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE MovimientosMunicion (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_municion INTEGER NOT NULL,
        tipo TEXT NOT NULL, -- compra|uso|ajuste
        cantidad INTEGER NOT NULL,
        fecha TEXT NOT NULL,
        nota TEXT
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

    await db.execute('''
      CREATE TABLE Licencias (
        id INTEGER PRIMARY KEY,
        license_key TEXT,
        estado TEXT,
        fecha_inicio TEXT,
        fecha_fin TEXT,
        plan TEXT,
        features_json TEXT,
        device_id TEXT,
        ultima_validacion TEXT,
        proxima_validacion TEXT,
        dias_gracia_offline INTEGER NOT NULL DEFAULT 3,
        max_dispositivos INTEGER,
        firma TEXT,
        ultimo_upgrade_at TEXT,
        ultimo_upgrade_capability TEXT,
        ultimo_upgrade_plan_requerido TEXT,
        ultimo_upgrade_plan_actual TEXT,
        ultimo_upgrade_backend_ok INTEGER,
        ultimo_upgrade_email_ok INTEGER,
        ultimo_upgrade_msg TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE UpgradeSolicitudes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL,
        capability TEXT NOT NULL,
        plan_requerido TEXT,
        plan_actual TEXT,
        backend_ok INTEGER NOT NULL DEFAULT 0,
        email_ok INTEGER NOT NULL DEFAULT 0,
        mensaje TEXT
      )
    ''');

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

    // TABLA SESIONES (Con lugar y modalidad)
    await db.execute('''
      CREATE TABLE Sesiones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT,
        id_equipo INTEGER,
        id_plantilla_tiempos INTEGER,
        id_modalidad INTEGER,
        id_municion INTEGER,
        nota TEXT,
        lugar TEXT,
        distancia_m INTEGER,
        posicion_tiro TEXT,
        es_interior INTEGER,
        temperatura_c REAL,
        humedad_pct REAL,
        presion_hpa REAL,
        viento_ms REAL,
        viento_direccion TEXT,
        iluminacion TEXT
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

    // --- 2. PRECARGA DE DATOS MASIVA (CATÁLOGO COMPLETO) ---
    await _insertarDatosIniciales(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _migrarV1aV2(db);
    }
    if (oldVersion < 3) {
      await _migrarV2aV3(db);
    }
    if (oldVersion < 4) {
      await _migrarV3aV4(db);
    }
    if (oldVersion < 5) {
      await _migrarV4aV5(db);
    }
    if (oldVersion < 6) {
      await _migrarV5aV6(db);
    }
    if (oldVersion < 7) {
      await _migrarV6aV7(db);
    }
  }

  Future<void> _migrarV1aV2(Database db) async {
    // Migracion no destructiva: preserva datos existentes y agrega columnas/tablas.
    await _agregarColumnaSiNoExiste(db, 'Municion', 'cantidad_inicial INTEGER NOT NULL DEFAULT 0');
    await _agregarColumnaSiNoExiste(db, 'Municion', 'cantidad_actual INTEGER NOT NULL DEFAULT 0');
    await _agregarColumnaSiNoExiste(db, 'Municion', 'total_disparada INTEGER NOT NULL DEFAULT 0');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS MovimientosMunicion (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_municion INTEGER NOT NULL,
        tipo TEXT NOT NULL, -- compra|uso|ajuste
        cantidad INTEGER NOT NULL,
        fecha TEXT NOT NULL,
        nota TEXT
      )
    ''');
  }

  Future<void> _migrarV2aV3(Database db) async {
    await _agregarColumnaSiNoExiste(db, 'Sesiones', 'id_municion INTEGER');
  }

  Future<void> _migrarV3aV4(Database db) async {
    await _agregarColumnaSiNoExiste(db, 'Sesiones', 'distancia_m INTEGER');
    await _agregarColumnaSiNoExiste(db, 'Sesiones', 'posicion_tiro TEXT');
    await _agregarColumnaSiNoExiste(db, 'Sesiones', 'es_interior INTEGER');
    await _agregarColumnaSiNoExiste(db, 'Sesiones', 'temperatura_c REAL');
    await _agregarColumnaSiNoExiste(db, 'Sesiones', 'humedad_pct REAL');
    await _agregarColumnaSiNoExiste(db, 'Sesiones', 'presion_hpa REAL');
    await _agregarColumnaSiNoExiste(db, 'Sesiones', 'viento_ms REAL');
    await _agregarColumnaSiNoExiste(db, 'Sesiones', 'viento_direccion TEXT');
    await _agregarColumnaSiNoExiste(db, 'Sesiones', 'iluminacion TEXT');
  }

  Future<void> _migrarV4aV5(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Licencias (
        id INTEGER PRIMARY KEY,
        license_key TEXT,
        estado TEXT,
        fecha_inicio TEXT,
        fecha_fin TEXT,
        plan TEXT,
        features_json TEXT,
        device_id TEXT,
        ultima_validacion TEXT,
        proxima_validacion TEXT,
        dias_gracia_offline INTEGER NOT NULL DEFAULT 3,
        max_dispositivos INTEGER,
        firma TEXT
      )
    ''');
  }

  Future<void> _migrarV5aV6(Database db) async {
    await _agregarColumnaSiNoExiste(db, 'Licencias', 'ultimo_upgrade_at TEXT');
    await _agregarColumnaSiNoExiste(db, 'Licencias', 'ultimo_upgrade_capability TEXT');
    await _agregarColumnaSiNoExiste(db, 'Licencias', 'ultimo_upgrade_plan_requerido TEXT');
    await _agregarColumnaSiNoExiste(db, 'Licencias', 'ultimo_upgrade_plan_actual TEXT');
    await _agregarColumnaSiNoExiste(db, 'Licencias', 'ultimo_upgrade_backend_ok INTEGER');
    await _agregarColumnaSiNoExiste(db, 'Licencias', 'ultimo_upgrade_email_ok INTEGER');
    await _agregarColumnaSiNoExiste(db, 'Licencias', 'ultimo_upgrade_msg TEXT');
  }

  Future<void> _migrarV6aV7(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS UpgradeSolicitudes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL,
        capability TEXT NOT NULL,
        plan_requerido TEXT,
        plan_actual TEXT,
        backend_ok INTEGER NOT NULL DEFAULT 0,
        email_ok INTEGER NOT NULL DEFAULT 0,
        mensaje TEXT
      )
    ''');
  }

  Future<void> _agregarColumnaSiNoExiste(
    Database db,
    String tabla,
    String definicionColumna,
  ) async {
    final nombreColumna = definicionColumna.trim().split(RegExp(r'\s+')).first;
    final pragma = await db.rawQuery("PRAGMA table_info($tabla)");
    final existe = pragma.any((col) => col['name'] == nombreColumna);
    if (!existe) {
      await db.execute('ALTER TABLE $tabla ADD COLUMN $definicionColumna');
    }
  }

  Future<void> _insertarDatosIniciales(Database db) async {
    // A. Perfil Base
    await db.insert('PerfilUsuario', {'nombre_tirador': '', 'numero_licencia': '', 'club': '', 'categoria': ''});

    // B. Catálogos
    for (var t in ['Pistola Aire', 'Pistola Fuego', 'Carabina Aire', 'Carabina Fuego', 'Pistola 9mm/Central', 'Avancarga']) {
      await db.insert('CatalogoTiposArma', {'nombre': t});
    }
    for (var c in ['4.5mm (.177)', '.22 LR', '9mm', '.32 S&W', '.38 Special', '.45 ACP', '.44-40', '.36 (Avancarga)', '.44 (Avancarga)']) {
      await db.insert('CatalogoCalibres', {'nombre': c});
    }
    
    // C. Dianas Oficiales
    int idDianaPrec = await db.insert('CatalogoDianas', {
      'nombre': 'ISSF 25m/50m Precisión', 'valor_minimo': 1, 'anillo_negro_inicio': 7, 'es_fondo_negro': 0, 'tiene_mosca': 1, 'tiene_guias': 0, 'ancho_exterior_mm': 500.0, 'alto_exterior_mm': 500.0
    });
    int idDianaDuelo = await db.insert('CatalogoDianas', {
      'nombre': 'ISSF 25m Duelo/Rápido', 'valor_minimo': 5, 'anillo_negro_inicio': 5, 'es_fondo_negro': 1, 'tiene_mosca': 1, 'tiene_guias': 1, 'ancho_exterior_mm': 500.0, 'alto_exterior_mm': 500.0
    });
    int idDianaAire = await db.insert('CatalogoDianas', {
      'nombre': 'ISSF 10m Aire', 'valor_minimo': 1, 'anillo_negro_inicio': 7, 'es_fondo_negro': 0, 'tiene_mosca': 1, 'tiene_guias': 0, 'ancho_exterior_mm': 170.0, 'alto_exterior_mm': 170.0
    });

    // D. PLANTILLAS DE TIEMPOS
    
    // Tiempos Precisión
    int idP_5min = await db.insert('PlantillasTiempos', {
      'nombre_disciplina': 'Serie Precisión 5min', 'disparos_por_serie': 5, 'series_por_sesion': 1,
      'puntuacion_decimal': 0, 'tiempo_preparacion': 60, 'es_duelo': 0, 'tiempo_exposicion': 300, 'tiempo_ocultacion': 0, 'id_tipo_diana': idDianaPrec
    });
    
    // Tiempos Duelo
    int idD_3_7 = await db.insert('PlantillasTiempos', {
      'nombre_disciplina': 'Serie Duelo 3s/7s', 'disparos_por_serie': 5, 'series_por_sesion': 1,
      'puntuacion_decimal': 0, 'tiempo_preparacion': 60, 'es_duelo': 1, 'tiempo_exposicion': 3, 'tiempo_ocultacion': 7, 'id_tipo_diana': idDianaDuelo
    });
    
    // Tiempos Standard / Velocidad
    int idStd_20s = await db.insert('PlantillasTiempos', {
      'nombre_disciplina': 'Serie Rápida 20s', 'disparos_por_serie': 5, 'series_por_sesion': 1,
      'puntuacion_decimal': 0, 'tiempo_preparacion': 60, 'es_duelo': 0, 'tiempo_exposicion': 20, 'tiempo_ocultacion': 0, 'id_tipo_diana': idDianaPrec
    });
    int idStd_10s = await db.insert('PlantillasTiempos', {
      'nombre_disciplina': 'Serie Rápida 10s', 'disparos_por_serie': 5, 'series_por_sesion': 1,
      'puntuacion_decimal': 0, 'tiempo_preparacion': 60, 'es_duelo': 0, 'tiempo_exposicion': 10, 'tiempo_ocultacion': 0, 'id_tipo_diana': idDianaPrec
    });
    
    // Tiempos Velocidad (8, 6, 4)
    int idVel_8s = await db.insert('PlantillasTiempos', {
      'nombre_disciplina': 'Serie Velocidad 8s', 'disparos_por_serie': 5, 'series_por_sesion': 1,
      'puntuacion_decimal': 0, 'tiempo_preparacion': 60, 'es_duelo': 0, 'tiempo_exposicion': 8, 'tiempo_ocultacion': 0, 'id_tipo_diana': idDianaDuelo
    });
    int idVel_6s = await db.insert('PlantillasTiempos', {
      'nombre_disciplina': 'Serie Velocidad 6s', 'disparos_por_serie': 5, 'series_por_sesion': 1,
      'puntuacion_decimal': 0, 'tiempo_preparacion': 60, 'es_duelo': 0, 'tiempo_exposicion': 6, 'tiempo_ocultacion': 0, 'id_tipo_diana': idDianaDuelo
    });
    int idVel_4s = await db.insert('PlantillasTiempos', {
      'nombre_disciplina': 'Serie Velocidad 4s', 'disparos_por_serie': 5, 'series_por_sesion': 1,
      'puntuacion_decimal': 0, 'tiempo_preparacion': 60, 'es_duelo': 0, 'tiempo_exposicion': 4, 'tiempo_ocultacion': 0, 'id_tipo_diana': idDianaDuelo
    });

    // Tiempos Aire
    int idAire60 = await db.insert('PlantillasTiempos', {
      'nombre_disciplina': 'Aire 10m (Serie 10)', 'disparos_por_serie': 10, 'series_por_sesion': 1,
      'puntuacion_decimal': 0, 'tiempo_preparacion': 60, 'es_duelo': 0, 'tiempo_exposicion': 900, 'tiempo_ocultacion': 0, 'id_tipo_diana': idDianaAire
    });
    int idAireDecimal = await db.insert('PlantillasTiempos', {
      'nombre_disciplina': 'Carabina Decimal', 'disparos_por_serie': 10, 'series_por_sesion': 1,
      'puntuacion_decimal': 1, 'tiempo_preparacion': 60, 'es_duelo': 0, 'tiempo_exposicion': 900, 'tiempo_ocultacion': 0, 'id_tipo_diana': idDianaAire
    });

    // Tiempos Largos (Libre / Avancarga)
    int idLibre = await db.insert('PlantillasTiempos', {
      'nombre_disciplina': 'Libre 50m (Serie 10)', 'disparos_por_serie': 10, 'series_por_sesion': 1,
      'puntuacion_decimal': 0, 'tiempo_preparacion': 60, 'es_duelo': 0, 'tiempo_exposicion': 1200, 'tiempo_ocultacion': 0, 'id_tipo_diana': idDianaPrec
    });
    int idAvancarga = await db.insert('PlantillasTiempos', {
      'nombre_disciplina': 'Avancarga (13 tiros)', 'disparos_por_serie': 13, 'series_por_sesion': 1,
      'puntuacion_decimal': 0, 'tiempo_preparacion': 180, 'es_duelo': 0, 'tiempo_exposicion': 1800, 'tiempo_ocultacion': 0, 'id_tipo_diana': idDianaPrec
    });


    // E. COMPETICIONES OFICIALES (Los "Playlist")

    // 1. PISTOLA FUEGO CENTRAL (15+15) - Versión Club
    int idFC15 = await db.insert('Modalidades', {'nombre': 'Pistola Fuego Central (15+15)', 'descripcion': 'Popular: 15 Precisión + 15 Duelo', 'es_oficial': 1});
    await _crearFase(db, idFC15, 1, idP_5min, 1, 1, "Ensayo Precisión");
    await _crearFase(db, idFC15, 2, idP_5min, 3, 0, "Fase Precisión");
    await _crearFase(db, idFC15, 3, idD_3_7, 1, 1, "Ensayo Duelo");
    await _crearFase(db, idFC15, 4, idD_3_7, 3, 0, "Fase Duelo");

    // 2. PISTOLA FUEGO CENTRAL (30+30) - Oficial
    int idFC30 = await db.insert('Modalidades', {'nombre': 'Pistola Fuego Central (30+30)', 'descripcion': 'Oficial ISSF', 'es_oficial': 1});
    await _crearFase(db, idFC30, 1, idP_5min, 1, 1, "Ensayo Precisión");
    await _crearFase(db, idFC30, 2, idP_5min, 6, 0, "Fase Precisión");
    await _crearFase(db, idFC30, 3, idD_3_7, 1, 1, "Ensayo Duelo");
    await _crearFase(db, idFC30, 4, idD_3_7, 6, 0, "Fase Duelo");

    // 3. PISTOLA STANDARD (20+20+20)
    int idStd = await db.insert('Modalidades', {'nombre': 'Pistola Standard', 'descripcion': '20 tiros en 150s, 20s y 10s', 'es_oficial': 1});
    await _crearFase(db, idStd, 1, idP_5min, 1, 1, "Ensayo 150s");
    await _crearFase(db, idStd, 2, idP_5min, 4, 0, "Fase 150s");
    await _crearFase(db, idStd, 3, idStd_20s, 4, 0, "Fase 20s");
    await _crearFase(db, idStd, 4, idStd_10s, 4, 0, "Fase 10s");

    // 4. PISTOLA 9mm (30+30)
    int id9mm = await db.insert('Modalidades', {'nombre': 'Pistola 9mm', 'descripcion': 'Precisión + Velocidad 20s', 'es_oficial': 1});
    await _crearFase(db, id9mm, 1, idP_5min, 1, 1, "Ensayo Precisión");
    await _crearFase(db, id9mm, 2, idP_5min, 6, 0, "Fase Precisión");
    await _crearFase(db, id9mm, 3, idStd_20s, 1, 1, "Ensayo Velocidad");
    await _crearFase(db, id9mm, 4, idStd_20s, 6, 0, "Fase Velocidad");

    // 5. PISTOLA VELOCIDAD (TRAINING)
    int idVel = await db.insert('Modalidades', {'nombre': 'Pistola Velocidad (Entrenamiento)', 'descripcion': 'Simulacro 8s, 6s, 4s', 'es_oficial': 1});
    await _crearFase(db, idVel, 1, idVel_8s, 1, 1, "Ensayo 8s");
    await _crearFase(db, idVel, 2, idVel_8s, 2, 0, "Serie 8s");
    await _crearFase(db, idVel, 3, idVel_6s, 2, 0, "Serie 6s");
    await _crearFase(db, idVel, 4, idVel_4s, 2, 0, "Serie 4s");

    // 6. PISTOLA AIRE 60
    int idAireP = await db.insert('Modalidades', {'nombre': 'Pistola Aire (60)', 'descripcion': '60 disparos 10m', 'es_oficial': 1});
    await _crearFase(db, idAireP, 1, idAire60, 1, 1, "Ensayos");
    await _crearFase(db, idAireP, 2, idAire60, 6, 0, "Competición");

    // 7. CARABINA AIRE (DECIMAL)
    int idCarab = await db.insert('Modalidades', {'nombre': 'Carabina Aire (Decimal)', 'descripcion': '60 disparos con décimas', 'es_oficial': 1});
    await _crearFase(db, idCarab, 1, idAireDecimal, 1, 1, "Ensayos");
    await _crearFase(db, idCarab, 2, idAireDecimal, 6, 0, "Competición");

    // 8. PISTOLA LIBRE 50M
    int idLibreMod = await db.insert('Modalidades', {'nombre': 'Pistola Libre 50m', 'descripcion': '60 disparos a 50m', 'es_oficial': 1});
    await _crearFase(db, idLibreMod, 1, idLibre, 1, 1, "Ensayos");
    await _crearFase(db, idLibreMod, 2, idLibre, 6, 0, "Competición");

    // 9. AVANCARGA (MARIETTE)
    int idMariette = await db.insert('Modalidades', {'nombre': 'Avancarga (Mariette)', 'descripcion': '13 disparos en 30min', 'es_oficial': 1});
    await _crearFase(db, idMariette, 1, idAvancarga, 1, 0, "Competición (13 tiros)");

    // Equipo Genérico (Con valor de clic)
    await db.insert('Equipos', {
      'nombre': 'Pistola Genérica .22', 'id_tipo_arma': 2, 'id_calibre': 2, 'marca': 'Genérica', 'modelo': 'Club',
      'correccion_click_mm': 5.0
    });
  }

  Future<void> _crearFase(Database db, int idMod, int orden, int idPlant, int reps, int esEnsayo, String desc) async {
    await db.insert('FasesModalidad', {
      'id_modalidad': idMod,
      'orden': orden,
      'id_plantilla_tiempos': idPlant,
      'repeticiones': reps,
      'es_ensayo': esEnsayo,
      'descripcion_fase': desc
    });
  }
}