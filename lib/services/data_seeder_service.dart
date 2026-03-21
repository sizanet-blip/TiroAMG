import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_provider.dart';

class DataSeederService {
  final dbProvider = DatabaseProvider.instance;
  final Random _rng = Random();

  // Etiqueta para identificar datos falsos
  static const String _tagPrueba = "[PRUEBA]";

  Future<void> generarDatosPrueba() async {
    final db = await dbProvider.database;

    // Si ya hay datos de prueba, los limpiamos antes de regenerar para no duplicar.
    await borrarSoloDatosPrueba();

    await _asegurarPerfilUsuarioPrueba(db);
    final idsEquipos = await _asegurarEquiposPrueba(db);
    final plantillas = await _asegurarPlantillasPrueba(db);
    final resModalidades = await db.query('Modalidades');
    final idsMuniciones = await _asegurarMunicionPrueba(db);

    if (plantillas.isEmpty || idsEquipos.isEmpty) return;

    // --- A. ENTRENAMIENTOS SUELTOS ---
    debugPrint("Generando entrenamientos realistas...");
    for (int i = 0; i < 60; i++) {
      final fecha = DateTime.now().subtract(Duration(days: _rng.nextInt(240)));
      final plantilla = plantillas[_rng.nextInt(plantillas.length)];
      final idEquipo = idsEquipos[_rng.nextInt(idsEquipos.length)];
      final idMunicion = idsMuniciones.isEmpty
          ? null
          : idsMuniciones[_rng.nextInt(idsMuniciones.length)];

      await _crearSesionFalsa(
        db,
        fecha,
        idEquipo,
        plantilla,
        null,
        "Entrenamiento simulado #${i + 1} $_tagPrueba",
        idMunicion: idMunicion,
        nivelRendimiento: _nivelRendimientoAleatorio(),
      );
    }

    // --- B. COMPETICIONES (MULTIPLES EDICIONES) ---
    debugPrint("Generando competiciones realistas...");
    for (final modMap in resModalidades) {
      final idModalidad = (modMap['id'] as num?)?.toInt();
      if (idModalidad == null) continue;
      final nombreModalidad = (modMap['nombre']?.toString() ?? 'Modalidad').trim();

      final fases = await db.query(
        'FasesModalidad',
        where: 'id_modalidad = ?',
        whereArgs: [idModalidad],
        orderBy: 'orden',
      );
      if (fases.isEmpty) continue;

      for (int edicion = 0; edicion < 5; edicion++) {
        final fechaTorneo = DateTime.now().subtract(
          Duration(days: _rng.nextInt(200) + (edicion * 12)),
        );
        final idEquipo = idsEquipos[_rng.nextInt(idsEquipos.length)];
        final idMunicion = idsMuniciones.isEmpty
            ? null
            : idsMuniciones[_rng.nextInt(idsMuniciones.length)];
        final nivel = _nivelRendimientoAleatorio();

        for (final faseMap in fases) {
          final idPlantillaFase = (faseMap['id_plantilla_tiempos'] as num?)?.toInt();
          if (idPlantillaFase == null) continue;
          final plantilla = plantillas.where((p) => p['id'] == idPlantillaFase).firstWhere(
                (_) => true,
                orElse: () => plantillas.first,
              );

          final repeticiones = ((faseMap['repeticiones'] as num?)?.toInt() ?? 1).clamp(1, 8);
          final orden = (faseMap['orden'] as num?)?.toInt() ?? 1;
          final esEnsayo = (faseMap['es_ensayo'] as num?)?.toInt() == 1;
          final descFase = (faseMap['descripcion_fase']?.toString() ?? 'Fase').trim();

          for (int r = 0; r < repeticiones; r++) {
            final fechaFase = fechaTorneo.add(
              Duration(minutes: 12 * orden + (r * 4)),
            );
            final prefijo = esEnsayo ? 'Ensayo' : 'Serie';

            await _crearSesionFalsa(
              db,
              fechaFase,
              idEquipo,
              plantilla,
              idModalidad,
              "Torneo: $nombreModalidad | $descFase | $prefijo ${r + 1} $_tagPrueba",
              idMunicion: idMunicion,
              nivelRendimiento: nivel,
            );
          }
        }
      }
    }

    await _insertarAjustesMunicionPrueba(db, idsMuniciones);
  }

