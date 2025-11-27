import 'dart:io'; // Necesario para detectar si es Windows
import 'package:flutter/material.dart';
// Importaciones para la base de datos en Windows
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'screens/home_screen.dart';

void main() {
  // 1. Inicializar bindings de Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // 2. CORRECCIÓN DEL ERROR: Inicializar BD para Windows/Linux/Mac
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const TiroTrackerApp());
}

class TiroTrackerApp extends StatelessWidget {
  const TiroTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tiro Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}