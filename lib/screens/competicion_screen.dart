import 'package:flutter/material.dart';

class CompeticionScreen extends StatelessWidget {
  const CompeticionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Competición')),
      body: const Center(child: Text('Pantalla de Registro de Competición')),
    );
  }
}