import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../database/database_provider.dart';

class DataSeederService {
  final dbProvider = DatabaseProvider.instance;
  final Random _rng = Random();
  
  // Etiqueta para identificar datos falsos
  static const String _tagPrueba = "[PRUEBA]"; 

  Future<void> generarDatosPrueba() async {
    final db = await dbProvider.database;

    // 1. OBTENER RECURSOS EXISTENTES
    var resEquipos = await db.query('Equipos');
    if (resEquipos.isEmpty) {
        await db.insert('Equipos', {'nombre': 'Arma de Prueba', 'id_tipo_arma': 1, 'id_calibre': 1});
        resEquipos = await db.query('Equipos');
    }
    List<int> idsEquipos = resEquipos.map((e) => e['id'] as int).toList();

    var resPlantillas = await db.query('PlantillasTiempos');
    List<int> idsPlantillas = resPlantillas.map((e) => e['id'] as int).toList();
    if (idsPlantillas.isEmpty) return;

    var resModalidades = await db.query('Modalidades');
    List<int> idsMuniciones = await _asegurarMunicionPrueba(db);
    
    // --- A. GENERAR 50 ENTRENAMIENTOS SUELTOS (Antes eran 10) ---
    print("Generando entrenamientos...");
    for (int i = 0; i < 50; i++) { 
        DateTime fecha = DateTime.now().subtract(Duration(days: _rng.nextInt(180))); // Últimos 6 meses
        int idEquipo = idsEquipos[_rng.nextInt(idsEquipos.length)];
        int idPlantilla = idsPlantillas[_rng.nextInt(idsPlantillas.length)];
        int? idMunicion = idsMuniciones.isEmpty ? null : idsMuniciones[_rng.nextInt(idsMuniciones.length)];
        
        await _crearSesionFalsa(
          db,
          fecha,
          idEquipo,
          idPlantilla,
          null,
          "Entrenamiento Simulado #$i $_tagPrueba",
          idMunicion: idMunicion,
        );
    }

    // --- B. GENERAR COMPETICIONES (HISTORIAL MÚLTIPLE) ---
    print("Generando competiciones...");
    for (var modMap in resModalidades) {
        // ¡CAMBIO AQUÍ! Generamos 5 ediciones distintas de cada torneo
        for (int i = 0; i < 5; i++) {
            // Fechas aleatorias en el pasado (evitando solaparse mucho)
            DateTime fechaTorneo = DateTime.now().subtract(Duration(days: _rng.nextInt(150) + (i * 10)));
            
            int idModalidad = modMap['id'] as int;
            int idEquipo = idsEquipos[_rng.nextInt(idsEquipos.length)];
            int? idMunicion = idsMuniciones.isEmpty ? null : idsMuniciones[_rng.nextInt(idsMuniciones.length)];

            var fases = await db.query('FasesModalidad', where: 'id_modalidad = ?', whereArgs: [idModalidad], orderBy: 'orden');
            
            for (var faseMap in fases) {
                int idPlantilla = faseMap['id_plantilla_tiempos'] as int;
                int repeticiones = faseMap['repeticiones'] as int;
                String descFase = faseMap['descripcion_fase'] as String;
                
                for (int r = 0; r < repeticiones; r++) {
                    DateTime fechaFase = fechaTorneo.add(Duration(minutes: 15 * (faseMap['orden'] as int) + (r * 5)));
                    
                    await _crearSesionFalsa(
                        db, 
                        fechaFase, 
                        idEquipo, 
                        idPlantilla, 
                        idModalidad, 
                        "Torneo: ${modMap['nombre']} | $descFase | Serie ${r+1} $_tagPrueba",
                        idMunicion: idMunicion,
                    );
                }
            }
        }
    }
  }

