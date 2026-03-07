import 'dart:math';
import 'package:flutter/material.dart'; 
import '../database/database_provider.dart';
import '../models/disparo_model.dart';
import '../models/tipo_diana_model.dart';

class DetalleError {
  final String etiqueta; 
  final double puntuacion; 
  DetalleError(this.etiqueta, this.puntuacion);
}

class EstadisticasService {
  final dbProvider = DatabaseProvider.instance;

  String _construirWhere(List<dynamic> args, {
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? idTipoDiana,
    int? idMunicion,
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
    if (idEquipo != null) { where += " AND s.id_equipo = ?"; args.add(idEquipo); }
    if (idTipoDiana != null) { where += " AND p.id_tipo_diana = ?"; args.add(idTipoDiana); }
    if (idMunicion != null) { where += " AND s.id_municion = ?"; args.add(idMunicion); }
    if (filtroModo == 1) { where += " AND s.id_modalidad IS NULL"; } 
    else if (filtroModo == 2) { where += " AND s.id_modalidad IS NOT NULL"; }
    return where;
  }

  Future<List<Map<String, dynamic>>> obtenerEvolucionPuntos({DateTimeRange? rangoFechas, int? idEquipo, int? idTipoDiana, int? idMunicion, int? filtroModo, List<int>? idsSesiones}) async {
    final db = await dbProvider.database; List<dynamic> args = [];
    String whereClause = _construirWhere(args, rangoFechas: rangoFechas, idEquipo: idEquipo, idTipoDiana: idTipoDiana, idMunicion: idMunicion, filtroModo: filtroModo, idsSesiones: idsSesiones);
    return await db.rawQuery('''
      SELECT s.fecha, COALESCE(SUM(d.puntuacion), 0) as total
      FROM Sesiones s
      JOIN PlantillasTiempos p ON s.id_plantilla_tiempos = p.id
      LEFT JOIN Disparos d ON s.id = d.id_sesion
      WHERE $whereClause
      GROUP BY s.id
      ORDER BY s.fecha ASC
    ''', args);
  }

  Future<List<TipoDiana>> obtenerTiposDianaEnFiltro({DateTimeRange? rangoFechas, int? idEquipo, int? idMunicion, int? filtroModo, List<int>? idsSesiones}) async {
    final db = await dbProvider.database; List<dynamic> args = [];
    String whereClause = _construirWhere(args, rangoFechas: rangoFechas, idEquipo: idEquipo, idTipoDiana: null, idMunicion: idMunicion, filtroModo: filtroModo, idsSesiones: idsSesiones);
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

  Future<AnalisisAgrupacion> calcularAnalisisAgrupacion({DateTimeRange? rangoFechas, int? idEquipo, int? idTipoDiana, int? idMunicion, int? filtroModo, List<int>? idsSesiones}) async {
    final db = await dbProvider.database; List<dynamic> args = [];
    String whereClause = _construirWhere(args, rangoFechas: rangoFechas, idEquipo: idEquipo, idTipoDiana: idTipoDiana, idMunicion: idMunicion, filtroModo: filtroModo, idsSesiones: idsSesiones);
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
    if (disparos.isEmpty) return AnalisisAgrupacion(disparosValidos: [], disparosDescartados: [], puntuacionRealMedia: 0, puntuacionPotencialMedia: 0, mpi: const Point(0,0), radioDisperson: 0, consejoTendencia: "Sin datos");

    double sumX = 0, sumY = 0, sumPuntos = 0;
    for (var d in disparos) { sumX += d.x; sumY += d.y; sumPuntos += d.puntuacion; }
    double mpiX = sumX / disparos.length; double mpiY = sumY / disparos.length;
    
    List<Disparo> validos = []; List<Disparo> descartados = [];
    if (disparos.length < 5) { validos = List.from(disparos); } else {
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

    if (validos.isNotEmpty) {
       sumX = 0; sumY = 0;
       for (var d in validos) { sumX += d.x; sumY += d.y; }
       mpiX = sumX / validos.length; mpiY = sumY / validos.length;
    }

    // --- CORRECCIÓN AQUÍ: TEXTO SEGURO SIN FLECHAS ---
    String tendencia = "Agrupación Circular (Equilibrada)";
    if (validos.length >= 3) {
       double minX = 999, maxX = -999, minY = 999, maxY = -999;
       for(var d in validos) {
          if (d.x < minX) {
            minX = d.x;
          }
          if (d.x > maxX) {
            maxX = d.x;
          }
          if (d.y < minY) {
            minY = d.y;
          }
          if (d.y > maxY) {
            maxY = d.y;
          }
       }
       double ancho = maxX - minX; double alto = maxY - minY;
       
       if (alto > ancho * 1.2) {
          tendencia = "Dispersión VERTICAL\nRevisa respiración o apoyo del brazo.";
       } else if (ancho > alto * 1.2) {
          tendencia = "Dispersión HORIZONTAL\nRevisa el dedo en el gatillo o la postura.";
       }
    } else if (validos.isEmpty) {
      tendencia = "Sin impactos válidos";
    }

    double sumPuntosPotenciales = 0; double sumRadio = 0;
    int valorMinimo = res.first['valor_minimo'] as int;
    bool esEstiloDuelo = (res.first['anillo_negro_inicio'] as int) <= 5;

    for (var d in validos) {
      double distAlMPI = sqrt(pow(d.x - mpiX, 2) + pow(d.y - mpiY, 2));
      sumRadio += distAlMPI;
      double distCentrada = distAlMPI; int puntosVirtuales = 0;
      if (distCentrada <= 1.0) {
          if (esEstiloDuelo) {
             double calculo = 11 - (distCentrada * 6);
             puntosVirtuales = calculo.floor();
             if (puntosVirtuales < 5) {
               puntosVirtuales = 0;
             }
             if (puntosVirtuales > 10) {
               puntosVirtuales = 10;
             }
          } else {
             int totalZonas = 11 - valorMinimo;
             double calculo = 11 - (distCentrada * totalZonas);
             puntosVirtuales = calculo.floor();
             if (puntosVirtuales < valorMinimo) {
               puntosVirtuales = 0;
             }
             if (puntosVirtuales > 10) {
               puntosVirtuales = 10;
             }
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
      consejoTendencia: tendencia, 
    );
  }

  Future<List<DiagnosticoTecnico>> calcularDiagnosticoTecnico({DateTimeRange? rangoFechas, int? idEquipo, int? idTipoDiana, int? idMunicion, int? filtroModo, List<int>? idsSesiones, bool esZurdo = false, bool generarEtiquetas = false}) async {
    final db = await dbProvider.database; List<dynamic> args = [];
    String whereClause = _construirWhere(args, rangoFechas: rangoFechas, idEquipo: idEquipo, idTipoDiana: idTipoDiana, idMunicion: idMunicion, filtroModo: filtroModo, idsSesiones: idsSesiones);
    final res = await db.rawQuery('''
      SELECT d.*, s.nota 
      FROM Disparos d
      JOIN Sesiones s ON d.id_sesion = s.id
      JOIN PlantillasTiempos p ON s.id_plantilla_tiempos = p.id
      WHERE $whereClause AND d.puntuacion < 9.5 
      LIMIT 1000
    ''', args);

    Map<String, List<DetalleError>> mapaErrores = { "Gatillazo (Dedazo)": [], "Muñeca floja (Breaking)": [], "Apretar Empuñadura": [], "Empujar (Anticipación)": [] };

    for (var row in res) {
      Disparo d = Disparo.fromMap(row);
      String notaSesion = row['nota'] as String? ?? "";
      String etiqueta = "#${d.numero}";
      if (generarEtiquetas) {
          if (notaSesion.contains("Serie")) {
             final regex = RegExp(r'Serie (\d+)');
             final match = regex.firstMatch(notaSesion);
             if (match != null) etiqueta = "S${match.group(1)}-${d.numero}";
          }
      }
      double angleRad = atan2(d.y, d.x); double angleDeg = angleRad * 180 / pi; 
      bool izquierda = (angleDeg > 90 || angleDeg < -90); bool derecha = (angleDeg < 90 && angleDeg > -90);   
      bool abajo = (angleDeg > 0); bool arriba = (angleDeg < 0); 
      if (esZurdo) { bool temp = izquierda; izquierda = derecha; derecha = temp; }
      String errorKey = "";
      if (abajo && izquierda) {
        errorKey = "Gatillazo (Dedazo)";
      } else if (arriba && derecha) {
        errorKey = "Empujar (Anticipación)";
      } else if (abajo && derecha) {
        errorKey = "Apretar Empuñadura";
      } else if (arriba && izquierda) {
        errorKey = "Muñeca floja (Breaking)";
      }
      if (errorKey.isNotEmpty && mapaErrores.containsKey(errorKey)) { mapaErrores[errorKey]!.add(DetalleError(etiqueta, d.puntuacion)); }
    }

    List<DiagnosticoTecnico> resultado = [];
    int totalFallos = res.length;
    if (totalFallos == 0) return [];

    mapaErrores.forEach((nombre, listaDetalles) {
      if (listaDetalles.isNotEmpty) {
        double porcentaje = (listaDetalles.length / totalFallos) * 100;
        listaDetalles.sort((a,b) => a.etiqueta.compareTo(b.etiqueta));
        resultado.add(DiagnosticoTecnico(nombreError: nombre, cantidad: listaDetalles.length, porcentaje: porcentaje, detalles: listaDetalles));
      }
    });
    resultado.sort((a, b) => b.cantidad.compareTo(a.cantidad)); 
    return resultado;
  }

  Future<List<ResumenMunicionStats>> obtenerResumenMunicion({
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? filtroModo,
    List<int>? idsSesiones,
  }) async {
    final db = await dbProvider.database;
    List<dynamic> args = [];
    String whereClause = _construirWhere(
      args,
      rangoFechas: rangoFechas,
      idEquipo: idEquipo,
      idTipoDiana: null,
      idMunicion: null,
      filtroModo: filtroModo,
      idsSesiones: idsSesiones,
    );
    final res = await db.rawQuery('''
      SELECT
        m.id as id_municion,
        m.marca,
        m.lote,
        COUNT(DISTINCT s.id) as sesiones,
        COUNT(d.id) as disparos,
        COALESCE(AVG(d.puntuacion), 0) as media,
        COALESCE(SUM(d.puntuacion), 0) as total_puntos
      FROM Sesiones s
      LEFT JOIN Municion m ON s.id_municion = m.id
      LEFT JOIN Disparos d ON d.id_sesion = s.id
      JOIN PlantillasTiempos p ON s.id_plantilla_tiempos = p.id
      WHERE $whereClause
      GROUP BY s.id_municion
      ORDER BY media DESC, disparos DESC
    ''', args);
    return res.map((e) => ResumenMunicionStats.fromMap(e)).toList();
  }

  Future<List<ComparativoLotesContexto>> obtenerComparativoLotes({
    DateTimeRange? rangoFechas,
    int? idEquipo,
    int? idMunicion,
    int? filtroModo,
    List<int>? idsSesiones,
  }) async {
    final db = await dbProvider.database;
    List<dynamic> args = [];
    String whereClause = _construirWhere(
      args,
      rangoFechas: rangoFechas,
      idEquipo: idEquipo,
      idTipoDiana: null,
      idMunicion: idMunicion,
      filtroModo: filtroModo,
      idsSesiones: idsSesiones,
    );

    final rows = await db.rawQuery('''
      SELECT
        COALESCE(mod.nombre, p.nombre_disciplina, 'Entrenamiento') as modalidad,
        s.id_municion,
        COALESCE(m.marca, 'Sin munición') as marca,
        COALESCE(m.lote, '-') as lote,
        s.temperatura_c,
        s.viento_ms,
        d.puntuacion
      FROM Sesiones s
      LEFT JOIN Modalidades mod ON s.id_modalidad = mod.id
      LEFT JOIN PlantillasTiempos p ON s.id_plantilla_tiempos = p.id
      LEFT JOIN Municion m ON s.id_municion = m.id
      LEFT JOIN Disparos d ON d.id_sesion = s.id
      WHERE $whereClause
    ''', args);

    final Map<String, _AcumLote> lotesPorContexto = {};
    for (final row in rows) {
      final modalidad = (row['modalidad'] as String?) ?? 'Entrenamiento';
      final temp = (row['temperatura_c'] as num?)?.toDouble();
      final viento = (row['viento_ms'] as num?)?.toDouble();
      final tempR = _rangoTemperatura(temp);
      final vientoR = _rangoViento(viento);
      final idMun = row['id_municion'] as int?;
      final marca = (row['marca'] as String?) ?? 'Sin munición';
      final lote = (row['lote'] as String?) ?? '-';
      final puntuacion = (row['puntuacion'] as num?)?.toDouble() ?? 0;

      final key = '$modalidad|$tempR|$vientoR|${idMun ?? -1}';
      final actual = lotesPorContexto[key];
      if (actual == null) {
        lotesPorContexto[key] = _AcumLote(
          modalidad: modalidad,
          rangoTemperatura: tempR,
          rangoViento: vientoR,
          idMunicion: idMun,
          marca: marca,
          lote: lote,
          disparos: 1,
          sumaPuntos: puntuacion,
        );
      } else {
        actual.disparos += 1;
        actual.sumaPuntos += puntuacion;
      }
    }

    final Map<String, List<_AcumLote>> grupos = {};
    for (final v in lotesPorContexto.values) {
      final groupKey = '${v.modalidad}|${v.rangoTemperatura}|${v.rangoViento}';
      grupos.putIfAbsent(groupKey, () => []).add(v);
    }

    final List<ComparativoLotesContexto> out = [];
    for (final entry in grupos.entries) {
      final lotes = entry.value.where((e) => e.disparos > 0).toList();
      if (lotes.length < 2) continue; // comparativo real requiere >=2 lotes
      lotes.sort((a, b) => b.media.compareTo(a.media));
      final best = lotes.first;
      final worst = lotes.last;
      out.add(
        ComparativoLotesContexto(
          modalidad: best.modalidad,
          rangoTemperatura: best.rangoTemperatura,
          rangoViento: best.rangoViento,
          mejor: LotePerformance(
            idMunicion: best.idMunicion,
            marca: best.marca,
            lote: best.lote,
            disparos: best.disparos,
            media: best.media,
          ),
          peor: LotePerformance(
            idMunicion: worst.idMunicion,
            marca: worst.marca,
            lote: worst.lote,
            disparos: worst.disparos,
            media: worst.media,
          ),
          diferencia: best.media - worst.media,
        ),
      );
    }

    out.sort((a, b) {
      final c = a.modalidad.compareTo(b.modalidad);
      if (c != 0) return c;
      return b.diferencia.compareTo(a.diferencia);
    });
    return out;
  }

  String _rangoTemperatura(double? t) {
    if (t == null) return 'Sin dato';
    if (t < 10) return '<10°C';
    if (t < 20) return '10-19°C';
    if (t < 30) return '20-29°C';
    return '>=30°C';
  }

  String _rangoViento(double? v) {
    if (v == null) return 'Sin dato';
    if (v < 0.5) return 'Calma';
    if (v < 2) return '0.5-1.9 m/s';
    if (v < 4) return '2.0-3.9 m/s';
    return '>=4.0 m/s';
  }
}

class AnalisisAgrupacion {
  final List<Disparo> disparosValidos;
  final List<Disparo> disparosDescartados;
  final Point<double> mpi;
  final double puntuacionRealMedia;
  final double puntuacionPotencialMedia;
  final double radioDisperson;
  final String consejoTendencia;

  AnalisisAgrupacion({
    required this.disparosValidos,
    required this.disparosDescartados,
    required this.mpi,
    required this.puntuacionRealMedia,
    required this.puntuacionPotencialMedia,
    required this.radioDisperson,
    this.consejoTendencia = "",
  });
}

class DiagnosticoTecnico {
  final String nombreError;
  final int cantidad;
  final double porcentaje;
  final List<DetalleError> detalles;
  DiagnosticoTecnico({required this.nombreError, required this.cantidad, required this.porcentaje, this.detalles = const []});
}

class ResumenMunicionStats {
  final int? idMunicion;
  final String marca;
  final String lote;
  final int sesiones;
  final int disparos;
  final double media;
  final double totalPuntos;

  ResumenMunicionStats({
    required this.idMunicion,
    required this.marca,
    required this.lote,
    required this.sesiones,
    required this.disparos,
    required this.media,
    required this.totalPuntos,
  });

  factory ResumenMunicionStats.fromMap(Map<String, dynamic> map) {
    return ResumenMunicionStats(
      idMunicion: map['id_municion'],
      marca: map['marca'] ?? 'Sin munición',
      lote: map['lote'] ?? '-',
      sesiones: (map['sesiones'] as num?)?.toInt() ?? 0,
      disparos: (map['disparos'] as num?)?.toInt() ?? 0,
      media: (map['media'] as num?)?.toDouble() ?? 0,
      totalPuntos: (map['total_puntos'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ComparativoLotesContexto {
  final String modalidad;
  final String rangoTemperatura;
  final String rangoViento;
  final LotePerformance mejor;
  final LotePerformance peor;
  final double diferencia;

  ComparativoLotesContexto({
    required this.modalidad,
    required this.rangoTemperatura,
    required this.rangoViento,
    required this.mejor,
    required this.peor,
    required this.diferencia,
  });
}

class LotePerformance {
  final int? idMunicion;
  final String marca;
  final String lote;
  final int disparos;
  final double media;

  LotePerformance({
    required this.idMunicion,
    required this.marca,
    required this.lote,
    required this.disparos,
    required this.media,
  });
}

class _AcumLote {
  final String modalidad;
  final String rangoTemperatura;
  final String rangoViento;
  final int? idMunicion;
  final String marca;
  final String lote;
  int disparos;
  double sumaPuntos;

  _AcumLote({
    required this.modalidad,
    required this.rangoTemperatura,
    required this.rangoViento,
    required this.idMunicion,
    required this.marca,
    required this.lote,
    required this.disparos,
    required this.sumaPuntos,
  });

  double get media => disparos <= 0 ? 0 : (sumaPuntos / disparos);
}