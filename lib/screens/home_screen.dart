import 'package:flutter/material.dart';
// Importamos las pantallas de destino
import 'competicion_screen.dart';
import 'entrenamiento_screen.dart';
import 'historial_screen.dart';
import 'backup_screen.dart';
import 'config_screen.dart';
import 'ayuda_screen.dart';
import 'recorte_diana_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../main.dart';
import '../services/app_auth_service.dart';
import '../services/app_update_service.dart';
import '../services/license_service.dart';
import '../services/license_permissions_service.dart';
import '../models/licencia_model.dart';
import '../theme/app_theme.dart';
import '../utils/app_exit.dart';
import '../widgets/app_ui.dart';
import '../widgets/identificar_instalacion_dialog.dart';
import '../widgets/tiro_amg_app_bar_title.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AppUpdateService _updateService = const AppUpdateService();
  final LicenseService _licenseService = const LicenseService();
  final LicensePermissionsService _permissions = const LicensePermissionsService();
  final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  bool _updateDialogShown = false;
  bool _identificacionLista = false;
  LicenciaLocal? _licenciaActual;

  bool get _puedeUsarApp => _licenciaActual?.puedeUsarApp == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupChecks());
  }

  Future<void> _runStartupChecks() async {
    if (AppAuthService.isConfigured) {
      final revoke = await AppAuthService().refreshAccountOrRevoke();
      if (!mounted) return;
      if (revoke) {
        TiroTrackerApp.signOut(context);
        return;
      }
      if (AppAuthService.takeOfflineUnlockNotice()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sin conexión. Has entrado con este dispositivo. '
              'La cuenta se comprobará cuando haya internet.',
            ),
          ),
        );
      }
    }

    // Ficha local primero (rápido). La red va en segundo plano.
    try {
      final quick = await _licenseService
          .revisarLicencia(forzarServidor: false)
          .timeout(const Duration(seconds: 4));
      if (!mounted) return;
      _actualizarLicencia(quick.licencia);
      if (_puedeUsarApp) {
        setState(() => _identificacionLista = true);
      }
    } catch (_) {}

    if (!mounted) return;
    try {
      await _maybeShowIdentifyPrompt();
    } catch (_) {}

    if (!mounted) return;
    // Sync de red DESPUÉS del diálogo legal: si va antes, puede sobrescribir
    // la aceptación de privacidad/condiciones con un snapshot antiguo.
    // ignore: unawaited_futures
    _syncInstallationInBackground();

    if (!mounted) return;
    try {
      await _checkUpdatesOnStart();
    } catch (_) {}
  }

  Future<void> _syncInstallationInBackground() async {
    try {
      final result = await _licenseService
          .revisarLicencia(forzarServidor: true)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (result.licencia != null) {
        _actualizarLicencia(result.licencia);
      }
    } catch (_) {}
  }

  Future<void> _maybeShowIdentifyPrompt() async {
    final show = await _licenseService.shouldShowIdentifyPrompt();
    if (!mounted) return;
    if (!show) {
      setState(() => _identificacionLista = true);
      return;
    }
    final ok = await _showIdentifyDialog();
    if (!mounted) return;
    if (ok) {
      setState(() => _identificacionLista = true);
      return;
    }
    // Sin aceptar privacidad y condiciones no se usa la app.
    exitApp();
  }

  void _actualizarLicencia(LicenciaLocal? licencia) {
    if (!mounted) return;
    setState(() {
      _licenciaActual = licencia;
    });
  }

  Future<void> _abrirSiPermitido({
    required BuildContext context,
    required LicenseCapability capability,
    required VoidCallback onAllowed,
  }) async {
    final permitidoLocal = _permissions.canAccess(_licenciaActual, capability);
    if (!permitidoLocal) {
      await _mostrarDialogoModuloBloqueado(capability: capability);
      return;
    }

    // Solo revalidamos en servidor la detección automática.
    if (capability == LicenseCapability.targetDetection) {
      final serverResult = await _licenseService.verificarCapacidadServidor(
        licencia: _licenciaActual,
        capability: _permissions.toServerCapability(capability),
      );
      if (serverResult.known && !serverResult.allowed) {
        if (!mounted) return;
        await _mostrarDialogoModuloBloqueado(
          capability: capability,
          detalleServidor: serverResult.message,
        );
        return;
      }
    }

    onAllowed();
  }

  Future<void> _mostrarDialogoModuloBloqueado({
    required LicenseCapability capability,
    String? detalleServidor,
  }) async {
    if (!mounted) return;
    final requerido = _permissions.requiredModuleLabel(capability);
    final actual = _permissions.currentModulesLabel(_licenciaActual);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Módulo no disponible'),
        content: Text(
          detalleServidor?.trim().isNotEmpty == true
              ? '$detalleServidor\n\nMódulos actuales: $actual.\nNecesitas: $requerido.'
              : 'Esta opción requiere el módulo «$requerido».\n'
                  'Módulos actuales: $actual.\n\n'
                  'Se activa desde el panel web de instalaciones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkUpdatesOnStart() async {
    if (_updateDialogShown || !mounted) return;
    // Solo aviso automático con canal propio (UPDATE_METADATA_URL).
    // En builds de Play, Google gestiona las actualizaciones.
    if (!AppUpdateService.usesServerUpdates) return;

    final result = await _updateService.checkForUpdates();
    if (!mounted) return;

    if (result.hasUpdate && result.info != null) {
      _updateDialogShown = true;
      await _showUpdateDialog(result.info!, force: result.forceUpdate);
    }
  }

  Future<void> _showUpdateDialog(AppUpdateInfo info,
      {required bool force}) async {
    final pkg = await PackageInfo.fromPlatform();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: !force,
      builder: (ctx) {
        return AlertDialog(
          title: Text(force
              ? 'Actualización obligatoria'
              : 'Nueva actualización disponible'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Versión actual: ${pkg.version}+${pkg.buildNumber}'),
              Text('Versión nueva: ${info.latestVersion}+${info.latestBuild}'),
              const SizedBox(height: 10),
              if (info.changelog.isNotEmpty) ...[
                const Text('Cambios:'),
                const SizedBox(height: 6),
                ...info.changelog.take(4).map((line) => Text('- $line')),
              ],
            ],
          ),
          actions: [
            if (!force)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Más tarde'),
              ),
            FilledButton(
              onPressed: () async {
                final opened = await _updateService.openDownloadUrl(info);
                if (!ctx.mounted) return;
                if (!opened) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text('No se pudo abrir la descarga.')),
                  );
                }
                if (!force && ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
              },
              child: const Text('Actualizar'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _showIdentifyDialog() async {
    if (!mounted) return false;
    final ok = await showIdentificarInstalacionDialog(
      context: context,
      licenseService: _licenseService,
      emailInicial: _licenciaActual?.contactEmail,
      permitirOmitir: false,
      salirAlCancelar: true,
      emailOpcional: true,
      privacidadYaAceptada: _licenciaActual?.privacyAccepted == true,
      condicionesYaAceptadas: _licenciaActual?.termsAccepted == true,
      emailRegex: _emailRegex,
    );
    if (!ok || !mounted) return false;
    try {
      final quick = await _licenseService.revisarLicencia(forzarServidor: false);
      if (mounted) _actualizarLicencia(quick.licencia);
    } catch (_) {}
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_identificacionLista || !_puedeUsarApp) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBrandHeader(),
                  const SizedBox(height: 28),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Esperando aceptación de privacidad y condiciones…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.subtitle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final items = <_HomeMenuItem>[
      if (_permissions.canAccess(
          _licenciaActual, LicenseCapability.targetDetection))
        _HomeMenuItem(
          title: 'Recorte Diana',
          subtitle: 'Análisis fotográfico de impactos',
          icon: Icons.camera_alt_outlined,
          color: Colors.deepOrange,
          onTap: () => _abrirSiPermitido(
            context: context,
            capability: LicenseCapability.targetDetection,
            onAllowed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecorteDianaScreen()),
            ),
          ),
        ),
      _HomeMenuItem(
        title: 'Competición',
        subtitle: 'Modalidades y fases oficiales',
        icon: Icons.emoji_events_outlined,
        color: const Color(0xFFC79100),
        onTap: () => _abrirSiPermitido(
          context: context,
          capability: LicenseCapability.competition,
          onAllowed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CompeticionScreen()),
          ),
        ),
      ),
      _HomeMenuItem(
        title: 'Entrenamiento',
        subtitle: 'Series, tiempos y avisos de tiro',
        icon: Icons.gps_fixed,
        color: Colors.teal.shade700,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EntrenamientoScreen()),
        ),
      ),
      _HomeMenuItem(
        title: 'Historial y Análisis',
        subtitle: 'Sesiones, estadísticas e informes',
        icon: Icons.insights_outlined,
        color: Colors.indigo.shade600,
        onTap: () => _abrirSiPermitido(
          context: context,
          capability: LicenseCapability.analytics,
          onAllowed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HistorialScreen()),
          ),
        ),
      ),
      _HomeMenuItem(
        title: 'Copia de Seguridad',
        subtitle: 'Exportar e importar datos',
        icon: Icons.cloud_sync_outlined,
        color: Colors.blueGrey.shade600,
        onTap: () => _abrirSiPermitido(
          context: context,
          capability: LicenseCapability.backup,
          onAllowed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BackupScreen()),
          ),
        ),
      ),
      _HomeMenuItem(
        title: 'Configuración',
        subtitle: 'Equipos, plantillas y preferencias',
        icon: Icons.settings_outlined,
        color: Colors.blueGrey.shade800,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ConfigScreen()),
        ),
      ),
      _HomeMenuItem(
        title: 'Ayuda',
        subtitle: 'Guía, manual y preguntas frecuentes',
        icon: Icons.help_outline,
        color: Colors.blueGrey.shade500,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AyudaScreen()),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: [
                _buildBrandHeader(),
                const SizedBox(height: 28),
                AppNavGroup(
                  children: [
                    for (final item in items)
                      AppNavTile(
                        title: item.title,
                        subtitle: item.subtitle,
                        icon: item.icon,
                        color: item.color,
                        onTap: item.onTap,
                      ),
                  ],
                ),
                if (AppAuthService.isConfigured) ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _confirmSignOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Cerrar sesión'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accentDanger,
                      side: const BorderSide(color: AppColors.accentDanger),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader() {
    return const TiroAmgWordmark(height: 96);
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Cerrar sesión',
        icon: Icons.logout,
        iconColor: AppColors.accentDanger,
        content: const Text(
          '¿Cerrar la sesión de la cuenta AMG en este dispositivo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    TiroTrackerApp.signOut(context);
    // ignore: unawaited_futures
    AppAuthService().logout();
  }
}

class _HomeMenuItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _HomeMenuItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
