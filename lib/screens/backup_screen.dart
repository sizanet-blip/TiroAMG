import 'package:flutter/material.dart';

class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Copia de Seguridad')),
      body: const Center(child: Text('Pantalla de Importación/Exportación')),
    );
  }
}