import 'dart:math';
import 'package:flutter/material.dart'; // Importante para DateTimeRange
import 'package:sqflite/sqflite.dart';
import '../database/database_provider.dart';
import '../models/disparo_model.dart';

class EstadisticasService {
  final dbProvider = DatabaseProvider.instance;

  String _construirWhere(List<dynamic> args, {
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? idTipoDiana,
    int? filtroModo,
  }) {
    String where = "1=1"; 

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

  Future<List<Map<String, dynamic>>> obtenerEvolucionPuntos({
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? idTipoDiana,
    int? filtroModo,
  }) async {
    final db = await dbProvider.database;
    List<dynamic> args = [];
    
    String whereClause = _construirWhere(args, 
      rangoFechas: rangoFechas, 
      idEquipo: idEquipo, 
      idTipoDiana: idTipoDiana,
      filtroModo: filtroModo
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

  Future<ResultadoAnalisis> obtenerAnalisisImpactos({
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? idTipoDiana,
    int? filtroModo,
  }) async {
    final db = await dbProvider.database;
    List<dynamic> args = [];
    
    String whereClause = _construirWhere(args, 
      rangoFechas: rangoFechas, 
      idEquipo: idEquipo, 
      idTipoDiana: idTipoDiana,
      filtroModo: filtroModo
    );

    final res = await db.rawQuery('''
      SELECT d.* FROM Disparos d
      JOIN Sesiones s ON d.id_sesion = s.id
      JOIN PlantillasTiempos p ON s.id_plantilla_tiempos = p.id
      WHERE $whereClause
      LIMIT 1000
    ''', args);

    List<Disparo> disparos = res.map((e) => Disparo.fromMap(e)).toList();

    Point<double>? centroGravedad;
    if (disparos.isNotEmpty) {
      double sumaX = 0;
      double sumaY = 0;
      for (var d in disparos) {
        sumaX += d.x;
        sumaY += d.y;
      }
      centroGravedad = Point(sumaX / disparos.length, sumaY / disparos.length);
    }

    return ResultadoAnalisis(disparos: disparos, centroGravedad: centroGravedad);
  }
}

class ResultadoAnalisis {
  final List<Disparo> disparos;
  final Point<double>? centroGravedad;

  ResultadoAnalisis({required this.disparos, this.centroGravedad});
}