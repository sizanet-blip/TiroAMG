import 'package:sqflite/sqflite.dart';
import '../database/database_provider.dart';

// Modelo simple interno
class PerfilUsuario {
  final String nombre;
  final String licencia;
  final String club;
  final String categoria;

  PerfilUsuario({this.nombre = '', this.licencia = '', this.club = '', this.categoria = ''});

  factory PerfilUsuario.fromMap(Map<String, dynamic> map) {
    return PerfilUsuario(
      nombre: map['nombre_tirador'] ?? '',
      licencia: map['numero_licencia'] ?? '',
      club: map['club'] ?? '',
      categoria: map['categoria'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre_tirador': nombre,
      'numero_licencia': licencia,
      'club': club,
      'categoria': categoria,
    };
  }
}

class PerfilService {
  final dbProvider = DatabaseProvider.instance;

  // Obtener el perfil (siempre devuelve el ID 1)
  Future<PerfilUsuario> obtenerPerfil() async {
    final db = await dbProvider.database;
    final res = await db.query('PerfilUsuario', where: 'id = 1');
    if (res.isNotEmpty) {
      return PerfilUsuario.fromMap(res.first);
    }
    // Si por lo que sea no existe, devolvemos uno vacío
    return PerfilUsuario();
  }

  // Guardar/Actualizar perfil
  Future<void> guardarPerfil(PerfilUsuario perfil) async {
    final db = await dbProvider.database;
    // Siempre actualizamos el ID 1
    await db.update('PerfilUsuario', perfil.toMap(), where: 'id = 1');
  }
}