  Future<void> _crearSesionFalsa(
    Database db,
    DateTime fecha,
    int idEquipo,
    Map<String, dynamic> plantilla,
    int? idModalidad,
    String nota, {
    int? idMunicion,
    required double nivelRendimiento,
  }) async {
    final interior = _rng.nextBool();
    final distancia = [10, 25, 50][_rng.nextInt(3)];
    final viento = interior ? 0.0 : (_rng.nextDouble() * 6.0);
    final hum = 30 + _rng.nextInt(61); // 30-90
    final temp = interior
        ? (18 + _rng.nextDouble() * 10) // 18-28
        : (5 + _rng.nextDouble() * 32); // 5-37
    final idPlantilla = (plantilla['id'] as num?)?.toInt() ?? 1;
    final disparosPorSerie =
        ((plantilla['disparos_por_serie'] as num?)?.toInt() ?? 5).clamp(1, 20);
    final seriesPorSesion =
        ((plantilla['series_por_sesion'] as num?)?.toInt() ?? 1).clamp(1, 10);
    final disparosTotales = (disparosPorSerie * seriesPorSesion).clamp(3, 120);

    final idSesion = await db.insert('Sesiones', {
      'fecha': fecha.toIso8601String(),
      'id_equipo': idEquipo,
      'id_plantilla_tiempos': idPlantilla,
      'id_modalidad': idModalidad,
      'id_municion': idMunicion,
      'nota': nota,
      'lugar': interior
          ? 'Galeria cubierta $_tagPrueba'
          : 'Campo exterior $_tagPrueba',
      'distancia_m': distancia,
      'posicion_tiro': ['Pie', 'Rodilla', 'Banco'][_rng.nextInt(3)],
      'es_interior': interior ? 1 : 0,
      'temperatura_c': temp,
      'humedad_pct': hum.toDouble(),
      'presion_hpa': (995 + _rng.nextInt(36)).toDouble(),
      'viento_ms': viento,
      'viento_direccion':
          interior ? '' : ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'][_rng.nextInt(8)],
      'iluminacion': interior
          ? ['Artificial', 'LED blanca', 'LED calida'][_rng.nextInt(3)]
          : ['Natural', 'Natural nublada', 'Natural intensa'][_rng.nextInt(3)],
    });

    var disparosGenerados = 0;
    for (int i = 1; i <= disparosTotales; i++) {
      final impacto = _generarImpactoRealista(
        numero: i,
        nivelRendimiento: nivelRendimiento,
      );

      await db.insert('Disparos', {
        'id_sesion': idSesion,
        'numero_disparo': impacto['numero_disparo'],
        'coordenada_x': impacto['coordenada_x'],
        'coordenada_y': impacto['coordenada_y'],
        'puntuacion': impacto['puntuacion'],
        'es_mosca': impacto['es_mosca'],
        'es_fuera': impacto['es_fuera'],
      });
      disparosGenerados++;
    }

    if (idMunicion != null && disparosGenerados > 0) {
      final res = await db.query(
        'Municion',
        columns: ['cantidad_actual'],
        where: 'id = ?',
        whereArgs: [idMunicion],
        limit: 1,
      );
      if (res.isNotEmpty) {
        final actual = (res.first['cantidad_actual'] as num?)?.toInt() ?? 0;
        final usoReal = disparosGenerados > actual ? actual : disparosGenerados;
        if (usoReal > 0) {
          await db.rawUpdate('''
            UPDATE Municion
            SET
              cantidad_actual = cantidad_actual - ?,
              total_disparada = total_disparada + ?
            WHERE id = ?
          ''', [usoReal, usoReal, idMunicion]);

          await db.insert('MovimientosMunicion', {
            'id_municion': idMunicion,
            'tipo': 'uso',
            'cantidad': usoReal,
            'fecha': fecha.toIso8601String(),
            'nota': 'Seeder sesion $idSesion $_tagPrueba',
          });
        }
      }
    }
  }

