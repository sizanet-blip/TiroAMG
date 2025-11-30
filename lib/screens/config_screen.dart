import 'package:flutter/material.dart';
// Importamos todas las pantallas de gestión
import 'gestion_equipos_screen.dart';
import 'gestion_municion_screen.dart';
import 'gestion_tiempos_screen.dart';
import 'catalogo_tipos_screen.dart';
import 'catalogo_calibres_screen.dart';
import 'catalogo_dianas_screen.dart'; // <--- 1. IMPORTANTE: Añade esta línea
import 'perfil_form_screen.dart';

class ConfigScreen extends StatelessWidget {
  const ConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración del Sistema'),
        backgroundColor: Colors.blueGrey,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          // --- SECCIÓN A ---
          _buildSectionHeader('A. Mi Equipo Personal'),
          _buildConfigItem(
            context, 
            'Mis Datos (Perfil)', 
            'Nombre, Licencia, Club...', 
            Icons.account_circle, 
            Colors.teal, 
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PerfilFormScreen())),
          ),          
          _buildConfigItem(
            context, 
            'Gestión de Armas (Equipos)', 
            'Añadir, modificar y borrar perfiles de armas.', 
            Icons.hardware, 
            Colors.teal, 
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GestionEquiposScreen())),
          ),
          _buildConfigItem(
            context, 
            'Gestión de Munición', 
            'Registro y seguimiento de lotes de munición.', 
            Icons.local_fire_department, 
            Colors.teal, 
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GestionMunicionScreen())),
          ),
          
          const Divider(height: 30),

          // --- SECCIÓN B ---
          _buildSectionHeader('B. Reglas de Entrenamiento'),
          _buildConfigItem(
            context, 
            'Plantillas de Tiempos/Series', 
            'Crear reglas de Duelo (3s/7s), Precisión, Estándar.', 
            Icons.timer, 
            Colors.indigo, 
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GestionTiemposScreen())),
          ),

          const Divider(height: 30),

          // --- SECCIÓN C ---
          _buildSectionHeader('C. Datos del Sistema (Catálogos)'),
          
          _buildConfigItem(
            context, 
            'Catálogo Tipos de Arma', 
            'Añadir/modificar categorías de armas.', 
            Icons.category, 
            Colors.blueGrey, 
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogoTiposScreen())),
          ),
          
          _buildConfigItem(
            context, 
            'Catálogo de Calibres', 
            'Añadir/modificar calibres no estándar.', 
            Icons.straighten, 
            Colors.blueGrey, 
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogoCalibresScreen())),
          ),

          // 2. AQUÍ VA EL NUEVO BOTÓN (Justo al final de la sección C)
          _buildConfigItem(
            context, 
            'Catálogo de Dianas', 
            'Definir tipos de diana (Precisión, Duelo...).', 
            Icons.adjust, // Icono de diana
            Colors.blueGrey, 
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogoDianasScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey.shade700,
        ),
      ),
    );
  }

  Widget _buildConfigItem(
      BuildContext context,
      String title,
      String subtitle,
      IconData icon,
      Color color,
      VoidCallback onTap) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Icon(icon, color: color, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}