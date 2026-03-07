import '../database/database_provider.dart';
import '../models/municion_model.dart';

class MunicionService {
  final dbProvider = DatabaseProvider.instance;
  final String _tabla = 'Municion';
  final String _tablaMovimientos = 'MovimientosMunicion';

  // Obtener lista con detalles (JOIN)
  Future<List<MunicionDetalle>> obtenerMunicionDetallada() async {
    final db = await dbProvider.database;
    final res = await db.rawQuery('''
      SELECT
        m.id,
        m.marca,
        m.lote,
        m.cantidad_inicial,
        m.cantidad_actual,
        m.total_disparada,
        c.nombre as nombre_calibre
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

  Future<MunicionDetalle?> obtenerDetallePorId(int id) async {
    final db = await dbProvider.database;
    final res = await db.rawQuery('''
      SELECT
        m.id,
        m.marca,
        m.lote,
        m.cantidad_inicial,
        m.cantidad_actual,
        m.total_disparada,
        c.nombre as nombre_calibre
      FROM Municion m
      LEFT JOIN CatalogoCalibres c ON m.id_calibre = c.id
      WHERE m.id = ?
      LIMIT 1
    ''', [id]);
    if (res.isEmpty) return null;
    return MunicionDetalle.fromMap(res.first);
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
    return await db.transaction((txn) async {
      await txn.delete(_tablaMovimientos, where: 'id_municion = ?', whereArgs: [id]);
      return txn.delete(_tabla, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> registrarCompra(int idMunicion, int cantidad, {String? nota}) async {
    if (cantidad <= 0) return;
    final db = await dbProvider.database;
    await db.transaction((txn) async {
      await txn.rawUpdate('''
        UPDATE Municion
        SET
          cantidad_inicial = cantidad_inicial + ?,
          cantidad_actual = cantidad_actual + ?
        WHERE id = ?
      ''', [cantidad, cantidad, idMunicion]);

      await txn.insert(_tablaMovimientos, MovimientoMunicion(
        idMunicion: idMunicion,
        tipo: 'compra',
        cantidad: cantidad,
        fecha: DateTime.now(),
        nota: nota,
      ).toMap());
    });
  }

  Future<void> registrarUso(int idMunicion, int cantidad, {String? nota}) async {
    if (cantidad <= 0) return;
    final db = await dbProvider.database;
    await db.transaction((txn) async {
      final res = await txn.query(_tabla, columns: ['cantidad_actual'], where: 'id = ?', whereArgs: [idMunicion], limit: 1);
      if (res.isEmpty) return;

      final actual = (res.first['cantidad_actual'] as num?)?.toInt() ?? 0;
      final usoReal = cantidad > actual ? actual : cantidad;
      if (usoReal <= 0) return;

      await txn.rawUpdate('''
        UPDATE Municion
        SET
          cantidad_actual = cantidad_actual - ?,
          total_disparada = total_disparada + ?
        WHERE id = ?
      ''', [usoReal, usoReal, idMunicion]);

      await txn.insert(_tablaMovimientos, MovimientoMunicion(
        idMunicion: idMunicion,
        tipo: 'uso',
        cantidad: usoReal,
        fecha: DateTime.now(),
        nota: nota,
      ).toMap());
    });
  }

  Future<List<MovimientoMunicion>> obtenerMovimientos(int idMunicion, {int limite = 100}) async {
    final db = await dbProvider.database;
    final res = await db.query(
      _tablaMovimientos,
      where: 'id_municion = ?',
      whereArgs: [idMunicion],
      orderBy: 'fecha DESC',
      limit: limite,
    );
    return res.map((e) => MovimientoMunicion.fromMap(e)).toList();
  }

  Future<List<UsoMunicionSesion>> obtenerDondeSeUso(int idMunicion, {int limite = 100}) async {
    final db = await dbProvider.database;
    final info = await db.rawQuery("PRAGMA table_info(Sesiones)");
    final cols = info.map((e) => (e['name'] as String).toLowerCase()).toSet();

    final hasDistancia = cols.contains('distancia_m');
    final hasInterior = cols.contains('es_interior');
    final hasTemp = cols.contains('temperatura_c');
    final hasHumedad = cols.contains('humedad_pct');
    final hasViento = cols.contains('viento_ms');
    final hasVientoDir = cols.contains('viento_direccion');

    final selectDistancia = hasDistancia ? 's.distancia_m' : 'NULL as distancia_m';
    final selectInterior = hasInterior ? 's.es_interior' : 'NULL as es_interior';
    final selectTemp = hasTemp ? 's.temperatura_c' : 'NULL as temperatura_c';
    final selectHumedad = hasHumedad ? 's.humedad_pct' : 'NULL as humedad_pct';
    final selectViento = hasViento ? 's.viento_ms' : 'NULL as viento_ms';
    final selectVientoDir = hasVientoDir ? 's.viento_direccion' : 'NULL as viento_direccion';

    final res = await db.rawQuery('''
      SELECT
        s.id as id_sesion,
        s.fecha,
        s.lugar,
        s.nota,
        $selectDistancia,
        $selectInterior,
        $selectTemp,
        $selectHumedad,
        $selectViento,
        $selectVientoDir,
        COUNT(d.id) as disparos
      FROM Sesiones s
      LEFT JOIN Disparos d ON d.id_sesion = s.id
      WHERE s.id_municion = ?
      GROUP BY s.id
      ORDER BY s.fecha DESC
      LIMIT ?
    ''', [idMunicion, limite]);
    return res.map((e) => UsoMunicionSesion.fromMap(e)).toList();
  }
}