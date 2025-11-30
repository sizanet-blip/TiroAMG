import 'package:sqflite/sqflite.dart';
import '../database/database_provider.dart';
import '../models/sesion_model.dart';
import '../models/disparo_model.dart';
import '../models/informe_model.dart';

class EntrenamientoService {
  final dbProvider = DatabaseProvider.instance;

  // 1. Guardar Sesión
  Future<void> guardarSesionCompleta(Sesion sesion, List<Disparo> disparos) async {
    final db = await dbProvider.database;
    await db.transaction((txn) async {
      int idSesionGenerado = await txn.insert('Sesiones', sesion.toMap());
      for (var disparo in disparos) {
        var mapaDisparo = disparo.toMap();
        mapaDisparo['id_sesion'] = idSesionGenerado;
        await txn.insert('Disparos', mapaDisparo);
      }
    });
  }
  
  // 2. ACTUALIZAR SESIÓN (¡NUEVO!)
  Future<void> actualizarSesion({
    required int idSesion,
    required int nuevoIdEquipo,
    required String nuevasNotas,
    required String nuevoLugar,
  }) async {
    final db = await dbProvider.database;
    await db.update(
      'Sesiones',
      {
        'id_equipo': nuevoIdEquipo,
        'nota': nuevasNotas,
        'lugar': nuevoLugar
      },
      where: 'id = ?',
      whereArgs: [idSesion]
    );
  }

  // 3. Actualizar Torneo Completo
  Future<void> actualizarDatosTorneoCompleto({
    required int idModalidad,
    required DateTime fecha,
    required int nuevoIdEquipo,
    required String nuevasNotas,
    required String nuevoLugar,
  }) async {
    final db = await dbProvider.database;
    String fechaStr = fecha.toIso8601String().substring(0, 10);
    
    await db.update(
      'Sesiones',
      {
        'id_equipo': nuevoIdEquipo,
        'nota': nuevasNotas,
        'lugar': nuevoLugar
      },
      where: 'id_modalidad = ? AND fecha LIKE ?',
      whereArgs: [idModalidad, '$fechaStr%']
    );
  }

  // --- LECTURAS ---
  Future<List<SesionResumen>> obtenerEntrenamientos() async {
    final db = await dbProvider.database;
    final res = await db.rawQuery('''
      SELECT 
        s.id, s.fecha, s.nota, s.lugar,
        e.nombre AS nombre_equipo, p.nombre_disciplina AS titulo,
        COALESCE(SUM(d.puntuacion), 0) as total_puntos,
        COALESCE(SUM(CASE WHEN d.es_mosca = 1 THEN 1 ELSE 0 END), 0) as total_moscas
      FROM Sesiones s
      LEFT JOIN Equipos e ON s.id_equipo = e.id
      LEFT JOIN PlantillasTiempos p ON s.id_plantilla_tiempos = p.id
      LEFT JOIN Disparos d ON s.id = d.id_sesion
      WHERE s.id_modalidad IS NULL
      GROUP BY s.id
      ORDER BY s.fecha DESC
    ''');
    return res.map((e) => SesionResumen.fromMap(e)).toList();
  }

  Future<List<SesionResumen>> obtenerCompeticionesAgrupadas() async {
    final db = await dbProvider.database;
    final res = await db.rawQuery('''
      SELECT 
        m.id as id_modalidad, 
        STRFTIME('%Y-%m-%d', s.fecha) as fecha_dia,
        MAX(s.fecha) as fecha_completa,
        e.nombre AS nombre_equipo,
        m.nombre AS titulo_torneo,
        MAX(s.lugar) as lugar,
        MAX(s.nota) as nota,
        COALESCE(SUM(CASE WHEN s.nota NOT LIKE '%Ensayo%' THEN d.puntuacion ELSE 0 END), 0) as total_puntos,
        COALESCE(SUM(CASE WHEN s.nota NOT LIKE '%Ensayo%' AND d.es_mosca = 1 THEN 1 ELSE 0 END), 0) as total_moscas,
        1 as es_competicion_flag
      FROM Sesiones s
      JOIN Modalidades m ON s.id_modalidad = m.id
      LEFT JOIN Equipos e ON s.id_equipo = e.id
      LEFT JOIN Disparos d ON s.id = d.id_sesion
      WHERE s.id_modalidad IS NOT NULL
      GROUP BY m.id, fecha_dia
      ORDER BY fecha_completa DESC
    ''');
    
    return res.map((row) {
        var map = Map<String, dynamic>.from(row);
        map['id'] = row['id_modalidad'];
        map['fecha'] = row['fecha_completa'];
        map['nombre_equipo'] = row['nombre_equipo'];
        map['nombre_disciplina'] = row['titulo_torneo'];
        map['id_modalidad'] = 1;
        return SesionResumen.fromMap(map);
    }).toList();
  }

