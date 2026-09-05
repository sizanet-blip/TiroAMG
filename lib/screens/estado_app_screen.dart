import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../database/database_provider.dart';
import '../models/licencia_model.dart';
import '../services/app_update_service.dart';
import '../services/license_permissions_service.dart';
import '../services/license_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/identificar_instalacion_dialog.dart';

class EstadoAppScreen extends StatefulWidget {
  const EstadoAppScreen({super.key});

  @override
  State<EstadoAppScreen> createState() => _EstadoAppScreenState();
}

class _EstadoAppScreenState extends State<EstadoAppScreen> {
  final AppUpdateService _updateService = const AppUpdateService();
  final LicenseService _licenseService = const LicenseService();
  final LicensePermissionsService _permissions =
      const LicensePermissionsService();

  String _appVersion = '-';
  String _appBuild = '-';
  int? _dbUserVersion;
  String _dbPath = '-';
  String _licenciaEstado = 'Sin comprobar';
  bool _licenciaOk = false;
  String? _licenciaNota;
  String _licenciaModulos = '-';
  String _licenciaEmail = '-';
  String _licenciaDevice = '-';
  String _licenciaSync = '-';
  bool _cargandoInfo = true;
  bool _comprobandoActualizacion = false;
  LicenciaLocal? _licenciaActual;

  @override
  void initState() {
    super.initState();
    _cargarInfoSistema();
    _cargarEstadoLicencia();
  }

  Future<void> _cargarInfoSistema() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final db = await DatabaseProvider.instance.database;
      final ver = await db.rawQuery('PRAGMA user_version');
      final versionValue =
          ver.isNotEmpty ? (ver.first.values.first as int? ?? 0) : 0;

      if (!mounted) return;
      setState(() {
        _appVersion = pkg.version;
        _appBuild = pkg.buildNumber;
        _dbUserVersion = versionValue;
        _dbPath = db.path;
        _cargandoInfo = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoInfo = false);
    }
  }

  Future<void> _cargarEstadoLicencia() async {
    final result = await _licenseService.revisarLicencia(forzarServidor: true);
    if (!mounted) return;

    final lic = result.licencia;
    final mods = _permissions.currentModulesLabel(lic);
    final mensaje = result.mensaje.trim();
    final notaUtil = mensaje.isEmpty ||
            mensaje.startsWith('Instalación activa') ||
            mensaje == 'Instalación registrada.' ||
            mensaje == 'Instalación local lista.' ||
            mensaje == 'Instalación identificada.'
        ? null
        : mensaje;

    setState(() {
      _licenciaOk = result.esValida;
      _licenciaEstado = result.esValida ? 'Activa' : 'Bloqueada';
      _licenciaNota = notaUtil;
      _licenciaModulos = mods;
      _licenciaEmail = (lic?.contactEmail?.trim().isNotEmpty == true)
          ? lic!.contactEmail!
          : 'Sin identificar';
      _licenciaDevice = lic?.deviceId ?? '-';
      _licenciaSync =
          lic?.ultimaValidacion?.toLocal().toString().split('.').first ?? '-';
      _licenciaActual = lic;
    });
  }

  Future<void> _identificarEmailDialog() async {
    final ok = await showIdentificarInstalacionDialog(
      context: context,
      licenseService: _licenseService,
      emailInicial: _licenciaActual?.contactEmail,
      permitirOmitir: false,
      emailOpcional: false,
      privacidadYaAceptada: _licenciaActual?.privacyAccepted == true,
      condicionesYaAceptadas: _licenciaActual?.termsAccepted == true,
    );
    if (!mounted) return;
    await _cargarEstadoLicencia();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Instalación identificada.')),
      );
    }
  }

  Future<void> _buscarActualizacionesManual() async {
    if (_comprobandoActualizacion) return;

    setState(() => _comprobandoActualizacion = true);
    final result = await _updateService.checkForUpdates();
    if (!mounted) return;
    setState(() => _comprobandoActualizacion = false);

    if (result.hasUpdate && result.info != null) {
      await _showUpdateDialog(result.info!, force: result.forceUpdate);
      return;
    }

    final message = result.message ?? 'Tu app ya está actualizada.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showUpdateDialog(AppUpdateInfo info,
      {required bool force}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: !force,
      builder: (ctx) => AppDialog(
        title: force
            ? 'Actualización obligatoria'
            : 'Nueva actualización disponible',
        icon: Icons.system_update_alt,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Versión disponible: ${info.latestVersion}+${info.latestBuild}',
              style: TextStyle(color: AppColors.title),
            ),
            if (info.changelog.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Cambios:', style: TextStyle(color: AppColors.subtitle)),
              const SizedBox(height: 6),
              ...info.changelog.take(4).map(
                    (line) => Text('- $line',
                        style: TextStyle(color: AppColors.subtitleSoft)),
                  ),
            ],
          ],
        ),
        actions: [
          if (!force)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Más tarde',
                  style: TextStyle(color: AppColors.subtitle)),
            ),
          FilledButton(
            onPressed: () async {
              final opened = await _updateService.openDownloadUrl(info);
              if (!ctx.mounted) return;
              if (!opened) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('No se pudo abrir la descarga.')),
                );
              }
              if (!force && ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const dbEsperada = DatabaseProvider.schemaVersion;
    final dbReal = _dbUserVersion;
    final migracionOk = dbReal != null && dbReal >= dbEsperada;

    return AppPageScaffold(
      title: 'Estado de la aplicación',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionCard(
            title: 'Esta instalación',
            titleIcon: Icons.verified_user_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _licenciaOk
                            ? const Color(0xFF2E7D32)
                            : AppColors.accentDanger,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _licenciaEstado,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.title,
                      ),
                    ),
                  ],
                ),
                if (_licenciaNota != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _licenciaNota!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppColors.subtitleSoft,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _techRow('Módulos', _licenciaModulos),
                _techRow('Email', _licenciaEmail),
                _techRow('Última sync', _licenciaSync),
                _techRow('Device', _licenciaDevice),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        await _cargarEstadoLicencia();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Instalación actualizada.')),
                        );
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refrescar'),
                    ),
                    TextButton.icon(
                      onPressed: _identificarEmailDialog,
                      icon: const Icon(Icons.email_outlined, size: 18),
                      label: const Text('Identificar (email)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            title: 'Actualizaciones',
            titleIcon: Icons.system_update_alt,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Consulta la versión remota y abre la descarga si hay una nueva.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.subtitleSoft,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _comprobandoActualizacion
                      ? null
                      : _buscarActualizacionesManual,
                  icon: _comprobandoActualizacion
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search),
                  label: Text(
                    _comprobandoActualizacion
                        ? 'Buscando…'
                        : 'Buscar actualizaciones',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            title: 'Información técnica',
            titleIcon: Icons.storage_outlined,
            child: _cargandoInfo
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Cargando versiones…'),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      _techRow('Versión App', '$_appVersion+$_appBuild'),
                      _techRow(
                        'Base de datos',
                        'Actual: ${dbReal ?? '-'} · Esperada: $dbEsperada',
                        trailing: Icon(
                          migracionOk
                              ? Icons.check_circle
                              : Icons.warning_amber_rounded,
                          size: 18,
                          color: migracionOk ? Colors.green : Colors.orange,
                        ),
                      ),
                      _techRow(
                        'Migración',
                        migracionOk ? 'OK' : 'Pendiente o parcial',
                      ),
                      _techRow('Ruta BD', _dbPath),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _techRow(String label, String value, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.title,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(fontSize: 12.5, color: AppColors.subtitleSoft),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}
