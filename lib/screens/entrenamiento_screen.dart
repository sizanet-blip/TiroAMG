import 'package:flutter/material.dart';

class EntrenamientoScreen extends StatelessWidget {
  const EntrenamientoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrenamiento')),
      body: const Center(child: Text('Pantalla de Inicio de Entrenamiento')),
    );
  }
}