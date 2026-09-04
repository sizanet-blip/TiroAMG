import 'package:flutter/material.dart';
// Importamos las pantallas de destino
import 'competicion_screen.dart';
import 'entrenamiento_screen.dart';
import 'historial_screen.dart';
import 'backup_screen.dart';
import 'config_screen.dart';
import 'recorte_diana_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/app_update_service.dart';
import '../services/license_service.dart';
import '../services/license_permissions_service.dart';
import '../models/licencia_model.dart';

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
  LicenciaLocal? _licenciaActual;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupChecks());
  }

  Future<void> _runStartupChecks() async {
    // Ficha local primero (rápido). La red va en segundo plano.
    try {
      final quick = await _licenseService
          .revisarLicencia(forzarServidor: false)
          .timeout(const Duration(seconds: 4));
      if (!mounted) return;
      _actualizarLicencia(quick.licencia);
    } catch (_) {}

    if (!mounted) return;
    // ignore: unawaited_futures
    _syncInstallationInBackground();

    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    try {
      await _maybeShowIdentifyPrompt();
    } catch (_) {}

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
    if (!show || !mounted) return;
    await _showIdentifyDialog();
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

  Future<void> _showIdentifyDialog() async {
    final userController = TextEditingController(
      text: _licenciaActual?.contactEmail ?? '',
    );
    String mensaje =
        'Opcional: asocia un email para localizar esta instalación en el panel.';
    bool cargando = false;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Identificar instalación'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mensaje),
                  const SizedBox(height: 12),
                  TextField(
                    controller: userController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: cargando
                      ? null
                      : () async {
                          await _licenseService.neverAskIdentifyPrompt();
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                  child: const Text('No volver a preguntar'),
                ),
                TextButton(
                  onPressed: cargando
                      ? null
                      : () async {
                          await _licenseService.snoozeIdentifyPrompt(days: 7);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                  child: const Text('Ahora no'),
                ),
                FilledButton(
                  onPressed: cargando
                      ? null
                      : () async {
                          final email = userController.text.trim();
                          if (!_emailRegex.hasMatch(email)) {
                            setStateDialog(() {
                              mensaje =
                                  'Introduce un email válido o pulsa «Ahora no».';
                            });
                            return;
                          }
                          setStateDialog(() => cargando = true);
                          final res = await _licenseService.identificarEmail(
                            email: email,
                          );
                          if (!ctx.mounted) return;
                          setStateDialog(() {
                            cargando = false;
                            mensaje = res.mensaje;
                          });
                          if (res.licencia != null) {
                            _actualizarLicencia(res.licencia);
                          }
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: [
                _buildBrandHeader(),
                const SizedBox(height: 28),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8EE)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0)
                          const Divider(
                            height: 1,
                            indent: 68,
                            endIndent: 16,
                            color: Color(0xFFE8EEF2),
                          ),
                        _buildMenuTile(items[i]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/logo.png',
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              'TiroAMG',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                height: 1,
                color: Colors.blueGrey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Tiro deportivo · entrenamientos y competiciones',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w500,
            color: Colors.blueGrey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _buildMenuTile(_HomeMenuItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, size: 22, color: item.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.blueGrey.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.blueGrey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.blueGrey.shade300,
              ),
            ],
          ),
        ),
      ),
    );
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
