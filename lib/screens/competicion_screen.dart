import 'package:flutter/material.dart';
import '../models/competicion_model.dart';
import '../services/competicion_service.dart';
// Importamos las pantallas de destino
import 'competicion_detalle_screen.dart'; // Para editar
import 'competicion_setup_screen.dart';   // Para empezar (Setup)

class CompeticionScreen extends StatefulWidget {
  const CompeticionScreen({super.key});

  @override
  State<CompeticionScreen> createState() => _CompeticionScreenState();
}

class _CompeticionScreenState extends State<CompeticionScreen> {
  final CompeticionService _service = CompeticionService();
  List<Modalidad> _lista = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() async {
    final datos = await _service.obtenerModalidades();
    setState(() => _lista = datos);
  }

  // --- MENÚ DE ACCIÓN (EMPEZAR O EDITAR) ---
  void _mostrarOpciones(Modalidad item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        height: 220, // Altura del panel
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item.nombre, 
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), 
              textAlign: TextAlign.center
            ),
            const SizedBox(height: 10),
            Text(
              item.descripcion ?? 'Selecciona una acción',
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            
            Row(
              children: [
                // BOTÓN EDITAR
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit, color: Colors.blueGrey),
                    label: const Text('EDITAR FASES', style: TextStyle(color: Colors.blueGrey)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      side: const BorderSide(color: Colors.blueGrey),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx); // Cerrar menú
                      // Ir al editor de fases
                      Navigator.push(
                        context, 
                        MaterialPageRoute(builder: (_) => CompeticionDetalleScreen(modalidad: item))
                      ).then((_) => _cargarDatos());
                    },
                  ),
                ),
                const SizedBox(width: 15),
                
                // BOTÓN EMPEZAR
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('EMPEZAR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      elevation: 5,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx); // Cerrar menú
                      // Ir al Setup para elegir arma y empezar
                      Navigator.push(
                        context, 
                        MaterialPageRoute(builder: (_) => CompeticionSetupScreen(modalidad: item))
                      );
                    },
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // Crear nueva modalidad
  void _crearModalidad() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva Competición'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nombre del Torneo', 
            hintText: 'Ej: Mi Entrenamiento Mixto'
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('Cancelar')
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await _service.crearModalidad(Modalidad(
                  nombre: controller.text.trim(),
                  descripcion: 'Personalizado',
                  esOficial: false, 
                ));
                _cargarDatos();
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _borrarModalidad(Modalidad item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar Competición'),
        content: Text('¿Eliminar "${item.nombre}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await _service.borrarModalidadCompleta(item.id!);
              _cargarDatos();
            },
            child: const Text('Borrar Todo'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Competiciones'), 
        backgroundColor: Colors.amber[700],
      ),
      body: _lista.isEmpty
          ? const Center(child: Text('Cargando competiciones...'))
          : ListView.builder(
              itemCount: _lista.length,
              itemBuilder: (context, index) {
                final item = _lista[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: item.esOficial ? Colors.amber.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                      child: Icon(
                        item.esOficial ? Icons.emoji_events : Icons.edit_note,
                        color: item.esOficial ? Colors.amber[800] : Colors.blue,
                      ),
                    ),
                    title: Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(item.esOficial ? 'Oficial ISSF' : 'Personalizada'),
                    
                    // Solo permitimos borrar si NO es oficial
                    trailing: item.esOficial 
                      ? const Icon(Icons.lock_outline, color: Colors.grey, size: 20)
                      : IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _borrarModalidad(item),
                        ),
                    
                    // AQUÍ ESTÁ LA CLAVE: Al tocar, abre el menú de opciones
                    onTap: () => _mostrarOpciones(item),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.amber[700],
        onPressed: _crearModalidad,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}