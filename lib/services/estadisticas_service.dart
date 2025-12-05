import 'dart:math';
import 'package:flutter/material.dart'; // Para DateTimeRange
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
    List<int>? idsSesiones, // ¡NUEVO PARÁMETRO!
  }) {
    String where = "1=1"; 

    // Si nos pasan IDs específicos, IGNORAMOS el resto de filtros
    if (idsSesiones != null && idsSesiones.isNotEmpty) {
      // Construimos: AND s.id IN (1, 2, 3)
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

  // --- 1. EVOLUCIÓN ---
  Future<List<Map<String, dynamic>>> obtenerEvolucionPuntos({
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? idTipoDiana,
    int? filtroModo,
    List<int>? idsSesiones, // Nuevo
  }) async {
    final db = await dbProvider.database;
    List<dynamic> args = [];
    String whereClause = _construirWhere(args, 
      rangoFechas: rangoFechas, idEquipo: idEquipo, idTipoDiana: idTipoDiana, filtroModo: filtroModo,
      idsSesiones: idsSesiones
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

  // --- 2. ANÁLISIS AVANZADO (AGRUPACIÓN) ---
  Future<AnalisisAgrupacion> calcularAnalisisAgrupacion({
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? idTipoDiana,
    int? filtroModo,
    List<int>? idsSesiones, // Nuevo
  }) async {
    final db = await dbProvider.database;
    List<dynamic> args = [];
    String whereClause = _construirWhere(args, 
      rangoFechas: rangoFechas, idEquipo: idEquipo, idTipoDiana: idTipoDiana, filtroModo: filtroModo,
      idsSesiones: idsSesiones
    );

    final res = await db.rawQuery('''
      SELECT d.*, cd.valor_minimo, cd.anillo_negro_inicio
      FROM Disparos d
      JOIN Sesiones s ON d.id_sesion = s.id
      JOIN PlantillasTiempos p ON s.id_plantilla_tiempos = p.id
      JOIN CatalogoDianas cd ON p.id_tipo_diana = cd.id
      WHERE $whereClause
      LIMIT 2000
    ''', args);

    List<Disparo> disparos = res.map((e) => Disparo.fromMap(e)).toList();
    
    if (disparos.isEmpty) return AnalisisAgrupacion(disparos: [], puntuacionRealMedia: 0, puntuacionPotencialMedia: 0, radioDisperson: 0, mpi: const Point(0,0));

    double sumX = 0, sumY = 0;
    double sumPuntosReales = 0;
    for (var d in disparos) {
      sumX += d.x;
      sumY += d.y;
      sumPuntosReales += d.puntuacion;
    }
    double mpiX = sumX / disparos.length;
    double mpiY = sumY / disparos.length;
    
    double sumPuntosPotenciales = 0;
    double sumRadio = 0;
    int valorMinimo = res.first['valor_minimo'] as int;
    bool esEstiloDuelo = (res.first['anillo_negro_inicio'] as int) <= 5;

    for (var d in disparos) {
      double distAlMPI = sqrt(pow(d.x - mpiX, 2) + pow(d.y - mpiY, 2));
      sumRadio += distAlMPI;
      
      double distCentrada = distAlMPI; 
      int puntosVirtuales = 0;
      if (distCentrada <= 1.0) {
          if (esEstiloDuelo) {
             double calculo = 11 - (distCentrada * 6);
             puntosVirtuales = calculo.floor();
             if (puntosVirtuales < 5) puntosVirtuales = 0; 
             if (puntosVirtuales > 10) puntosVirtuales = 10;
          } else {
             int totalZonas = 11 - valorMinimo;
             double calculo = 11 - (distCentrada * totalZonas);
             puntosVirtuales = calculo.floor();
             if (puntosVirtuales < valorMinimo) puntosVirtuales = 0;
             if (puntosVirtuales > 10) puntosVirtuales = 10;
          }
      }
      sumPuntosPotenciales += puntosVirtuales;
    }

    return AnalisisAgrupacion(
      disparos: disparos,
      mpi: Point(mpiX, mpiY),
      puntuacionRealMedia: sumPuntosReales / disparos.length,
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