  Future<void> _asegurarPerfilUsuarioPrueba(Database db) async {
    final existente = await db.query(
      'PerfilUsuario',
      where: 'nombre_tirador LIKE ? OR club LIKE ?',
      whereArgs: ['%$_tagPrueba%', '%$_tagPrueba%'],
      limit: 1,
    );
    if (existente.isNotEmpty) return;

    await db.insert('PerfilUsuario', {
      'nombre_tirador': 'Tirador Demo $_tagPrueba',
      'numero_licencia': 'DEMO-2026-001',
      'club': 'Club AMG Demo $_tagPrueba',
      'categoria': 'Senior',
    });
  }

  Future<List<int>> _asegurarEquiposPrueba(Database db) async {
    final existentes = await db.query(
      'Equipos',
      columns: ['id'],
      where: 'nombre LIKE ? OR marca LIKE ? OR modelo LIKE ?',
      whereArgs: ['%$_tagPrueba%', '%$_tagPrueba%', '%$_tagPrueba%'],
    );
    if (existentes.isNotEmpty) {
      return existentes.map((e) => (e['id'] as num).toInt()).toList();
    }

    final tipos = await db.query('CatalogoTiposArma', columns: ['id'], limit: 1);
    final calibres = await db.query('CatalogoCalibres', columns: ['id'], limit: 1);
    final idTipo = tipos.isNotEmpty ? (tipos.first['id'] as num).toInt() : null;
    final idCalibre =
        calibres.isNotEmpty ? (calibres.first['id'] as num).toInt() : null;

    final equipos = [
      {
        'nombre': 'Pardini SP $_tagPrueba',
        'marca': 'Pardini $_tagPrueba',
        'modelo': 'SP RF',
        'correccion_click_mm': 2.5,
      },
      {
        'nombre': 'Walther GSP $_tagPrueba',
        'marca': 'Walther $_tagPrueba',
        'modelo': 'GSP500',
        'correccion_click_mm': 2.0,
      },
      {
        'nombre': 'CZ TS2 $_tagPrueba',
        'marca': 'CZ $_tagPrueba',
        'modelo': 'TS2',
        'correccion_click_mm': 2.8,
      },
    ];

    final ids = <int>[];
    for (final e in equipos) {
      final id = await db.insert('Equipos', {
        'nombre': e['nombre'],
        'id_tipo_arma': idTipo,
        'id_calibre': idCalibre,
        'marca': e['marca'],
        'modelo': e['modelo'],
        'correccion_click_mm': e['correccion_click_mm'],
      });
      ids.add(id);
    }
    return ids;
  }

