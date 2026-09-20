import 'package:flutter/material.dart';
import 'gestion_equipos_screen.dart';
import 'gestion_municion_screen.dart';
import 'gestion_tiempos_screen.dart';
import 'catalogo_tipos_screen.dart';
import 'catalogo_calibres_screen.dart';
import 'catalogo_dianas_screen.dart';
import 'perfil_form_screen.dart';
import 'avisos_tiro_screen.dart';
import 'estado_app_screen.dart';
import 'ayuda_screen.dart';
import '../services/license_service.dart';
import '../services/license_permissions_service.dart';
import '../models/licencia_model.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/tiro_amg_app_bar_title.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final LicenseService _licenseService = const LicenseService();
  final LicensePermissionsService _permissions =
      const LicensePermissionsService();
  LicenciaLocal? _licenciaActual;

  @override
  void initState() {
    super.initState();
    _cargarEstadoLicencia();
  }

  Future<void> _cargarEstadoLicencia() async {
    final result = await _licenseService.revisarLicencia(forzarServidor: true);
    if (!mounted) return;
    setState(() => _licenciaActual = result.licencia);
  }

  VoidCallback _accionProtegida({
    required LicenseCapability capability,
    required VoidCallback onAllowed,
  }) {
    return () async {
      final permitidoLocal =
          _permissions.canAccess(_licenciaActual, capability);
      if (!permitidoLocal) {
        await _mostrarDialogoModuloBloqueado(capability: capability);
        return;
      }

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
    };
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
      builder: (ctx) => AppDialog(
        title: 'Módulo no disponible',
        icon: Icons.lock_outline,
        iconColor: AppColors.accentDanger,
        content: Text(
          detalleServidor?.trim().isNotEmpty == true
              ? '$detalleServidor\n\nMódulos actuales: $actual.\nNecesitas: $requerido.'
              : 'Esta opción requiere «$requerido».\nMódulos actuales: $actual.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const TiroAmgAppBarTitle(section: 'Configuración')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              AppNavGroup(
                header: 'MI EQUIPO PERSONAL',
                children: [
                  AppNavTile(
                    title: 'Mis Datos (Perfil)',
                    subtitle: 'Nombre, licencia, club…',
                    icon: Icons.account_circle_outlined,
                    color: AppColors.accentTraining,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PerfilFormScreen()),
                    ),
                  ),
                  AppNavTile(
                    title: 'Gestión de Armas',
                    subtitle: 'Añadir, modificar y borrar perfiles',
                    icon: Icons.hardware_outlined,
                    color: AppColors.accentTraining,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const GestionEquiposScreen()),
                    ),
                  ),
                  AppNavTile(
                    title: 'Gestión de Munición',
                    subtitle: 'Lotes y seguimiento de munición',
                    icon: Icons.local_fire_department_outlined,
                    color: AppColors.accentTraining,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const GestionMunicionScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AppNavGroup(
                header: 'REGLAS DE ENTRENAMIENTO',
                children: [
                  AppNavTile(
                    title: 'Tiempos y series',
                    subtitle: 'Plantillas: duelo, precisión, estándar…',
                    icon: Icons.timer_outlined,
                    color: AppColors.accentAnalytics,
                    onTap: _accionProtegida(
                      capability: LicenseCapability.settingsRules,
                      onAllowed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const GestionTiemposScreen()),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AppNavGroup(
                header: 'CATÁLOGOS',
                children: [
                  AppNavTile(
                    title: 'Tipos de Arma',
                    subtitle: 'Categorías de armas',
                    icon: Icons.category_outlined,
                    color: AppColors.primary,
                    onTap: _accionProtegida(
                      capability: LicenseCapability.settingsCatalogs,
                      onAllowed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CatalogoTiposScreen()),
                      ),
                    ),
                  ),
                  AppNavTile(
                    title: 'Calibres',
                    subtitle: 'Calibres no estándar',
                    icon: Icons.straighten,
                    color: AppColors.primary,
                    onTap: _accionProtegida(
                      capability: LicenseCapability.settingsCatalogs,
                      onAllowed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CatalogoCalibresScreen()),
                      ),
                    ),
                  ),
                  AppNavTile(
                    title: 'Dianas',
                    subtitle: 'Precisión, duelo…',
                    icon: Icons.adjust,
                    color: AppColors.primary,
                    onTap: _accionProtegida(
                      capability: LicenseCapability.settingsCatalogs,
                      onAllowed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CatalogoDianasScreen()),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AppNavGroup(
                header: 'AVISOS',
                children: [
                  AppNavTile(
                    title: 'Avisos de tiro',
                    subtitle: 'Competición, volumen y vibración',
                    icon: Icons.campaign_outlined,
                    color: AppColors.accentAnalytics,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AvisosTiroScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AppNavGroup(
                header: 'SISTEMA',
                children: [
                  AppNavTile(
                    title: 'Estado de la aplicación',
                    subtitle: 'Licencia, actualizaciones y versiones',
                    icon: Icons.info_outline,
                    color: AppColors.primary,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const EstadoAppScreen()),
                      );
                      if (mounted) await _cargarEstadoLicencia();
                    },
                  ),
                  AppNavTile(
                    title: 'Ayuda',
                    subtitle: 'Guía, manual y preguntas frecuentes',
                    icon: Icons.help_outline,
                    color: AppColors.accentAnalytics,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AyudaScreen()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
