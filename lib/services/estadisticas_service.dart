import 'dart:math';
import 'package:flutter/material.dart';
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

  // --- 2. OBTENER DIANAS ---
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
    // (El código de esta función se mantiene IGUAL que antes,
    //  lo copio aquí para que el archivo esté completo y compile)
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
    
    if (disparos.isEmpty) return AnalisisAgrupacion(disparos: [], puntuacionRealMedia: 0, puntuacionPotencialMedia: 0, radioDisperson: 0, mpi: const Point(0,0));

    double sumX = 0, sumY = 0, sumPuntos = 0;
    for (var d in disparos) { sumX += d.x; sumY += d.y; sumPuntos += d.puntuacion; }
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
             if (puntosVirtuales < 5) puntosVirtuales = 0; if (puntosVirtuales > 10) puntosVirtuales = 10;
          } else {
             int totalZonas = 11 - valorMinimo;
             double calculo = 11 - (distCentrada * totalZonas);
             puntosVirtuales = calculo.floor();
             if (puntosVirtuales < valorMinimo) puntosVirtuales = 0; if (puntosVirtuales > 10) puntosVirtuales = 10;
          }
      }
      sumPuntosPotenciales += puntosVirtuales;
    }

    return AnalisisAgrupacion(
      disparos: disparos,
      mpi: Point(mpiX, mpiY),
      puntuacionRealMedia: sumPuntos / disparos.length,
      puntuacionPotencialMedia: sumPuntosPotenciales / disparos.length,
      radioDisperson: sumRadio / disparos.length,
    );
  }

  // --- 4. ¡NUEVO! DIAGNÓSTICO TÉCNICO (RELOJ DE ERRORES) ---
  Future<List<DiagnosticoTecnico>> calcularDiagnosticoTecnico({
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? idTipoDiana,
    int? filtroModo,
    List<int>? idsSesiones,
    bool esZurdo = false, // Importante para invertir el reloj
  }) async {
    final db = await dbProvider.database;
    List<dynamic> args = [];
    String whereClause = _construirWhere(args, rangoFechas: rangoFechas, idEquipo: idEquipo, idTipoDiana: idTipoDiana, filtroModo: filtroModo, idsSesiones: idsSesiones);

    // Solo analizamos disparos que NO sean dieces perfectos (puntuacion < 9.8 aprox o fuera del centro)
    // Asumimos que un 10 no es un error técnico.
    final res = await db.rawQuery('''
      SELECT d.* FROM Disparos d
      JOIN Sesiones s ON d.id_sesion = s.id
      JOIN PlantillasTiempos p ON s.id_plantilla_tiempos = p.id
      WHERE $whereClause AND d.puntuacion < 9.5 
      LIMIT 1000
    ''', args);

    List<Disparo> fallos = res.map((e) => Disparo.fromMap(e)).toList();
    
    // Mapa de errores
    Map<String, int> conteoErrores = {
      "Gatillazo (Dedazo)": 0,
      "Muñeca floja (Breaking)": 0,
      "Apretar Empuñadura": 0,
      "Empujar (Anticipación)": 0,
    };

    for (var d in fallos) {
      // Calcular ángulo en grados (0 a 360, donde 0 es las 3 en punto, reloj matemático)
      // Pero para el reloj de tiro: 12h = -90deg, 3h = 0deg, 6h = 90deg, 9h = 180deg
      double angleRad = atan2(d.y, d.x); // y crece hacia abajo en pantalla
      double angleDeg = angleRad * 180 / pi; 
      
      // Normalizamos ángulo de reloj: 12h = 0 grados, horario positivo
      // atan2 devuelve: 0 (3h), 90 (6h), 180/-180 (9h), -90 (12h)
      
      // Convertimos a sistema de "Zonas del Reloj" (simplificado)
      // Definiciones para DIESTRO (Si es zurdo, invertimos izquierda/derecha)
      
      bool izquierda = (angleDeg > 90 || angleDeg < -90); // 9h
      bool derecha = (angleDeg < 90 && angleDeg > -90);   // 3h
      bool abajo = (angleDeg > 0); // 6h
      bool arriba = (angleDeg < 0); // 12h

      // Lógica de Diagnóstico (Clásica Diestro)
      String error = "Desconocido";
      
      if (esZurdo) {
         // INVERTIR LÓGICA HORIZONTAL
         bool temp = izquierda; izquierda = derecha; derecha = temp;
      }

      if (abajo && izquierda) error = "Gatillazo (Dedazo)";
      else if (arriba && derecha) error = "Empujar (Anticipación)";
      else if (abajo && derecha) error = "Apretar Empuñadura";
      else if (arriba && izquierda) error = "Muñeca floja (Breaking)";
      else if (derecha) error = "Dedo índice mal puesto";
      else if (izquierda) error = "Dedo índice poco metido";
      else error = "Falta de estabilidad";

      // Simplificamos a 4 grandes grupos para la gráfica
      if (abajo && izquierda) conteoErrores["Gatillazo (Dedazo)"] = conteoErrores["Gatillazo (Dedazo)"]! + 1;
      else if (arriba && derecha) conteoErrores["Empujar (Anticipación)"] = conteoErrores["Empujar (Anticipación)"]! + 1;
      else if (abajo && derecha) conteoErrores["Apretar Empuñadura"] = conteoErrores["Apretar Empuñadura"]! + 1;
      else if (arriba && izquierda) conteoErrores["Muñeca floja (Breaking)"] = conteoErrores["Muñeca floja (Breaking)"]! + 1;
      // Los otros se ignoran para el gráfico principal o se suman al más cercano
    }

    // Convertir mapa a lista ordenada
    List<DiagnosticoTecnico> resultado = [];
    int totalFallos = fallos.length;
    if (totalFallos == 0) return [];

    conteoErrores.forEach((nombre, cantidad) {
      if (cantidad > 0) {
        double porcentaje = (cantidad / totalFallos) * 100;
        resultado.add(DiagnosticoTecnico(nombreError: nombre, cantidad: cantidad, porcentaje: porcentaje));
      }
    });

    resultado.sort((a, b) => b.cantidad.compareTo(a.cantidad)); // Ordenar por frecuencia
    return resultado;
  }
}

class AnalisisAgrupacion {
  final List<Disparo> disparos;
  final Point<double> mpi;
  final double puntuacionRealMedia;
  final double puntuacionPotencialMedia;
  final double radioDisperson;

  AnalisisAgrupacion({required this.disparos, required this.mpi, required this.puntuacionRealMedia, required this.puntuacionPotencialMedia, required this.radioDisperson});
}

class DiagnosticoTecnico {
  final String nombreError;
  final int cantidad;
  final double porcentaje;
  DiagnosticoTecnico({required this.nombreError, required this.cantidad, required this.porcentaje});
}