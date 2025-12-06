import 'dart:math';
import 'package:flutter/material.dart'; 
import 'package:sqflite/sqflite.dart';
import '../database/database_provider.dart';
import '../models/disparo_model.dart';
import '../models/tipo_diana_model.dart';

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

  // --- 1. EVOLUCIÓN ---
  Future<List<Map<String, dynamic>>> obtenerEvolucionPuntos({
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? idTipoDiana,
    int? filtroModo,
    List<int>? idsSesiones,
  }) async {
    final db = await dbProvider.database;
    List<dynamic> args = [];
    String whereClause = _construirWhere(args, rangoFechas: rangoFechas, idEquipo: idEquipo, idTipoDiana: idTipoDiana, filtroModo: filtroModo, idsSesiones: idsSesiones);

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

  // --- 2. OBTENER DIANAS ---
  Future<List<TipoDiana>> obtenerTiposDianaEnFiltro({
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? filtroModo,
    List<int>? idsSesiones,
  }) async {
    final db = await dbProvider.database;
    List<dynamic> args = [];
    String whereClause = _construirWhere(args, rangoFechas: rangoFechas, idEquipo: idEquipo, idTipoDiana: null, filtroModo: filtroModo, idsSesiones: idsSesiones);

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

  // --- 3. ANÁLISIS AGRUPACIÓN ---
  Future<AnalisisAgrupacion> calcularAnalisisAgrupacion({
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? idTipoDiana,
    int? filtroModo,
    List<int>? idsSesiones,
  }) async {
    final db = await dbProvider.database;
    List<dynamic> args = [];
    String whereClause = _construirWhere(args, rangoFechas: rangoFechas, idEquipo: idEquipo, idTipoDiana: idTipoDiana, filtroModo: filtroModo, idsSesiones: idsSesiones);

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
    
    if (disparos.isEmpty) return AnalisisAgrupacion(disparosValidos: [], disparosDescartados: [], puntuacionRealMedia: 0, puntuacionPotencialMedia: 0, mpi: const Point(0,0), radioDisperson: 0);

    // 1. MPI Inicial
    double sumX = 0, sumY = 0, sumPuntos = 0;
    for (var d in disparos) { sumX += d.x; sumY += d.y; sumPuntos += d.puntuacion; }
    double mpiX = sumX / disparos.length;
    double mpiY = sumY / disparos.length;
    
    // 2. FILTRO DE FLYERS
    List<Disparo> validos = [];
    List<Disparo> descartados = [];
    
    if (disparos.length < 5) {
      validos = List.from(disparos);
    } else {
      double sumaDistancias = 0;
      for (var d in disparos) {
        sumaDistancias += sqrt(pow(d.x - mpiX, 2) + pow(d.y - mpiY, 2));
      }
      double distanciaMedia = sumaDistancias / disparos.length;
      double umbral = distanciaMedia * 2.5; 
      
      for (var d in disparos) {
        double dist = sqrt(pow(d.x - mpiX, 2) + pow(d.y - mpiY, 2));
        if (dist > umbral && dist > 0.15) {
           descartados.add(d);
        } else {
           validos.add(d);
        }
      }
    }

    // 3. RE-CALCULAR MPI FINO
    if (validos.isNotEmpty) {
       sumX = 0; sumY = 0;
       for (var d in validos) { sumX += d.x; sumY += d.y; }
       mpiX = sumX / validos.length;
       mpiY = sumY / validos.length;
    }

    // 4. Calcular Potencial
    double sumPuntosPotenciales = 0;
    double sumRadio = 0;
    int valorMinimo = res.first['valor_minimo'] as int;
    bool esEstiloDuelo = (res.first['anillo_negro_inicio'] as int) <= 5;

    for (var d in validos) {
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
      disparosValidos: validos,
      disparosDescartados: descartados,
      mpi: Point(mpiX, mpiY),
      puntuacionRealMedia: sumPuntos / disparos.length,
      puntuacionPotencialMedia: validos.isEmpty ? 0 : sumPuntosPotenciales / validos.length,
      radioDisperson: validos.isEmpty ? 0 : sumRadio / validos.length,
    );
  }

  // --- 4. DIAGNÓSTICO TÉCNICO (RESTAURADO) ---
  Future<List<DiagnosticoTecnico>> calcularDiagnosticoTecnico({
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? idTipoDiana,
    int? filtroModo,
    List<int>? idsSesiones,
    bool esZurdo = false, 
    bool generarEtiquetas = false,
  }) async {
    final db = await dbProvider.database;
    List<dynamic> args = [];
    String whereClause = _construirWhere(args, rangoFechas: rangoFechas, idEquipo: idEquipo, idTipoDiana: idTipoDiana, filtroModo: filtroModo, idsSesiones: idsSesiones);

    final res = await db.rawQuery('''
      SELECT d.*, s.nota 
      FROM Disparos d
      JOIN Sesiones s ON d.id_sesion = s.id
      JOIN PlantillasTiempos p ON s.id_plantilla_tiempos = p.id
      WHERE $whereClause AND d.puntuacion < 9.5 
      LIMIT 1000
    ''', args);

    Map<String, List<String>> mapaErrores = {
      "Gatillazo (Dedazo)": [],
      "Muñeca floja (Breaking)": [],
      "Apretar Empuñadura": [],
      "Empujar (Anticipación)": [],
    };

    for (var row in res) {
      Disparo d = Disparo.fromMap(row);
      String notaSesion = row['nota'] as String? ?? "";
      
      String etiqueta = "#${d.numero}";
      if (generarEtiquetas) {
          if (notaSesion.contains("Serie")) {
             final regex = RegExp(r'Serie (\d+)');
             final match = regex.firstMatch(notaSesion);
             if (match != null) {
                etiqueta = "#S${match.group(1)}-${d.numero}";
             }
          }
      }

      double angleRad = atan2(d.y, d.x); 
      double angleDeg = angleRad * 180 / pi; 
      bool izquierda = (angleDeg > 90 || angleDeg < -90); 
      bool derecha = (angleDeg < 90 && angleDeg > -90);   
      bool abajo = (angleDeg > 0); 
      bool arriba = (angleDeg < 0); 

      if (esZurdo) { bool temp = izquierda; izquierda = derecha; derecha = temp; }

      String errorKey = "";
      if (abajo && izquierda) errorKey = "Gatillazo (Dedazo)";
      else if (arriba && derecha) errorKey = "Empujar (Anticipación)";
      else if (abajo && derecha) errorKey = "Apretar Empuñadura";
      else if (arriba && izquierda) errorKey = "Muñeca floja (Breaking)";

      if (errorKey.isNotEmpty && mapaErrores.containsKey(errorKey)) {
         mapaErrores[errorKey]!.add(etiqueta);
      }
    }

    List<DiagnosticoTecnico> resultado = [];
    int totalFallos = res.length;
    if (totalFallos == 0) return [];

    mapaErrores.forEach((nombre, etiquetas) {
      if (etiquetas.isNotEmpty) {
        double porcentaje = (etiquetas.length / totalFallos) * 100;
        resultado.add(DiagnosticoTecnico(
            nombreError: nombre, 
            cantidad: etiquetas.length, 
            porcentaje: porcentaje,
            etiquetas: generarEtiquetas ? etiquetas : [] 
        ));
      }
    });

    resultado.sort((a, b) => b.cantidad.compareTo(a.cantidad)); 
    return resultado;
  }
}

// MODELOS INTERNOS
class AnalisisAgrupacion {
  final List<Disparo> disparosValidos;
  final List<Disparo> disparosDescartados;
  final Point<double> mpi;
  final double puntuacionRealMedia;
  final double puntuacionPotencialMedia;
  final double radioDisperson;

  AnalisisAgrupacion({
    required this.disparosValidos,
    required this.disparosDescartados,
    required this.mpi,
    required this.puntuacionRealMedia,
    required this.puntuacionPotencialMedia,
    required this.radioDisperson,
  });
}

class DiagnosticoTecnico {
  final String nombreError;
  final int cantidad;
  final double porcentaje;
  final List<String> etiquetas;

  DiagnosticoTecnico({
    required this.nombreError, 
    required this.cantidad, 
    required this.porcentaje,
    this.etiquetas = const [],
  });
}