  Future<List<SesionResumen>> obtenerFasesDeTorneoRealizado(int idModalidad, DateTime fecha) async {
    final db = await dbProvider.database;
    String fechaStr = fecha.toIso8601String().substring(0, 10);

    final res = await db.rawQuery('''
      SELECT 
        s.id, s.fecha, s.nota, s.lugar,
        e.nombre AS nombre_equipo,
        p.nombre_disciplina AS titulo,
        COALESCE(SUM(d.puntuacion), 0) as total_puntos,
        COALESCE(SUM(CASE WHEN d.es_mosca = 1 THEN 1 ELSE 0 END), 0) as total_moscas
      FROM Sesiones s
      LEFT JOIN Equipos e ON s.id_equipo = e.id
      LEFT JOIN PlantillasTiempos p ON s.id_plantilla_tiempos = p.id
      LEFT JOIN Disparos d ON s.id = d.id_sesion
      WHERE s.id_modalidad = ? AND s.fecha LIKE ?
      GROUP BY s.id
      ORDER BY s.fecha ASC
    ''', [idModalidad, '$fechaStr%']);

    return res.map((e) => SesionResumen.fromMap(e)).toList();
  }

  Future<List<GrupoFaseInforme>> obtenerDatosInformeTorneo(int idModalidad, DateTime fecha) async {
    final db = await dbProvider.database;
    String fechaStr = fecha.toIso8601String().substring(0, 10);
    
    final sesionesRaw = await db.rawQuery('''
      SELECT 
        s.id as id_sesion, s.nota, s.lugar,
        p.nombre_disciplina,
        cd.valor_minimo, cd.anillo_negro_inicio, cd.es_fondo_negro, cd.tiene_mosca, cd.tiene_guias
      FROM Sesiones s
      JOIN PlantillasTiempos p ON s.id_plantilla_tiempos = p.id
      JOIN CatalogoDianas cd ON p.id_tipo_diana = cd.id
      WHERE s.id_modalidad = ? AND s.fecha LIKE ?
      ORDER BY s.id ASC
    ''', [idModalidad, '$fechaStr%']);

    Map<String, GrupoFaseInforme> gruposMap = {};

    for (var row in sesionesRaw) {
      String nombre = row['nombre_disciplina'] as String;
      String nota = row['nota'] as String? ?? "";
      bool esEnsayo = nota.contains("Ensayo");
      
      String claveGrupo = "$nombre-${esEnsayo ? 'ENSAYO' : 'COMPE'}";
      int idSesion = row['id_sesion'] as int;
      final tirosRaw = await db.query('Disparos', where: 'id_sesion = ?', whereArgs: [idSesion]);
      List<Disparo> nuevosTiros = tirosRaw.map((t) => Disparo.fromMap(t)).toList();

      if (gruposMap.containsKey(claveGrupo)) {
        gruposMap[claveGrupo]!.disparos.addAll(nuevosTiros);
      } else {
        int anilloNegro = row['anillo_negro_inicio'] as int;
        gruposMap[claveGrupo] = GrupoFaseInforme(
          titulo: esEnsayo ? "$nombre (Ensayo)" : nombre,
          esEnsayo: esEnsayo,
          disparos: nuevosTiros,
          valorMinimo: row['valor_minimo'] as int,
          anilloNegro: anilloNegro,
          esFondoNegro: (row['es_fondo_negro'] as int) == 1,
          tieneMosca: (row['tiene_mosca'] as int) == 1,
          tieneGuias: (row['tiene_guias'] as int) == 1,
          esEstiloDuelo: anilloNegro <= 5,
        );
      }
    }
    return gruposMap.values.toList();
  }

  Future<void> borrarSesion(int id) async {
    final db = await dbProvider.database;
    await db.transaction((txn) async {
      await txn.delete('Disparos', where: 'id_sesion = ?', whereArgs: [id]);
      await txn.delete('Sesiones', where: 'id = ?', whereArgs: [id]);
    });
  }
  
  Future<void> borrarTorneoDeFecha(int idModalidad, DateTime fecha) async {
    final db = await dbProvider.database;
    String fechaStr = fecha.toIso8601String().substring(0, 10);
    final sesiones = await db.query('Sesiones', columns: ['id'], where: 'id_modalidad = ? AND fecha LIKE ?', whereArgs: [idModalidad, '$fechaStr%']);
    await db.transaction((txn) async {
      for (var s in sesiones) {
          int id = s['id'] as int;
          await txn.delete('Disparos', where: 'id_sesion = ?', whereArgs: [id]);
          await txn.delete('Sesiones', where: 'id = ?', whereArgs: [id]);
      }
    });
  }
  Future<Sesion?> obtenerSesionPorId(int id) async {
    final db = await dbProvider.database;
    final res = await db.query('Sesiones', where: 'id = ?', whereArgs: [id]);
    return res.isNotEmpty ? Sesion.fromMap(res.first) : null;
  }
  Future<List<Disparo>> obtenerDisparosDeSesion(int idSesion) async {
    final db = await dbProvider.database;
    final res = await db.query('Disparos', where: 'id_sesion = ?', whereArgs: [idSesion]);
    return res.map((e) => Disparo.fromMap(e)).toList();
  }
}