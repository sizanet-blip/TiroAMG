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
    
    // --- A. GENERAR 50 ENTRENAMIENTOS SUELTOS (Antes eran 10) ---
    print("Generando entrenamientos...");
    for (int i = 0; i < 50; i++) { 
        DateTime fecha = DateTime.now().subtract(Duration(days: _rng.nextInt(180))); // Últimos 6 meses
        int idEquipo = idsEquipos[_rng.nextInt(idsEquipos.length)];
        int idPlantilla = idsPlantillas[_rng.nextInt(idsPlantillas.length)];
        
        await _crearSesionFalsa(db, fecha, idEquipo, idPlantilla, null, "Entrenamiento Simulado #$i $_tagPrueba");
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
                        "Torneo: ${modMap['nombre']} | $descFase | Serie ${r+1} $_tagPrueba"
                    );
                }
            }
        }
    }
  }

  Future<void> _crearSesionFalsa(Database db, DateTime fecha, int idEquipo, int idPlantilla, int? idModalidad, String nota) async {
      int idSesion = await db.insert('Sesiones', {
          'fecha': fecha.toIso8601String(),
          'id_equipo': idEquipo,
          'id_plantilla_tiempos': idPlantilla,
          'id_modalidad': idModalidad,
          'nota': nota
      });

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
      }
  }
  
  Future<int> borrarSoloDatosPrueba() async {
      final db = await dbProvider.database;
      
      await db.execute('''
        DELETE FROM Disparos 
        WHERE id_sesion IN (SELECT id FROM Sesiones WHERE nota LIKE '%$_tagPrueba%')
      ''');

      int count = await db.delete('Sesiones', where: "nota LIKE '%$_tagPrueba%'");
      return count;
  }

  Future<void> borrarTodosLosDatos() async {
      final db = await dbProvider.database;
      await db.delete('Disparos');
      await db.delete('Sesiones');
  }
}