import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
// Importamos todas las pantallas de gestión
import 'gestion_equipos_screen.dart';
import 'gestion_municion_screen.dart';
import 'gestion_tiempos_screen.dart';
import 'catalogo_tipos_screen.dart';
import 'catalogo_calibres_screen.dart';
import 'catalogo_dianas_screen.dart'; // <--- 1. IMPORTANTE: Añade esta línea
import 'perfil_form_screen.dart';
import '../database/database_provider.dart';
import '../services/app_update_service.dart';
import '../services/license_service.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final AppUpdateService _updateService = const AppUpdateService();
  final LicenseService _licenseService = const LicenseService();
  String _appVersion = '-';
  String _appBuild = '-';
  int? _dbUserVersion;
  String _dbPath = '-';
  String _licenciaEstado = 'Sin comprobar';
  String _licenciaDetalle = 'Estado de licencia cargado automáticamente.';
  bool _cargandoInfo = true;
  bool _comprobandoActualizacion = false;

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
    final result = await _licenseService.revisarLicencia();
    if (!mounted) return;

    final lic = result.licencia;
    final fechaFin = lic?.fechaFin?.toLocal().toString().split(' ').first ?? '-';
    final ultimaValidacion =
        lic?.ultimaValidacion?.toLocal().toString().split('.').first ?? '-';
    final estado = lic?.estado.toUpperCase() ?? (result.esValida ? 'OK' : 'NO ACTIVA');

    setState(() {
      _licenciaEstado = estado;
      _licenciaDetalle =
          '${result.mensaje}\nVence: $fechaFin\nÚltima validación: $ultimaValidacion';
    });
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
      builder: (ctx) {
        return AlertDialog(
          title: Text(force
              ? 'Actualización obligatoria'
              : 'Nueva actualización disponible'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Versión disponible: ${info.latestVersion}+${info.latestBuild}'),
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

  @override
  Widget build(BuildContext context) {
    const dbEsperada = DatabaseProvider.schemaVersion;
    final dbReal = _dbUserVersion;
    final migracionOk = dbReal != null && dbReal >= dbEsperada;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración del Sistema'),
        backgroundColor: Colors.blueGrey,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          // --- SECCIÓN A ---
          _buildSectionHeader('A. Mi Equipo Personal'),
          _buildConfigItem(
            context,
            'Mis Datos (Perfil)',
            'Nombre, Licencia, Club...',
            Icons.account_circle,
            Colors.teal,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PerfilFormScreen())),
          ),
          _buildConfigItem(
            context,
            'Gestión de Armas (Equipos)',
            'Añadir, modificar y borrar perfiles de armas.',
            Icons.hardware,
            Colors.teal,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const GestionEquiposScreen())),
          ),
          _buildConfigItem(
            context,
            'Gestión de Munición',
            'Registro y seguimiento de lotes de munición.',
            Icons.local_fire_department,
            Colors.teal,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const GestionMunicionScreen())),
          ),

          const Divider(height: 30),

          // --- SECCIÓN B ---
          _buildSectionHeader('B. Reglas de Entrenamiento'),
          _buildConfigItem(
            context,
            'Plantillas de Tiempos/Series',
            'Crear reglas de Duelo (3s/7s), Precisión, Estándar.',
            Icons.timer,
            Colors.indigo,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const GestionTiemposScreen())),
          ),

          const Divider(height: 30),

          // --- SECCIÓN C ---
          _buildSectionHeader('C. Datos del Sistema (Catálogos)'),

          _buildConfigItem(
            context,
            'Catálogo Tipos de Arma',
            'Añadir/modificar categorías de armas.',
            Icons.category,
            Colors.blueGrey,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CatalogoTiposScreen())),
          ),

          _buildConfigItem(
            context,
            'Catálogo de Calibres',
            'Añadir/modificar calibres no estándar.',
            Icons.straighten,
            Colors.blueGrey,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CatalogoCalibresScreen())),
          ),

          // 2. AQUÍ VA EL NUEVO BOTÓN (Justo al final de la sección C)
          _buildConfigItem(
            context,
            'Catálogo de Dianas',
            'Definir tipos de diana (Precisión, Duelo...).',
            Icons.adjust, // Icono de diana
            Colors.blueGrey,
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CatalogoDianasScreen())),
          ),

          const Divider(height: 30),
          _buildSectionHeader('D. Estado de la Aplicación'),
          _buildSubSectionHeader('Licencia'),
          _buildInfoCard(
            leading: const Icon(Icons.key, color: Colors.deepPurple, size: 30),
            title: 'Licencia: $_licenciaEstado',
            subtitle: _licenciaDetalle,
          ),
          const SizedBox(height: 6),
          _buildSubSectionHeader('Actualizaciones'),
          _buildInfoCard(
            leading: const Icon(Icons.system_update_alt,
                color: Colors.deepPurple, size: 30),
            title: _comprobandoActualizacion
                ? 'Buscando actualización...'
                : 'Buscar actualizaciones',
            subtitle:
                'Consulta versión remota y abre la descarga desde tu servidor.',
            onTap: _buscarActualizacionesManual,
            showChevron: true,
          ),
          const SizedBox(height: 6),
          _buildSubSectionHeader('Información técnica'),
          Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: _cargandoInfo
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Cargando versiones...')
                      ],
                    ),
                  )
                : Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.phone_android,
                            color: Colors.indigo),
                        title: const Text('Versión App'),
                        subtitle: Text('$_appVersion+$_appBuild'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading:
                            const Icon(Icons.storage, color: Colors.indigo),
                        title: const Text('Versión Base de Datos'),
                        subtitle: Text(
                          'Actual: ${dbReal ?? '-'} | Esperada: $dbEsperada',
                        ),
                        trailing: Icon(
                          migracionOk
                              ? Icons.check_circle
                              : Icons.warning_amber_rounded,
                          color: migracionOk ? Colors.green : Colors.orange,
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading:
                            const Icon(Icons.verified, color: Colors.indigo),
                        title: const Text('Estado de Migración'),
                        subtitle:
                            Text(migracionOk ? 'OK' : 'Pendiente o parcial'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.folder, color: Colors.indigo),
                        title: const Text('Ruta BD'),
                        subtitle:
                            Text(_dbPath, style: const TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required Widget leading,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool showChevron = false,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: leading,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: showChevron
            ? const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey)
            : null,
        onTap: onTap,
      ),
    );
  }

  Widget _buildSubSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.blueGrey.shade500,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey.shade700,
        ),
      ),
    );
  }

  Widget _buildConfigItem(BuildContext context, String title, String subtitle,
      IconData icon, Color color, VoidCallback onTap) {
    return _buildInfoCard(
      leading: Icon(icon, color: color, size: 30),
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      showChevron: true,
    );
  }
}
