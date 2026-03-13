import '../database/database_provider.dart';
import '../models/sesion_model.dart';
import '../models/disparo_model.dart';
import '../models/informe_model.dart';

class EntrenamientoService {
  final dbProvider = DatabaseProvider.instance;

  // 1. Guardar Sesión
  Future<void> guardarSesionCompleta(
      Sesion sesion, List<Disparo> disparos) async {
    final db = await dbProvider.database;
    await db.transaction((txn) async {
      int idSesionGenerado = await txn.insert('Sesiones', sesion.toMap());
      for (var disparo in disparos) {
        var mapaDisparo = disparo.toMap();
        mapaDisparo['id_sesion'] = idSesionGenerado;
        await txn.insert('Disparos', mapaDisparo);
      }

      if (sesion.idMunicion != null && disparos.isNotEmpty) {
        final uso = disparos.length;
        final res = await txn.query(
          'Municion',
          columns: ['cantidad_actual'],
          where: 'id = ?',
          whereArgs: [sesion.idMunicion],
          limit: 1,
        );
        if (res.isNotEmpty) {
          final actual = (res.first['cantidad_actual'] as num?)?.toInt() ?? 0;
          final usoReal = uso > actual ? actual : uso;
          if (usoReal > 0) {
            await txn.rawUpdate('''
              UPDATE Municion
              SET
                cantidad_actual = cantidad_actual - ?,
                total_disparada = total_disparada + ?
              WHERE id = ?
            ''', [usoReal, usoReal, sesion.idMunicion]);

            await txn.insert('MovimientosMunicion', {
              'id_municion': sesion.idMunicion,
              'tipo': 'uso',
              'cantidad': usoReal,
              'fecha': DateTime.now().toIso8601String(),
              'nota': 'Sesion $idSesionGenerado',
            });
          }
        }
      }
    });
  }

  // 2. ACTUALIZAR SESIÓN (¡NUEVO!)
  Future<void> actualizarSesion({
    required int idSesion,
    required int nuevoIdEquipo,
    required String nuevasNotas,
    required String nuevoLugar,
    int? distanciaMetros,
    String? posicionTiro,
    bool? esInterior,
    double? temperaturaC,
    double? humedadPct,
    double? presionHpa,
    double? vientoMs,
    String? vientoDireccion,
    String? iluminacion,
  }) async {
    final db = await dbProvider.database;
    await db.update(
        'Sesiones',
        {
          'id_equipo': nuevoIdEquipo,
          'nota': nuevasNotas,
          'lugar': nuevoLugar,
          'distancia_m': distanciaMetros,
          'posicion_tiro': posicionTiro,
          'es_interior': esInterior == null ? null : (esInterior ? 1 : 0),
          'temperatura_c': temperaturaC,
          'humedad_pct': humedadPct,
          'presion_hpa': presionHpa,
          'viento_ms': vientoMs,
          'viento_direccion': vientoDireccion,
          'iluminacion': iluminacion,
        },
        where: 'id = ?',
        whereArgs: [idSesion]);
  }

  // 3. Actualizar Torneo Completo
  Future<void> actualizarDatosTorneoCompleto({
    required int idModalidad,
    required DateTime fecha,
    required int nuevoIdEquipo,
    required String nuevasNotas,
    required String nuevoLugar,
    int? distanciaMetros,
    String? posicionTiro,
    bool? esInterior,
    double? temperaturaC,
    double? humedadPct,
    double? presionHpa,
    double? vientoMs,
    String? vientoDireccion,
    String? iluminacion,
  }) async {
    final db = await dbProvider.database;
    String fechaStr = fecha.toIso8601String().substring(0, 10);

    await db.update(
        'Sesiones',
        {
          'id_equipo': nuevoIdEquipo,
          'nota': nuevasNotas,
          'lugar': nuevoLugar,
          'distancia_m': distanciaMetros,
          'posicion_tiro': posicionTiro,
          'es_interior': esInterior == null ? null : (esInterior ? 1 : 0),
          'temperatura_c': temperaturaC,
          'humedad_pct': humedadPct,
          'presion_hpa': presionHpa,
          'viento_ms': vientoMs,
          'viento_direccion': vientoDireccion,
          'iluminacion': iluminacion,
        },
        where: 'id_modalidad = ? AND fecha LIKE ?',
        whereArgs: [idModalidad, '$fechaStr%']);
  }

