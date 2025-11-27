import 'package:flutter/material.dart';
import 'competicion_screen.dart';
import 'entrenamiento_screen.dart';
import 'historial_screen.dart';
import 'backup_screen.dart';
import 'config_screen.dart';

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
              // --- SECCIÓN LOGO (IMAGEN PERSONALIZADA) ---
              Padding(
                padding: const EdgeInsets.only(bottom: 40.0),
                child: Column(
                  children: [
                    // CAMBIO: Usamos Image.asset en lugar de Icon
                    Container(
                      height: 120, // Altura del logo
                      width: 120,  // Anchura del logo
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      // Asegúrate de tener 'assets/logo.png' en tu proyecto
                      child: Image.asset(
                        'assets/logo.png', 
                        fit: BoxFit.contain, // Ajusta la imagen sin recortarla
                        errorBuilder: (context, error, stackTrace) {
                          // Si falla la carga (olvidaste el paso 2), muestra esto:
                          return const Icon(Icons.broken_image, size: 50, color: Colors.red);
                        },
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text(
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
              _buildMenuItem(context, '1. Competición', Icons.emoji_events, Colors.amber[700]!, 
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompeticionScreen()))
              ),

              _buildMenuItem(context, '2. Entrenamientos', Icons.sports_baseball, Colors.teal, 
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EntrenamientoScreen()))
              ),

              _buildMenuItem(context, '3. Listado (Historial)', Icons.list_alt, Colors.indigo, 
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistorialScreen()))
              ),

              _buildMenuItem(context, '4. Importación/Exportación', Icons.cloud_sync, Colors.blueGrey, 
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen()))
              ),

              _buildMenuItem(context, '5. Configuración', Icons.settings, Colors.grey[700]!, 
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConfigScreen()))
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