import 'dart:math';
import 'package:flutter/material.dart'; // Para DateTimeRange
import 'package:sqflite/sqflite.dart';
import '../database/database_provider.dart';
import '../models/disparo_model.dart';
import '../models/tipo_diana_model.dart'; // Necesario para devolver la lista de dianas

class EstadisticasService {
  final dbProvider = DatabaseProvider.instance;

  String _construirWhere(List<dynamic> args, {
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? idTipoDiana,
    int? filtroModo,
    List<int>? idsSesiones,
  }) {
    String where = "1=1"; 

    if (idsSesiones != null && idsSesiones.isNotEmpty) {
      where += " AND s.id IN (${List.filled(idsSesiones.length, '?').join(',')})";
      args.addAll(idsSesiones);
      return where; 
    }

    if (rangoFechas != null) {
      where += " AND s.fecha >= ? AND s.fecha <= ?";
      final fin = DateTime(rangoFechas.end.year, rangoFechas.end.month, rangoFechas.end.day, 23, 59, 59);
      args.add(rangoFechas.start.toIso8601String());
      args.add(fin.toIso8601String());
    }
    if (idEquipo != null) {
      where += " AND s.id_equipo = ?";
      args.add(idEquipo);
    }
    if (idTipoDiana != null) {
      where += " AND p.id_tipo_diana = ?";
      args.add(idTipoDiana);
    }
    if (filtroModo == 1) {
      where += " AND s.id_modalidad IS NULL"; 
    } else if (filtroModo == 2) {
      where += " AND s.id_modalidad IS NOT NULL"; 
    }
    return where;
  }

  // --- 1. EVOLUCIÓN (Mezcla todo o filtra si se pide) ---
  Future<List<Map<String, dynamic>>> obtenerEvolucionPuntos({
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? idTipoDiana, // ¡AÑADIDO PARA CORREGIR EL ERROR!
    int? filtroModo,
    List<int>? idsSesiones,
  }) async {
    final db = await dbProvider.database;
    List<dynamic> args = [];
    
    // Pasamos idTipoDiana como null intencionalmente si queremos mezclar todo,
    // O pasamos la variable si queremos permitir filtrar evolución por diana.
    // Para mantener la lógica de "ver tendencia global", pasamos null aquí:
    String whereClause = _construirWhere(args, 
      rangoFechas: rangoFechas, idEquipo: idEquipo, idTipoDiana: null, filtroModo: filtroModo, idsSesiones: idsSesiones
    );

    final res = await db.rawQuery('''
      SELECT s.fecha, COALESCE(SUM(d.puntuacion), 0) as total
      FROM Sesiones s
      JOIN PlantillasTiempos p ON s.id_plantilla_tiempos = p.id
      LEFT JOIN Disparos d ON s.id = d.id_sesion
      WHERE $whereClause
      GROUP BY s.id
      ORDER BY s.fecha ASC
    ''', args);

    return res;
  }

  // --- 2. NUEVO: OBTENER DIANAS DISPONIBLES EN EL FILTRO ---
  Future<List<TipoDiana>> obtenerTiposDianaEnFiltro({
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? filtroModo,
    List<int>? idsSesiones,
  }) async {
    final db = await dbProvider.database;
    List<dynamic> args = [];
    String whereClause = _construirWhere(args, 
      rangoFechas: rangoFechas, idEquipo: idEquipo, idTipoDiana: null, filtroModo: filtroModo, idsSesiones: idsSesiones
    );

    // Buscamos qué tipos de diana aparecen en las sesiones filtradas
    final res = await db.rawQuery('''
      SELECT DISTINCT cd.*
      FROM CatalogoDianas cd
      JOIN PlantillasTiempos p ON cd.id = p.id_tipo_diana
      JOIN Sesiones s ON p.id = s.id_plantilla_tiempos
      WHERE $whereClause
      ORDER BY cd.nombre
    ''', args);

    return res.map((e) => TipoDiana.fromMap(e)).toList();
  }

  // --- 3. ANÁLISIS AGRUPACIÓN (Filtra por diana específica) ---
  Future<AnalisisAgrupacion> calcularAnalisisAgrupacion({
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? idTipoDiana, // ESTE ES OBLIGATORIO AHORA PARA NO MEZCLAR
    int? filtroModo,
    List<int>? idsSesiones,
  }) async {
    final db = await dbProvider.database;
    List<dynamic> args = [];
    String whereClause = _construirWhere(args, 
      rangoFechas: rangoFechas, idEquipo: idEquipo, idTipoDiana: idTipoDiana, filtroModo: filtroModo, idsSesiones: idsSesiones
    );

    final res = await db.rawQuery('''
      SELECT d.*
      FROM Disparos d
      JOIN Sesiones s ON d.id_sesion = s.id
      JOIN PlantillasTiempos p ON s.id_plantilla_tiempos = p.id
      WHERE $whereClause
      LIMIT 2000
    ''', args);

    List<Disparo> disparos = res.map((e) => Disparo.fromMap(e)).toList();
    
    if (disparos.isEmpty) return AnalisisAgrupacion(disparos: [], puntuacionRealMedia: 0, puntuacionPotencialMedia: 0, radioDisperson: 0, mpi: const Point(0,0));

    // Calcular MPI
    double sumX = 0, sumY = 0, sumPuntos = 0;
    for (var d in disparos) { sumX += d.x; sumY += d.y; sumPuntos += d.puntuacion; }
    double mpiX = sumX / disparos.length;
    double mpiY = sumY / disparos.length;
    
    // Calcular Potencial
    // Para hacerlo exacto necesitaríamos saber la diana, asumimos la del filtro o la primera si no
    // En este caso, como el análisis requiere idTipoDiana, podemos asumir su lógica
    // Si idTipoDiana es null (error), devolvemos básico.
    
    // Recuperar datos diana si no los tenemos (opcional, para cálculo exacto de potencial)
    // Por simplicidad, usaremos una lógica estándar aquí o podemos hacer una query extra.
    // Asumiremos Precisión (1-10) por defecto para el cálculo potencial si no hay datos específicos de diana en la query de disparos.
    
    double sumPuntosPotenciales = 0;
    double sumRadio = 0;

    for (var d in disparos) {
      double dist = sqrt(pow(d.x - mpiX, 2) + pow(d.y - mpiY, 2));
      sumRadio += dist;
      // Cálculo simplificado de potencial (asumiendo diana precisión)
      double calc = 11 - (dist * 10); 
      if (calc > 10) calc = 10; if (calc < 0) calc = 0;
      sumPuntosPotenciales += calc.floor();
    }

    return AnalisisAgrupacion(
      disparos: disparos,
      mpi: Point(mpiX, mpiY),
      puntuacionRealMedia: sumPuntos / disparos.length,
      puntuacionPotencialMedia: sumPuntosPotenciales / disparos.length,
      radioDisperson: sumRadio / disparos.length,
    );
  }
}

class AnalisisAgrupacion {
  final List<Disparo> disparos;
  final Point<double> mpi;
  final double puntuacionRealMedia;
  final double puntuacionPotencialMedia;
  final double radioDisperson;

  AnalisisAgrupacion({
    required this.disparos,
    required this.mpi,
    required this.puntuacionRealMedia,
    required this.puntuacionPotencialMedia,
    required this.radioDisperson,
  });
}