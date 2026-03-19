import 'package:sqflite/sqflite.dart';
import '../database/database_provider.dart';
import '../models/competicion_model.dart';

class CompeticionService {
  final dbProvider = DatabaseProvider.instance;

  // ==========================================
  //           GESTIÓN DE MODALIDADES
  // ==========================================

  // 1. Obtener todas las modalidades (Para la lista de selección)
  Future<List<Modalidad>> obtenerModalidades() async {
    final db = await dbProvider.database;
    final res = await db.query('Modalidades', orderBy: 'nombre ASC');
    return res.map((e) => Modalidad.fromMap(e)).toList();
  }

  // 2. Crear nueva modalidad (Cabecera)
  Future<int> crearModalidad(Modalidad modalidad) async {
    final db = await dbProvider.database;
    return await db.insert('Modalidades', modalidad.toMap());
  }

  // 3. Borrar modalidad (¡OJO! También borra sus fases en cascada)
  Future<void> borrarModalidadCompleta(int idModalidad) async {
    final db = await dbProvider.database;
    // Usamos una transacción para asegurar que se borra todo o nada
    await db.transaction((txn) async {
      // Borrar fases hijas
      await txn.delete('FasesModalidad', where: 'id_modalidad = ?', whereArgs: [idModalidad]);
      // Borrar padre
      await txn.delete('Modalidades', where: 'id = ?', whereArgs: [idModalidad]);
    });
  }

  // ==========================================
  //           GESTIÓN DE FASES
  // ==========================================

  // 4. Obtener las fases de un torneo DETALLADAS (Con JOIN a Plantillas)
  Future<List<FaseDetalle>> obtenerFasesDetalladas(int idModalidad) async {
    final db = await dbProvider.database;
    
    // Consulta SQL avanzada:
    // Seleccionamos TODO de la fase (f.*)
    // Y traemos el nombre y el tipo (es_duelo) de la plantilla de tiempos (p)
    final res = await db.rawQuery('''
      SELECT f.*, 
             p.nombre_disciplina AS nombre_plantilla, 
             p.es_duelo AS es_duelo_plantilla
      FROM FasesModalidad f
      LEFT JOIN PlantillasTiempos p ON f.id_plantilla_tiempos = p.id
      WHERE f.id_modalidad = ?
      ORDER BY f.orden ASC
    ''', [idModalidad]);

    return res.map((row) {
      // Construimos el objeto FaseModalidad base
      final fase = FaseModalidad.fromMap(row);
      
      // Construimos el detalle extra
      return FaseDetalle(
        fase: fase,
        nombrePlantilla: row['nombre_plantilla'] as String? ?? 'Desconocida',
        esDuelo: (row['es_duelo_plantilla'] as int?) == 1,
      );
    }).toList();
  }

  // 5. Añadir una fase nueva a un torneo
  Future<int> agregarFase(FaseModalidad fase) async {
    final db = await dbProvider.database;
    return await db.insert('FasesModalidad', fase.toMap());
  }
  
  // 6. Actualizar una fase
  Future<int> actualizarFase(FaseModalidad fase) async {
    final db = await dbProvider.database;
    return await db.update('FasesModalidad', fase.toMap(), where: 'id = ?', whereArgs: [fase.id]);
  }

  // 7. Borrar una fase
  Future<int> borrarFase(int idFase) async {
    final db = await dbProvider.database;
    return await db.delete('FasesModalidad', where: 'id = ?', whereArgs: [idFase]);
  }
}