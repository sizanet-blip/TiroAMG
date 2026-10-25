import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'screens/auth_gate_screen.dart';
import 'screens/home_screen.dart';
import 'services/app_auth_service.dart';
import 'theme/app_theme.dart';

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

class TiroTrackerApp extends StatefulWidget {
  const TiroTrackerApp({super.key});

  @override
  State<TiroTrackerApp> createState() => _TiroTrackerAppState();
}

class _TiroTrackerAppState extends State<TiroTrackerApp>
    with WidgetsBindingObserver {
  var _authReady = !AppAuthService.isConfigured;
  var _checkingAuth = AppAuthService.isConfigured;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setWakelock(true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuth());
  }

  Future<void> _checkAuth() async {
    if (!AppAuthService.isConfigured) {
      if (mounted) {
        setState(() {
          _authReady = true;
          _checkingAuth = false;
        });
      }
      return;
    }
    final ok = await AppAuthService().hasSession();
    if (!mounted) return;
    setState(() {
      _authReady = ok;
      _checkingAuth = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setWakelock(true);
    } else {
      _setWakelock(false);
    }
  }

  Future<void> _setWakelock(bool enabled) async {
    await WakelockPlus.toggle(enable: enabled);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setWakelock(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TiroAMG', 
      theme: buildTiroAmgTheme(),
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

      home: _checkingAuth
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (_authReady
              ? const HomeScreen()
              : AuthGateScreen(
                  onAuthenticated: () => setState(() => _authReady = true),
                )),
    );
  }
}