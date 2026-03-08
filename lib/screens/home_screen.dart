import 'dart:io';

import 'package:flutter/material.dart';
// Importamos las pantallas de destino
import 'competicion_screen.dart';
import 'entrenamiento_screen.dart';
import 'historial_screen.dart';
import 'backup_screen.dart';
import 'config_screen.dart';
import 'recorte_diana_screen.dart';
import 'package:flutter/foundation.dart'; // <--- Agrega esto para usar kDebugMode
import 'package:package_info_plus/package_info_plus.dart';
import '../services/app_update_service.dart';
import '../services/license_service.dart';
import '../services/license_permissions_service.dart';
import '../models/licencia_model.dart';
import '../utils/license_ui_helper.dart';

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
  bool _licenseDialogShown = false;
  LicenciaLocal? _licenciaActual;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupChecks());
  }

  Future<void> _runStartupChecks() async {
    final ok = await _checkLicenseOnStart();
    if (!ok || !mounted) return;
    await _checkUpdatesOnStart();
  }

  Future<bool> _checkLicenseOnStart() async {
    if (!mounted) return false;

    final initialResult = await _licenseService.revisarLicencia();
    if (!mounted) return false;

    if (initialResult.esValida) {
      _actualizarLicencia(initialResult.licencia);
      if (initialResult.enGraciaOffline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(initialResult.mensaje)),
        );
      }
      return true;
    }

    if (_licenseDialogShown) return false;
    _licenseDialogShown = true;
    await _showLicenseDialog(initialResult.mensaje);
    _licenseDialogShown = false;

    final retryResult = await _licenseService.revisarLicencia(forzarServidor: true);
    if (!mounted) return false;
    if (retryResult.esValida) {
      _actualizarLicencia(retryResult.licencia);
      return true;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(retryResult.mensaje)),
      );
    }
    return false;
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
      await _mostrarDialogoUpgrade(capability: capability);
      return;
    }

    final serverResult = await _licenseService.verificarCapacidadServidor(
      licencia: _licenciaActual,
      capability: _permissions.toServerCapability(capability),
    );

    // known=true: respuesta autoritativa del servidor.
    if (serverResult.known && !serverResult.allowed) {
      if (!mounted) return;
      await _mostrarDialogoUpgrade(
        capability: capability,
        detalleServidor: serverResult.message,
      );
      return;
    }

    onAllowed();
  }

  Future<void> _mostrarDialogoUpgrade({
    required LicenseCapability capability,
    String? detalleServidor,
  }) async {
    if (!mounted) return;
    final planNecesario = _permissions.requiredPlanLabel(capability);
    final planActual = _permissions.currentPlanLabel(_licenciaActual?.plan);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Función bloqueada por licencia'),
        content: Text(
          detalleServidor?.trim().isNotEmpty == true
              ? '$detalleServidor\n\nTu plan actual: $planActual.\nPlan requerido: $planNecesario o superior.'
              : 'Tu plan actual es $planActual.\nEsta opción requiere plan $planNecesario o superior.',
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await _licenseService.solicitarUpgrade(
                licencia: _licenciaActual,
                capability: _permissions.toServerCapability(capability),
                requiredPlan: planNecesario,
                currentPlan: planActual,
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(result.message)),
              );
            },
            child: const Text('Solicitar mejora de plan'),
          ),
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

  Future<void> _showLicenseDialog(String initialMessage) async {
    final userController = TextEditingController();
    String mensaje = initialMessage;
    bool cargando = false;

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('Activar cuenta'),
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
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: cargando
                      ? null
                      : () async {
                          final email = userController.text.trim();
                          if (!_emailRegex.hasMatch(email)) {
                            setStateDialog(() {
                              mensaje =
                                  'Introduce un email válido para activar tu cuenta.';
                            });
                            return;
                          }
                          setStateDialog(() => cargando = true);
                          final res = await _licenseService.solicitarLicenciaAutomatica(
                            identificadorUsuario: email,
                            nombreApp: 'Tiro Deportivo AMG',
                          );
                          if (!ctx.mounted) return;
                          setStateDialog(() {
                            cargando = false;
                            mensaje = res.mensaje;
                          });
                          if (res.esValida) {
                            Navigator.of(ctx).pop();
                          }
                        },
                  child: const Text('Activar'),
                ),
                if (!kIsWeb)
                  TextButton(
                    onPressed: cargando
                        ? null
                        : () {
                            exit(0);
                          },
                    child: const Text('Salir'),
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
    final bloqueoCompeticion =
        !_permissions.canAccess(_licenciaActual, LicenseCapability.competition);
    final bloqueoBackup =
        !_permissions.canAccess(_licenciaActual, LicenseCapability.backup);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Tiro Deportivo AMG'),
        backgroundColor: Colors.blueGrey,
        centerTitle: true,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // --- LOGO ---
              const Padding(
                padding: EdgeInsets.only(bottom: 40.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.adjust,
                      size: 100,
                      color: Colors.blueGrey,
                    ),
                    SizedBox(height: 15),
                    Text(
                      'Registro de Tiro',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
              if (_licenciaActual != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Center(
                    child: Chip(
                      avatar: const Icon(Icons.verified, size: 18),
                      label: Text(
                        'Plan: ${_permissions.currentPlanLabel(_licenciaActual?.plan)}',
                      ),
                    ),
                  ),
                ),

              // --- BOTONES DEL MENÚ ---
              if (kDebugMode) ...[
                // ** NUEVA OPCIÓN DE PRUEBAS (PRIMERA) **
                _buildMenuItem(
                    context,
                    'Recorte Diana (Pruebas)',
                    Icons.camera_alt,
                    Colors.deepOrange,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RecorteDianaScreen()))),
              ],
              _buildMenuItem(
                  context,
                  'Competición',
                  Icons.emoji_events,
                  Colors.amber[700]!,
                  locked: bloqueoCompeticion,
                  lockPlanLabel: _permissions.requiredPlanLabel(
                    LicenseCapability.competition,
                  ),
                  () => _abrirSiPermitido(
                        context: context,
                        capability: LicenseCapability.competition,
                        onAllowed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CompeticionScreen()),
                        ),
                      )),

              _buildMenuItem(
                  context,
                  'Entrenamiento',
                  Icons.sports_baseball,
                  Colors.teal,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const EntrenamientoScreen()))),

              _buildMenuItem(
                  context,
                  'Historial y Análisis',
                  Icons.analytics,
                  Colors.indigo,
                  () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HistorialScreen(
                            puedeVerEstadisticas: _permissions.canAccess(
                              _licenciaActual,
                              LicenseCapability.analytics,
                            ),
                            puedeVerCompeticiones: _permissions.canAccess(
                              _licenciaActual,
                              LicenseCapability.competition,
                            ),
                            requiredPlanEstadisticas:
                                _permissions.requiredPlanLabel(
                              LicenseCapability.analytics,
                            ),
                          ),
                        ),
                      )),

              _buildMenuItem(
                  context,
                  'Copia de Seguridad',
                  Icons.cloud_sync,
                  Colors.blueGrey,
                  locked: bloqueoBackup,
                  lockPlanLabel: _permissions.requiredPlanLabel(
                    LicenseCapability.backup,
                  ),
                  () => _abrirSiPermitido(
                        context: context,
                        capability: LicenseCapability.backup,
                        onAllowed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BackupScreen()),
                        ),
                      )),

              _buildMenuItem(
                  context,
                  'Configuración',
                  Icons.settings,
                  Colors.grey[700]!,
                  () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ConfigScreen()),
                    );
                    if (!mounted) return;
                    final refreshed = await _licenseService.revisarLicencia(
                      forzarServidor: true,
                    );
                    if (!mounted) return;
                    _actualizarLicencia(refreshed.licencia);
                  }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    bool locked = false,
    String? lockPlanLabel,
  }) {
    final lockColor = LicenseUiHelper.lockColorForPlan(lockPlanLabel);
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(width: 20),
              Expanded(
                // Aquí quitamos la necesidad de que el título contenga la numeración
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (locked)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock, size: 16, color: lockColor),
                          if (lockPlanLabel != null && lockPlanLabel.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                lockPlanLabel.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: lockColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

}
