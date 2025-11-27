import 'package:flutter/material.dart';

class GestionTiemposScreen extends StatelessWidget {
  const GestionTiemposScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plantillas de Tiempos')), 
      body: const Center(child: Text('Aquí construiremos el CRUD de Tiempos y Reglas.'))
    );
  }
}