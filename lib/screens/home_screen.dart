import 'package:flutter/material.dart';
// Importamos las pantallas de destino
import 'competicion_screen.dart';
import 'entrenamiento_screen.dart';
import 'historial_screen.dart';
import 'backup_screen.dart'; 
import 'config_screen.dart';
import 'recorte_diana_screen.dart'; 
import 'package:flutter/foundation.dart'; // <--- Agrega esto para usar kDebugMode

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Tiro Deportivo AMG'),
        backgroundColor: Colors.blueGrey,
        centerTitle: true,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // --- LOGO ---
              const Padding(
                padding: EdgeInsets.only(bottom: 40.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.adjust,
                      size: 100,
                      color: Colors.blueGrey,
                    ),
                    SizedBox(height: 15),
                    Text(
                      'Registro de Tiro',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.blueGrey
                      ),
                    ),
                  ],
                ),
              ),

              // --- BOTONES DEL MENÚ ---
              if (kDebugMode) ...[
                // ** NUEVA OPCIÓN DE PRUEBAS (PRIMERA) **
                _buildMenuItem(context, 'Recorte Diana (Pruebas)', Icons.camera_alt, Colors.deepOrange, 
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecorteDianaScreen()))
                ),
              ],
              _buildMenuItem(context, 'Competición', Icons.emoji_events, Colors.amber[700]!, 
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => CompeticionScreen()))
              ),

              _buildMenuItem(context, 'Entrenamiento', Icons.sports_baseball, Colors.teal, 
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntrenamientoScreen()))
              ),

              _buildMenuItem(context, 'Historial y Análisis', Icons.analytics, Colors.indigo, 
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => HistorialScreen()))
              ),

              _buildMenuItem(context, 'Copia de Seguridad', Icons.cloud_sync, Colors.blueGrey, 
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => BackupScreen()))
              ),

              _buildMenuItem(context, 'Configuración', Icons.settings, Colors.grey[700]!, 
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => ConfigScreen()))
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(width: 20),
              Expanded(
                // Aquí quitamos la necesidad de que el título contenga la numeración
                child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}