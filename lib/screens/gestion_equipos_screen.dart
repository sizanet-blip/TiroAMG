import 'package:flutter/material.dart';

class GestionEquiposScreen extends StatelessWidget {
  const GestionEquiposScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de Equipos (Armas)')), 
      body: const Center(child: Text('Aquí construiremos el CRUD de Equipos.'))
    );
  }
}