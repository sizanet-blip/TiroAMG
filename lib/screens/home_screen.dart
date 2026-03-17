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
import '../utils/responsive_layout.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AppUpdateService _updateService = const AppUpdateService();
  final LicenseService _licenseService = const LicenseService();
  final LicensePermissionsService _permissions =
      const LicensePermissionsService();
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

    final retryResult =
        await _licenseService.revisarLicencia(forzarServidor: true);
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
                          final res =
                              await _licenseService.solicitarLicenciaAutomatica(
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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final veryNarrow = screenWidth < 340;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final landscapeColumns =
        ResponsiveLayout.actionGridColumns(context, landscape: true);
    final landscapeCompactCards =
        ResponsiveLayout.isCompactLandscape(context, maxWidth: 1100);
    final compactTopBar = isLandscape && screenWidth < 900;
    final mainCardsAspect = !isLandscape
        ? 2.0
        : (screenWidth < 700 ? 2.7 : (screenWidth < 1100 ? 3.0 : 3.25));
    final moreCardsAspect = !isLandscape
        ? 2.4
        : (screenWidth < 700 ? 2.9 : (screenWidth < 1100 ? 3.2 : 3.5));
    final contentPadding = ResponsiveLayout.pagePadding(context);
    final maxContentWidth = ResponsiveLayout.maxContentWidth(context);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            pinned: true,
            toolbarHeight: compactTopBar ? 56 : 64,
            titleSpacing: compactTopBar ? 8 : 12,
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            elevation: 0,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: veryNarrow
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.adjust, size: 18, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'AMG',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        )
                      : Image.asset(
                          'assets/logo.png',
                          height: compactTopBar ? 30 : 36,
                          fit: BoxFit.contain,
                        ),
                ),
                if (_licenciaActual != null) ...[
                  SizedBox(width: compactTopBar ? 6 : 8),
                  Flexible(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compactTopBar ? 8 : 10,
                        vertical: compactTopBar ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(compactTopBar ? 14 : 16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified,
                            size: compactTopBar ? 12 : 14,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          if (!veryNarrow) ...[
                            SizedBox(width: compactTopBar ? 3 : 4),
                            Flexible(
                              child: Text(
                                _permissions.currentPlanLabel(_licenciaActual?.plan).toUpperCase(),
                                style: TextStyle(
                                  fontSize: compactTopBar ? 9 : 10,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              contentPadding,
              isLandscape ? 14 : 24,
              contentPadding,
              isLandscape ? 24 : 32,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxContentWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Panel de Control',
                          style: TextStyle(
                            fontSize: isLandscape ? 20 : 22,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: isLandscape ? 12 : 16),
                        if (isLandscape)
                          _buildGroupedButtonsGrid(
                            crossAxisCount: landscapeColumns,
                            childAspectRatio: mainCardsAspect,
                            children: [
                              _buildModernActionCard(
                                context: context,
                                title: 'Entrenamiento',
                                subtitle: 'Registra series y mejora tu técnica.',
                                icon: Icons.track_changes,
                                color: Colors.teal,
                                isDark: isDark,
                                dense: landscapeCompactCards,
                                inGrid: true,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const EntrenamientoScreen()),
                                ),
                              ),
                              _buildModernActionCard(
                                context: context,
                                title: 'Competición',
                                subtitle: 'Gestiona tiradas oficiales y resultados.',
                                icon: Icons.emoji_events,
                                color: Colors.amber.shade700,
                                isDark: isDark,
                                dense: landscapeCompactCards,
                                inGrid: true,
                                locked: bloqueoCompeticion,
                                lockPlanLabel: _permissions.requiredPlanLabel(
                                  LicenseCapability.competition,
                                ),
                                onTap: () => _abrirSiPermitido(
                                  context: context,
                                  capability: LicenseCapability.competition,
                                  onAllowed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const CompeticionScreen()),
                                  ),
                                ),
                              ),
                              _buildModernActionCard(
                                context: context,
                                title: 'Historial y análisis',
                                subtitle: 'Consulta tu progreso y estadísticas.',
                                icon: Icons.analytics,
                                color: Colors.indigo,
                                isDark: isDark,
                                dense: landscapeCompactCards,
                                inGrid: true,
                                onTap: () => Navigator.push(
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
                                ),
                              ),
                            ],
                          )
                        else ...[
                          _buildModernActionCard(
                            context: context,
                            title: 'Entrenamiento',
                            subtitle: 'Registra series y mejora tu técnica.',
                            icon: Icons.track_changes,
                            color: Colors.teal,
                            isDark: isDark,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const EntrenamientoScreen()),
                            ),
                          ),
                          _buildModernActionCard(
                            context: context,
                            title: 'Competición',
                            subtitle: 'Gestiona tiradas oficiales y resultados.',
                            icon: Icons.emoji_events,
                            color: Colors.amber.shade700,
                            isDark: isDark,
                            locked: bloqueoCompeticion,
                            lockPlanLabel: _permissions.requiredPlanLabel(
                              LicenseCapability.competition,
                            ),
                            onTap: () => _abrirSiPermitido(
                              context: context,
                              capability: LicenseCapability.competition,
                              onAllowed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const CompeticionScreen()),
                              ),
                            ),
                          ),
                          _buildModernActionCard(
                            context: context,
                            title: 'Historial y análisis',
                            subtitle: 'Consulta tu progreso y estadísticas.',
                            icon: Icons.analytics,
                            color: Colors.indigo,
                            isDark: isDark,
                            onTap: () => Navigator.push(
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
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),
                        Text(
                          'Más opciones',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (isLandscape)
                          _buildGroupedButtonsGrid(
                            crossAxisCount: landscapeColumns,
                            childAspectRatio: moreCardsAspect,
                            children: [
                              _buildModernMenuCard(
                                child: _buildModernMenuItem(
                                  context: context,
                                  title: 'Copia de seguridad',
                                  icon: Icons.cloud_sync_rounded,
                                  color: Colors.blueGrey,
                                  dense: landscapeCompactCards,
                                  locked: bloqueoBackup,
                                  lockPlanLabel: _permissions.requiredPlanLabel(
                                    LicenseCapability.backup,
                                  ),
                                  onTap: () => _abrirSiPermitido(
                                    context: context,
                                    capability: LicenseCapability.backup,
                                    onAllowed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const BackupScreen()),
                                    ),
                                  ),
                                ),
                              ),
                              _buildModernMenuCard(
                                child: _buildModernMenuItem(
                                  context: context,
                                  title: 'Configuración',
                                  icon: Icons.settings_rounded,
                                  color: Colors.grey.shade700,
                                  dense: landscapeCompactCards,
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const ConfigScreen()),
                                    );
                                    if (!mounted) return;
                                    final refreshed = await _licenseService.revisarLicencia(
                                      forzarServidor: true,
                                    );
                                    if (!mounted) return;
                                    _actualizarLicencia(refreshed.licencia);
                                  },
                                ),
                              ),
                              if (kDebugMode)
                                _buildModernMenuCard(
                                  child: _buildModernMenuItem(
                                    context: context,
                                    title: 'Recorte Diana (pruebas)',
                                    icon: Icons.camera_alt_rounded,
                                    color: Colors.deepOrange,
                                    dense: landscapeCompactCards,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const RecorteDianaScreen(),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                                color: colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                )),
                            child: Column(
                              children: [
                                _buildModernMenuItem(
                                  context: context,
                                  title: 'Copia de seguridad',
                                  icon: Icons.cloud_sync_rounded,
                                  color: Colors.blueGrey,
                                  locked: bloqueoBackup,
                                  lockPlanLabel: _permissions.requiredPlanLabel(
                                    LicenseCapability.backup,
                                  ),
                                  onTap: () => _abrirSiPermitido(
                                    context: context,
                                    capability: LicenseCapability.backup,
                                    onAllowed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const BackupScreen()),
                                    ),
                                  ),
                                ),
                                Divider(
                                    height: 1,
                                    indent: 56,
                                    color:
                                        colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                _buildModernMenuItem(
                                  context: context,
                                  title: 'Configuración',
                                  icon: Icons.settings_rounded,
                                  color: Colors.grey.shade700,
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const ConfigScreen()),
                                    );
                                    if (!mounted) return;
                                    final refreshed = await _licenseService.revisarLicencia(
                                      forzarServidor: true,
                                    );
                                    if (!mounted) return;
                                    _actualizarLicencia(refreshed.licencia);
                                  },
                                ),
                                if (kDebugMode) ...[
                                  Divider(
                                      height: 1,
                                      indent: 56,
                                      color: colorScheme.outlineVariant
                                          .withValues(alpha: 0.5)),
                                  _buildModernMenuItem(
                                    context: context,
                                    title: 'Recorte Diana (pruebas)',
                                    icon: Icons.camera_alt_rounded,
                                    color: Colors.deepOrange,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const RecorteDianaScreen(),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedButtonsGrid({
    required int crossAxisCount,
    required double childAspectRatio,
    required List<Widget> children,
  }) {
    return GridView.count(
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: childAspectRatio,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );
  }

  Widget _buildModernMenuCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.5),
        ),
      ),
      child: child,
    );
  }

  Widget _buildModernActionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
    bool dense = false,
    bool inGrid = false,
    bool locked = false,
    String? lockPlanLabel,
  }) {
    final lockColor = LicenseUiHelper.lockColorForPlan(lockPlanLabel);
    final themeInfo = Theme.of(context).colorScheme;
    
    // Si está bloqueado, lo atenuamos un poco
    final double opacity = locked ? 0.7 : 1.0;
    
    return Container(
      margin: EdgeInsets.only(bottom: inGrid ? 0 : 16),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Opacity(
            opacity: opacity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 420;
                final lockText = lockPlanLabel == null
                    ? null
                    : 'REQUIERE PLAN ${lockPlanLabel.toUpperCase()}';

                if (compact) {
                  return Padding(
                    padding: EdgeInsets.all(dense ? 12 : 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(dense ? 8 : 10),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: isDark ? 0.2 : 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, size: dense ? 20 : 24, color: color),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: themeInfo.onSurface.withValues(alpha: 0.3),
                              size: 24,
                            ),
                          ],
                        ),
                        SizedBox(height: dense ? 6 : 10),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: dense ? 14 : 15,
                            fontWeight: FontWeight.bold,
                            color: themeInfo.onSurface,
                          ),
                        ),
                        SizedBox(height: dense ? 2 : 4),
                        Text(
                          subtitle,
                          maxLines: dense ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: dense ? 11 : 12,
                            color: themeInfo.onSurfaceVariant,
                            height: 1.2,
                          ),
                        ),
                        if (locked && lockText != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: lockColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: lockColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.lock_outline, size: 12, color: lockColor),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    lockText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: lockColor,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // Marca de agua del icono de fondo
                    Positioned(
                      right: -10,
                      bottom: -15,
                      child: Icon(
                        icon,
                        size: 100,
                        color: color.withValues(alpha: isDark ? 0.1 : 0.05),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(dense ? 12 : 16),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(dense ? 8 : 10),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: isDark ? 0.2 : 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, size: dense ? 22 : 28, color: color),
                          ),
                          SizedBox(width: dense ? 10 : 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: dense ? 14 : 16,
                                    fontWeight: FontWeight.bold,
                                    color: themeInfo.onSurface,
                                  ),
                                ),
                                SizedBox(height: dense ? 1 : 2),
                                Text(
                                  subtitle,
                                  maxLines: dense ? 1 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: dense ? 11 : 12,
                                    color: themeInfo.onSurfaceVariant,
                                    height: 1.2,
                                  ),
                                ),
                                if (locked && lockText != null) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: lockColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: lockColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.lock_outline, size: 12, color: lockColor),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            lockText,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              color: lockColor,
                                              letterSpacing: 0.5,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ]
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: themeInfo.onSurface.withValues(alpha: 0.3),
                            size: dense ? 24 : 28,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernMenuItem({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool dense = false,
    bool locked = false,
    String? lockPlanLabel,
  }) {
    final lockColor = LicenseUiHelper.lockColorForPlan(lockPlanLabel);
    final themeInfo = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? (dense ? 10 : 12) : (dense ? 12 : 16),
              vertical: compact ? (dense ? 10 : 12) : (dense ? 11 : 14),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(compact ? (dense ? 6 : 7) : (dense ? 7 : 8)),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: compact ? (dense ? 16 : 18) : (dense ? 18 : 20), color: color),
                ),
                SizedBox(width: compact ? (dense ? 6 : 8) : (dense ? 8 : 12)),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? (dense ? 13 : 14) : (dense ? 14 : 16),
                      fontWeight: FontWeight.w600,
                      color: locked
                          ? themeInfo.onSurface.withValues(alpha: 0.6)
                          : themeInfo.onSurface,
                    ),
                  ),
                ),
                if (locked && lockPlanLabel != null) ...[
                  const SizedBox(width: 8),
                  if (compact)
                    Icon(Icons.lock_outline, size: 16, color: lockColor)
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: lockColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline, size: 12, color: lockColor),
                          const SizedBox(width: 4),
                          Text(
                            lockPlanLabel.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: lockColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                SizedBox(width: compact ? 2 : 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: compact ? 18 : 20,
                  color: themeInfo.onSurface.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