  // --- LECTURAS ---
  Future<List<SesionResumen>> obtenerEntrenamientos() async {
    final db = await dbProvider.database;
    final res = await db.rawQuery('''
      SELECT 
        s.id, s.fecha, s.nota, s.lugar, s.id_municion,
        m.marca AS marca_municion,
        m.lote AS lote_municion,
        e.nombre AS nombre_equipo, p.nombre_disciplina AS titulo,
        COALESCE(SUM(d.puntuacion), 0) as total_puntos,
        COALESCE(SUM(CASE WHEN d.es_mosca = 1 THEN 1 ELSE 0 END), 0) as total_moscas
      FROM Sesiones s
      LEFT JOIN Equipos e ON s.id_equipo = e.id
      LEFT JOIN Municion m ON s.id_municion = m.id
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
        MAX(s.id_municion) as id_municion,
        MAX(mu.marca) as marca_municion,
        MAX(mu.lote) as lote_municion,
        MAX(s.lugar) as lugar,
        MAX(s.nota) as nota,
        COALESCE(SUM(CASE WHEN s.nota NOT LIKE '%Ensayo%' THEN d.puntuacion ELSE 0 END), 0) as total_puntos,
        COALESCE(SUM(CASE WHEN s.nota NOT LIKE '%Ensayo%' AND d.es_mosca = 1 THEN 1 ELSE 0 END), 0) as total_moscas,
        1 as es_competicion_flag
      FROM Sesiones s
      JOIN Modalidades m ON s.id_modalidad = m.id
      LEFT JOIN Equipos e ON s.id_equipo = e.id
      LEFT JOIN Municion mu ON s.id_municion = mu.id
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

  Future<List<SesionResumen>> obtenerFasesDeTorneoRealizado(
      int idModalidad, DateTime fecha) async {
    final db = await dbProvider.database;
    String fechaStr = fecha.toIso8601String().substring(0, 10);

    final res = await db.rawQuery('''
      SELECT 
        s.id, s.fecha, s.nota, s.lugar, s.id_municion,
        m.marca AS marca_municion,
        m.lote AS lote_municion,
        e.nombre AS nombre_equipo,
        p.nombre_disciplina AS titulo,
        COALESCE(SUM(d.puntuacion), 0) as total_puntos,
        COALESCE(SUM(CASE WHEN d.es_mosca = 1 THEN 1 ELSE 0 END), 0) as total_moscas
      FROM Sesiones s
      LEFT JOIN Equipos e ON s.id_equipo = e.id
      LEFT JOIN Municion m ON s.id_municion = m.id
      LEFT JOIN PlantillasTiempos p ON s.id_plantilla_tiempos = p.id
      LEFT JOIN Disparos d ON s.id = d.id_sesion
      WHERE s.id_modalidad = ? AND s.fecha LIKE ?
      GROUP BY s.id
      ORDER BY s.fecha ASC
    ''', [idModalidad, '$fechaStr%']);

    return res.map((e) => SesionResumen.fromMap(e)).toList();
  }

  Future<List<GrupoFaseInforme>> obtenerDatosInformeTorneo(
      int idModalidad, DateTime fecha) async {
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
      final tirosRaw = await db
          .query('Disparos', where: 'id_sesion = ?', whereArgs: [idSesion]);
      List<Disparo> nuevosTiros =
          tirosRaw.map((t) => Disparo.fromMap(t)).toList();

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
    final sesiones = await db.query('Sesiones',
        columns: ['id'],
        where: 'id_modalidad = ? AND fecha LIKE ?',
        whereArgs: [idModalidad, '$fechaStr%']);
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
    final res = await db
        .query('Disparos', where: 'id_sesion = ?', whereArgs: [idSesion]);
    return res.map((e) => Disparo.fromMap(e)).toList();
  }

  Future<void> actualizarDisparosSesion({
    required int idSesion,
    required List<Disparo> disparos,
  }) async {
    final db = await dbProvider.database;
    await db.transaction((txn) async {
      for (final disparo in disparos) {
        final payload = {
          'id_sesion': idSesion,
          'numero_disparo': disparo.numero,
          'coordenada_x': disparo.x,
          'coordenada_y': disparo.y,
          'puntuacion': disparo.puntuacion,
          'es_mosca': disparo.esMosca ? 1 : 0,
        };

        if (disparo.id != null) {
          await txn.update(
            'Disparos',
            payload,
            where: 'id = ? AND id_sesion = ?',
            whereArgs: [disparo.id, idSesion],
          );
        } else {
          await txn.insert('Disparos', payload);
        }
      }
    });
  }
}