  Future<void> _crearSesionFalsa(
    Database db,
    DateTime fecha,
    int idEquipo,
    int idPlantilla,
    int? idModalidad,
    String nota, {
    int? idMunicion,
  }) async {
      final interior = _rng.nextBool();
      final distancia = [10, 25, 50][_rng.nextInt(3)];
      final viento = interior ? 0.0 : (_rng.nextDouble() * 4.5);
      final hum = 35 + _rng.nextInt(50);
      final temp = 12 + _rng.nextDouble() * 18;
      int idSesion = await db.insert('Sesiones', {
          'fecha': fecha.toIso8601String(),
          'id_equipo': idEquipo,
          'id_plantilla_tiempos': idPlantilla,
          'id_modalidad': idModalidad,
          'id_municion': idMunicion,
          'nota': nota,
          'lugar': interior ? 'Galería Club $_tagPrueba' : 'Campo Exterior $_tagPrueba',
          'distancia_m': distancia,
          'posicion_tiro': ['Pie', 'Rodilla', 'Banco'][_rng.nextInt(3)],
          'es_interior': interior ? 1 : 0,
          'temperatura_c': temp,
          'humedad_pct': hum.toDouble(),
          'presion_hpa': (1000 + _rng.nextInt(25)).toDouble(),
          'viento_ms': viento,
          'viento_direccion': interior ? '' : ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'][_rng.nextInt(8)],
          'iluminacion': interior ? 'Artificial' : 'Natural',
      });

      int disparosGenerados = 0;
      for (int i = 1; i <= 5; i++) {
          double base = 7.0;
          double variacion = _rng.nextDouble() * 4.0; 
          if (_rng.nextBool()) variacion += 1.5; 
          
          double puntos = base + variacion;
          if (puntos > 10.9) puntos = 10.9;
          
          bool esMosca = puntos >= 10.3;
          double dispersion = (11 - puntos) / 10;
          double angle = _rng.nextDouble() * 2 * pi;
          double distance = dispersion * _rng.nextDouble();
          
          await db.insert('Disparos', {
              'id_sesion': idSesion,
              'numero_disparo': i,
              'coordenada_x': cos(angle) * distance,
              'coordenada_y': sin(angle) * distance,
              'puntuacion': puntos,
              'es_mosca': esMosca ? 1 : 0
          });
          disparosGenerados++;
      }

      if (idMunicion != null && disparosGenerados > 0) {
        final res = await db.query('Municion', columns: ['cantidad_actual'], where: 'id = ?', whereArgs: [idMunicion], limit: 1);
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
              'nota': 'Seeder Sesion $idSesion $_tagPrueba',
            });
          }
        }
      }
  }

  Future<List<int>> _asegurarMunicionPrueba(Database db) async {
    final existentes = await db.query(
      'Municion',
      columns: ['id'],
      where: "lote LIKE ? OR marca LIKE ?",
      whereArgs: ['%$_tagPrueba%', '%$_tagPrueba%'],
    );
    if (existentes.isNotEmpty) {
      return existentes.map((e) => e['id'] as int).toList();
    }

    final calibres = await db.query('CatalogoCalibres', columns: ['id']);
    final idCalibreDefault = calibres.isNotEmpty ? calibres.first['id'] as int : null;

    final lotes = [
      {'marca': 'SK Long Range $_tagPrueba', 'lote': 'SK-LR-001 $_tagPrueba', 'stock': 500},
      {'marca': 'ELEY Match $_tagPrueba', 'lote': 'ELY-M-778 $_tagPrueba', 'stock': 750},
      {'marca': 'RWS R50 $_tagPrueba', 'lote': 'RWS-R50-42 $_tagPrueba', 'stock': 600},
    ];

    final ids = <int>[];
    for (final l in lotes) {
      final id = await db.insert('Municion', {
        'marca': l['marca'],
        'lote': l['lote'],
        'id_calibre': idCalibreDefault,
        'cantidad_inicial': l['stock'],
        'cantidad_actual': l['stock'],
        'total_disparada': 0,
      });
      ids.add(id);

      await db.insert('MovimientosMunicion', {
        'id_municion': id,
        'tipo': 'compra',
        'cantidad': l['stock'],
        'fecha': DateTime.now().subtract(Duration(days: _rng.nextInt(120))).toIso8601String(),
        'nota': 'Carga inicial de pruebas $_tagPrueba',
      });
    }

    return ids;
  }
  
  Future<int> borrarSoloDatosPrueba() async {
      final db = await dbProvider.database;
      
      await db.execute('''
        DELETE FROM Disparos 
        WHERE id_sesion IN (SELECT id FROM Sesiones WHERE nota LIKE '%$_tagPrueba%')
      ''');

      int count = await db.delete('Sesiones', where: "nota LIKE '%$_tagPrueba%'");

      await db.execute('''
        DELETE FROM MovimientosMunicion
        WHERE nota LIKE '%$_tagPrueba%'
           OR id_municion IN (SELECT id FROM Municion WHERE lote LIKE '%$_tagPrueba%' OR marca LIKE '%$_tagPrueba%')
      ''');
      await db.execute("DELETE FROM Municion WHERE lote LIKE '%$_tagPrueba%' OR marca LIKE '%$_tagPrueba%'");
      return count;
  }

  Future<void> borrarTodosLosDatos() async {
      final db = await dbProvider.database;
      await db.delete('Disparos');
      await db.delete('Sesiones');
  }
}