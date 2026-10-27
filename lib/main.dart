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

  /// Cierra la sesión de UI y vuelve a la pantalla de acceso.
  static void signOut([BuildContext? context]) {
    final fromContext =
        context?.findAncestorStateOfType<_TiroTrackerAppState>();
    (fromContext ?? _TiroTrackerAppState.instance)?.signOut();
  }

  @override
  State<TiroTrackerApp> createState() => _TiroTrackerAppState();
}

class _TiroTrackerAppState extends State<TiroTrackerApp>
    with WidgetsBindingObserver {
  static _TiroTrackerAppState? instance;

  var _authReady = !AppAuthService.isConfigured;
  var _checkingAuth = AppAuthService.isConfigured;

  @override
  void initState() {
    super.initState();
    instance = this;
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
    // Al abrir/reiniciar la app no se reutiliza sesión guardada en disco.
    await AppAuthService.discardPersistedSession();
    if (!mounted) return;
    setState(() {
      _authReady = false;
      _checkingAuth = false;
    });
  }

  void signOut() {
    if (!mounted) return;
    setState(() {
      _authReady = false;
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
    if (identical(instance, this)) instance = null;
    WidgetsBinding.instance.removeObserver(this);
    _setWakelock(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ValueKey: al cerrar sesión se recrea el Navigator y no quedan
    // pantallas apiladas (Config / Cuenta AMG) encima del AuthGate.
    return MaterialApp(
      key: ValueKey<String>(
        _checkingAuth
            ? 'checking'
            : (_authReady ? 'in-app' : 'auth-gate'),
      ),
      debugShowCheckedModeBanner: false,
      title: 'TiroAMG',
      theme: buildTiroAmgTheme(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'ES'),
        Locale('en', 'US'),
      ],
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