  Future<List<Map<String, dynamic>>> _asegurarPlantillasPrueba(Database db) async {
    var plantillas = await db.query('PlantillasTiempos');
    if (plantillas.isNotEmpty) {
      return plantillas.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    final dianas = await db.query('CatalogoDianas', columns: ['id'], limit: 1);
    final idDiana = dianas.isNotEmpty ? (dianas.first['id'] as num).toInt() : null;

    final defaults = [
      {
        'nombre_disciplina': 'Precision demo $_tagPrueba',
        'disparos_por_serie': 5,
        'series_por_sesion': 6,
        'puntuacion_decimal': 1,
        'tiempo_preparacion': 180,
        'es_duelo': 0,
        'tiempo_exposicion': 0,
        'tiempo_ocultacion': 0,
        'id_tipo_diana': idDiana,
      },
      {
        'nombre_disciplina': 'Duelo demo $_tagPrueba',
        'disparos_por_serie': 5,
        'series_por_sesion': 4,
        'puntuacion_decimal': 0,
        'tiempo_preparacion': 120,
        'es_duelo': 1,
        'tiempo_exposicion': 3,
        'tiempo_ocultacion': 7,
        'id_tipo_diana': idDiana,
      },
    ];

    for (final p in defaults) {
      await db.insert('PlantillasTiempos', p);
    }
    plantillas = await db.query('PlantillasTiempos');
    return plantillas.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<int>> _asegurarMunicionPrueba(Database db) async {
    final existentes = await db.query(
      'Municion',
      columns: ['id'],
      where: "lote LIKE ? OR marca LIKE ?",
      whereArgs: ['%$_tagPrueba%', '%$_tagPrueba%'],
    );
    if (existentes.isNotEmpty) {
      return existentes.map((e) => (e['id'] as num).toInt()).toList();
    }

    final idCalibre22 = await _asegurarCalibre(db, [
      '22',
      '22 lr',
      '.22',
      '.22 lr',
    ], '22 LR');
    final idCalibre9mm = await _asegurarCalibre(db, [
      '9mm',
      '9 mm',
      '9x19',
      '9 para',
    ], '9mm');
    final idCalibre38 = await _asegurarCalibre(db, [
      '38',
      '.38',
      '38 special',
      '.38 special',
      '38 spl',
    ], '38 Special');

    final lotes = [
      {
        'marca': 'SK Long Range $_tagPrueba',
        'lote': 'SK-LR-001 $_tagPrueba',
        'stock': 500,
        'id_calibre': idCalibre22,
      },
      {
        'marca': 'ELEY Match $_tagPrueba',
        'lote': 'ELY-M-778 $_tagPrueba',
        'stock': 750,
        'id_calibre': idCalibre22,
      },
      {
        'marca': 'RWS R50 $_tagPrueba',
        'lote': 'RWS-R50-42 $_tagPrueba',
        'stock': 600,
        'id_calibre': idCalibre22,
      },
      {
        'marca': 'Lapua X-Act $_tagPrueba',
        'lote': 'LAP-XA-221 $_tagPrueba',
        'stock': 400,
        'id_calibre': idCalibre22,
      },
      {
        'marca': 'Fiocchi FMJ $_tagPrueba',
        'lote': 'FCH-9MM-11 $_tagPrueba',
        'stock': 450,
        'id_calibre': idCalibre9mm,
      },
      {
        'marca': 'Geco 9mm $_tagPrueba',
        'lote': 'GCO-9MM-02 $_tagPrueba',
        'stock': 350,
        'id_calibre': idCalibre9mm,
      },
      {
        'marca': 'Sellier&Bellot .38 $_tagPrueba',
        'lote': 'SB-38SP-07 $_tagPrueba',
        'stock': 300,
        'id_calibre': idCalibre38,
      },
      {
        'marca': 'Magtech .38 $_tagPrueba',
        'lote': 'MGT-38SP-03 $_tagPrueba',
        'stock': 280,
        'id_calibre': idCalibre38,
      },
    ];

    final ids = <int>[];
    for (final l in lotes) {
      final id = await db.insert('Municion', {
        'marca': l['marca'],
        'lote': l['lote'],
        'id_calibre': l['id_calibre'],
        'cantidad_inicial': l['stock'],
        'cantidad_actual': l['stock'],
        'total_disparada': 0,
      });
      ids.add(id);

      await db.insert('MovimientosMunicion', {
        'id_municion': id,
        'tipo': 'compra',
        'cantidad': l['stock'],
        'fecha': DateTime.now()
            .subtract(Duration(days: _rng.nextInt(120)))
            .toIso8601String(),
        'nota': 'Carga inicial de pruebas $_tagPrueba',
      });
    }

    return ids;
  }

  Future<int?> _asegurarCalibre(
    Database db,
    List<String> aliases,
    String nombreCreacion,
  ) async {
    final rows = await db.query('CatalogoCalibres', columns: ['id', 'nombre']);
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt();
      final nombre = (row['nombre']?.toString() ?? '').trim().toLowerCase();
      if (id == null || nombre.isEmpty) continue;
      for (final alias in aliases) {
        final a = alias.trim().toLowerCase();
        if (a.isEmpty) continue;
        if (nombre == a || nombre.contains(a)) {
          return id;
        }
      }
    }

    final nuevoId = await db.insert('CatalogoCalibres', {'nombre': nombreCreacion});
    return nuevoId;
  }

  Future<void> _insertarAjustesMunicionPrueba(
    Database db,
    List<int> idsMuniciones,
  ) async {
    if (idsMuniciones.isEmpty) return;
    final now = DateTime.now();
    for (final id in idsMuniciones) {
      if (_rng.nextDouble() < 0.45) {
        final cantidad = 20 + _rng.nextInt(80);
        await db.rawUpdate('''
          UPDATE Municion
          SET
            cantidad_inicial = cantidad_inicial + ?,
            cantidad_actual = cantidad_actual + ?
          WHERE id = ?
        ''', [cantidad, cantidad, id]);
        await db.insert('MovimientosMunicion', {
          'id_municion': id,
          'tipo': 'ajuste',
          'cantidad': cantidad,
          'fecha': now
              .subtract(Duration(days: _rng.nextInt(90)))
              .toIso8601String(),
          'nota': 'Ajuste inventario $_tagPrueba',
        });
      }
    }
  }

  double _nivelRendimientoAleatorio() {
    final r = _rng.nextDouble();
    if (r < 0.20) return 0.25 + _rng.nextDouble() * 0.20; // principiante
    if (r < 0.75) return 0.45 + _rng.nextDouble() * 0.25; // medio
    return 0.70 + _rng.nextDouble() * 0.25; // alto
  }

  Map<String, dynamic> _generarImpactoRealista({
    required int numero,
    required double nivelRendimiento,
  }) {
    final nivel = nivelRendimiento.clamp(0.0, 1.0);
    final pFuera = _interp(0.22, 0.05, nivel);
    final pMalo = _interp(0.36, 0.16, nivel);
    final pBueno = _interp(0.16, 0.44, nivel);
    final r = _rng.nextDouble();

    double radio;
    if (r < pFuera) {
      radio = 1.02 + _rng.nextDouble() * 0.43; // fuera de diana
    } else if (r < pFuera + pMalo) {
      radio = 0.70 + _rng.nextDouble() * 0.29; // malo
    } else if (r < pFuera + pMalo + pBueno) {
      radio = 0.10 + _rng.nextDouble() * 0.28; // bueno
    } else {
      radio = 0.35 + _rng.nextDouble() * 0.34; // medio
    }

    final angle = _rng.nextDouble() * 2 * pi;
    final x = cos(angle) * radio;
    final y = sin(angle) * radio;

    final puntosRaw = radio > 1.0 ? 0.0 : (10.9 - (radio * 10.9));
    final puntos = double.parse(puntosRaw.clamp(0.0, 10.9).toStringAsFixed(1));
    final esMosca = puntos >= 10.3;

    final fuera = radio > 1.0;
    return {
      'numero_disparo': numero,
      'coordenada_x': x,
      'coordenada_y': y,
      'puntuacion': puntos,
      'es_mosca': esMosca ? 1 : 0,
      'es_fuera': fuera ? 1 : 0,
    };
  }

  double _interp(double a, double b, double t) => a + (b - a) * t;

  Future<int> borrarSoloDatosPrueba() async {
    final db = await dbProvider.database;

    await db.execute('''
      DELETE FROM Disparos 
      WHERE id_sesion IN (SELECT id FROM Sesiones WHERE nota LIKE '%$_tagPrueba%')
    ''');

    final count = await db.delete('Sesiones', where: "nota LIKE '%$_tagPrueba%'");

    await db.execute('''
      DELETE FROM MovimientosMunicion
      WHERE nota LIKE '%$_tagPrueba%'
         OR id_municion IN (SELECT id FROM Municion WHERE lote LIKE '%$_tagPrueba%' OR marca LIKE '%$_tagPrueba%')
    ''');
    await db.execute(
      "DELETE FROM Municion WHERE lote LIKE '%$_tagPrueba%' OR marca LIKE '%$_tagPrueba%'",
    );
    await db.execute(
      "DELETE FROM Equipos WHERE nombre LIKE '%$_tagPrueba%' OR marca LIKE '%$_tagPrueba%' OR modelo LIKE '%$_tagPrueba%'",
    );
    await db.execute(
      "DELETE FROM PerfilUsuario WHERE nombre_tirador LIKE '%$_tagPrueba%' OR club LIKE '%$_tagPrueba%'",
    );
    return count;
  }

  Future<void> borrarTodosLosDatos() async {
    final db = await dbProvider.database;
    await db.delete('Disparos');
    await db.delete('Sesiones');
  }
}
