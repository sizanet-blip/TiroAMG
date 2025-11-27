import 'package:flutter/material.dart';
// 1. IMPORTANTE: Importamos la pantalla del catálogo que acabamos de crear
import 'catalogo_tipos_screen.dart';

class ConfigScreen extends StatelessWidget {
  const ConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        backgroundColor: Colors.blueGrey,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          // --- SECCIÓN A: EQUIPO ---
          _buildSectionHeader('A. Mi Equipo'),
          _buildMenuItem(
            context, 
            'Gestión de Armas', 
            Icons.hardware, 
            Colors.teal, 
            () => print('Ir a Armas'), // Aquí pondremos la pantalla de armas luego
          ),

          const Divider(height: 30),

          // --- SECCIÓN B: REGLAS ---
          _buildSectionHeader('B. Reglas'),
          _buildMenuItem(
            context, 
            'Plantillas de Tiempos', 
            Icons.timer, 
            Colors.indigo, 
            () => print('Ir a Tiempos'),
          ),

          const Divider(height: 30),

          // --- SECCIÓN C: CATÁLOGOS ---
          _buildSectionHeader('C. Datos del Sistema'),
          
          // 2. AQUÍ ESTÁ EL CÓDIGO QUE ME PEDISTE
          _buildMenuItem(
            context, 
            'Catálogo Tipos de Arma', 
            Icons.category, 
            Colors.blueGrey, 
            // Navegamos a la pantalla que creamos en el paso anterior
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogoTiposScreen())),
          ),
          
          _buildMenuItem(
            context, 
            'Catálogo Calibres', 
            Icons.straighten, 
            Colors.blueGrey, 
            () => print('Ir a Calibres'),
          ),
        ],
      ),
    );
  }

  // Título de las secciones (A, B, C)
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        title,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey[700]),
      ),
    );
  }

  // El diseño de cada botón
  Widget _buildMenuItem(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        leading: Icon(icon, color: color, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}