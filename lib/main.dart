import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'screens/home_screen.dart';

void main() {
  // 1. Inicializar bindings de Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Inicializar BD para Windows/Linux/Mac
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
      title: 'Tiro Deportivo AMG', 
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        useMaterial3: true,
      ),
      
      // --- CONFIGURACIÓN DE IDIOMA (¡NUEVO!) ---
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'ES'), // Español
        Locale('en', 'US'), // Inglés (por si acaso)
      ],
      // -----------------------------------------

      home: const HomeScreen(),
    );
  }
}