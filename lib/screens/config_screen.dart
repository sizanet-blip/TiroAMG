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
import '../services/license_permissions_service.dart';
import '../models/licencia_model.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final AppUpdateService _updateService = const AppUpdateService();
  final LicenseService _licenseService = const LicenseService();
  final LicensePermissionsService _permissions = const LicensePermissionsService();
  String _appVersion = '-';
  String _appBuild = '-';
  int? _dbUserVersion;
  String _dbPath = '-';
  String _licenciaEstado = 'Sin comprobar';
  String _licenciaDetalle = 'Estado de licencia cargado automáticamente.';
  bool _cargandoInfo = true;
  bool _comprobandoActualizacion = false;
  LicenciaLocal? _licenciaActual;
  LicenseUpgradeStatus? _ultimoUpgrade;

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
    final ultimoUpgrade = await _licenseService.obtenerUltimoUpgradeStatus();
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
      _licenciaActual = lic;
      _ultimoUpgrade = ultimoUpgrade;
    });
  }

  VoidCallback _accionProtegida({
    required LicenseCapability capability,
    required VoidCallback onAllowed,
  }) {
    return () async {
      final permitidoLocal = _permissions.canAccess(_licenciaActual, capability);
      if (!permitidoLocal) {
        await _mostrarDialogoUpgrade(capability: capability);
        return;
      }

      final serverResult = await _licenseService.verificarCapacidadServidor(
        licencia: _licenciaActual,
        capability: _permissions.toServerCapability(capability),
      );

      if (serverResult.known && !serverResult.allowed) {
        if (!mounted) return;
        await _mostrarDialogoUpgrade(
          capability: capability,
          detalleServidor: serverResult.message,
        );
        return;
      }

      onAllowed();
    };
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
        title: const Text('Opción bloqueada por licencia'),
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
              final ultimo = await _licenseService.obtenerUltimoUpgradeStatus();
              if (mounted) {
                setState(() => _ultimoUpgrade = ultimo);
              }
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

  String _normalizarPlan(String? rawPlan) {
    final p = (rawPlan ?? '').trim().toLowerCase();
    switch (p) {
      case 'basic':
      case 'basico':
      case 'básico':
      case 'trial':
      case 'essential':
        return 'basic';
      case 'medio':
      case 'medium':
        return 'medio';
      case 'pro':
      case 'premium':
        return 'pro';
      case 'completo':
      case 'complete':
      case 'full':
      case 'enterprise':
        return 'completo';
      default:
        return 'basic';
    }
  }

  String _planLabelPorClave(String clave) {
    switch (clave) {
      case 'medio':
        return 'Medio';
      case 'pro':
        return 'Pro';
      case 'completo':
        return 'Completo';
      default:
        return 'Básico';
    }
  }

  Future<void> _solicitarAmpliacionDesdeHistorial() async {
    if (!mounted) return;
    var planSolicitado = 'medio';
    var enviando = false;
    final planActualClave = _normalizarPlan(_licenciaActual?.plan);
    final opcionesPlan = <String>['medio', 'pro', 'completo'];
    if (planActualClave == 'medio') {
      planSolicitado = 'pro';
    } else if (planActualClave == 'pro') {
      planSolicitado = 'completo';
    } else if (planActualClave == 'completo') {
      planSolicitado = 'completo';
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final screenSize = MediaQuery.sizeOf(ctx);
          final dialogWidth = (screenSize.width - 32).clamp(280.0, 780.0).toDouble();
          final dialogMaxHeight = (screenSize.height * 0.78).clamp(240.0, 560.0).toDouble();
          final planActual = _permissions.currentPlanLabel(_licenciaActual?.plan);
          final planObjetivo = _planLabelPorClave(planSolicitado);
          final capability = 'solicitud_plan_$planSolicitado';

          return AlertDialog(
            title: const Text('Solicitar ampliación de licencia'),
            content: SizedBox(
              width: dialogWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: dialogMaxHeight),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selecciona el plan que quieres solicitar.',
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 640),
                          child: DataTable(
                            headingRowHeight: 36,
                            dataRowMinHeight: 36,
                            dataRowMaxHeight: 56,
                            columns: const [
                              DataColumn(label: Text('Plan')),
                              DataColumn(label: Text('Uso recomendado')),
                              DataColumn(label: Text('Funciones clave')),
                            ],
                            rows: const [
                              DataRow(cells: [
                                DataCell(Text('Básico')),
                                DataCell(Text('Inicio y entreno manual')),
                                DataCell(Text('Entrenamiento base, sin competición ni analítica avanzada.')),
                              ]),
                              DataRow(cells: [
                                DataCell(Text('Medio')),
                                DataCell(Text('Entrenamiento con más control')),
                                DataCell(Text('Analítica avanzada y reglas de entrenamiento.')),
                              ]),
                              DataRow(cells: [
                                DataCell(Text('Pro')),
                                DataCell(Text('Tirador competitivo')),
                                DataCell(Text('Competición, backup/export y gestión de catálogos.')),
                              ]),
                              DataRow(cells: [
                                DataCell(Text('Completo')),
                                DataCell(Text('Uso premium integral')),
                                DataCell(Text('Todo lo de Pro + detección automática de tiros en diana.')),
                              ]),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: planSolicitado,
                        decoration: const InputDecoration(
                          labelText: 'Plan que quieres solicitar',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: opcionesPlan
                            .map((plan) => DropdownMenuItem(
                                  value: plan,
                                  child: Text(_planLabelPorClave(plan)),
                                ))
                            .toList(),
                        onChanged: enviando
                            ? null
                            : (value) {
                                if (value == null) return;
                                setDialogState(() => planSolicitado = value);
                              },
                      ),
                      const SizedBox(height: 10),
                      Text('Plan actual: $planActual'),
                      Text('Plan solicitado: $planObjetivo'),
                      const SizedBox(height: 4),
                      const Text(
                        'Nota: la activación final depende de validación de licencia.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: enviando ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: enviando
                    ? null
                    : () async {
                        setDialogState(() => enviando = true);
                        final result = await _licenseService.solicitarUpgrade(
                          licencia: _licenciaActual,
                          capability: capability,
                          requiredPlan: planObjetivo,
                          currentPlan: planActual,
                        );
                        final ultimo = await _licenseService.obtenerUltimoUpgradeStatus();
                        if (!mounted) return;
                        setState(() => _ultimoUpgrade = ultimo);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(result.message)),
                        );
                      },
                child: const Text('Solicitar ampliación'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _mostrarHistorialUpgrade() async {
    final historial = await _licenseService.obtenerHistorialUpgrade(limit: 30);
    if (!mounted) return;
    String filtro = 'todos';

    List<LicenseUpgradeStatus> filtrar(List<LicenseUpgradeStatus> items) {
      switch (filtro) {
        case 'backend_ok':
          return items.where((e) => e.backendRegistered).toList();
        case 'backend_pendiente':
          return items.where((e) => !e.backendRegistered).toList();
        case 'email_ok':
          return items.where((e) => e.emailOpened).toList();
        case 'email_no':
          return items.where((e) => !e.emailOpened).toList();
        default:
          return items;
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final screenSize = MediaQuery.sizeOf(ctx);
          final dialogWidth = (screenSize.width - 32).clamp(280.0, 760.0).toDouble();
          final listHeight = (screenSize.height * 0.45).clamp(170.0, 360.0).toDouble();
          final filtrado = filtrar(historial);
          return AlertDialog(
            title: const Text('Historial de solicitudes'),
            content: SizedBox(
              width: dialogWidth,
              child: historial.isEmpty
                  ? const Text('No hay solicitudes registradas todavía.')
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: filtro,
                          decoration: const InputDecoration(
                            labelText: 'Filtrar por estado',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'todos', child: Text('Todos')),
                            DropdownMenuItem(value: 'backend_ok', child: Text('Backend registrado')),
                            DropdownMenuItem(value: 'backend_pendiente', child: Text('Backend pendiente')),
                            DropdownMenuItem(value: 'email_ok', child: Text('Email abierto')),
                            DropdownMenuItem(value: 'email_no', child: Text('Email no abierto')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() => filtro = value);
                          },
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Resultados: ${filtrado.length}',
                            style: TextStyle(
                              color: Colors.blueGrey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: listHeight,
                          child: filtrado.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No hay resultados para este filtro.',
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: filtrado.length,
                                  separatorBuilder: (_, __) => const Divider(height: 16),
                                  itemBuilder: (_, i) {
                                    final item = filtrado[i];
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(
                                        item.backendRegistered ? Icons.check_circle : Icons.mark_email_read,
                                        color: item.backendRegistered ? Colors.green : Colors.orange,
                                      ),
                                      title: Text(
                                        '${item.requiredPlan} · ${item.capability}',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      subtitle: Text(
                                        '${item.at.toString().split('.').first}\n'
                                        'Plan actual: ${item.currentPlan} · '
                                        'Backend: ${item.backendRegistered ? 'registrado' : 'pendiente'} · '
                                        'Email: ${item.emailOpened ? 'abierto' : 'no abierto'}\n'
                                        '${item.message}',
                                      ),
                                      isThreeLine: true,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _solicitarAmpliacionDesdeHistorial();
                },
                icon: const Icon(Icons.upgrade),
                label: const Text('Solicitar ampliación'),
              ),
              if (historial.isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    final ok = await _licenseService.exportarHistorialUpgradePorEmail(
                      items: filtrado,
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Cliente de email abierto con el historial filtrado.'
                              : 'No se pudo abrir el cliente de email.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.send),
                  label: const Text('Exportar'),
                ),
              if (historial.isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    final confirmar = await showDialog<bool>(
                      context: ctx,
                      builder: (dialogCtx) => AlertDialog(
                        title: const Text('Limpiar historial'),
                        content: const Text(
                          'Se eliminarán todas las solicitudes guardadas. Esta acción no se puede deshacer.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogCtx, false),
                            child: const Text('Cancelar'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogCtx, true),
                            child: const Text('Eliminar'),
                          ),
                        ],
                      ),
                    );
                    if (confirmar != true) return;
                    final borradas = await _licenseService.limpiarHistorialUpgrade(
                      limpiarUltimoEstado: true,
                    );
                    final ultimo = await _licenseService.obtenerUltimoUpgradeStatus();
                    if (!mounted) return;
                    setState(() => _ultimoUpgrade = ultimo);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          borradas > 0
                              ? 'Historial limpiado ($borradas registros).'
                              : 'No había registros para limpiar.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Limpiar'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
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
            _accionProtegida(
              capability: LicenseCapability.settingsRules,
              onAllowed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GestionTiemposScreen()),
              ),
            ),
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
            _accionProtegida(
              capability: LicenseCapability.settingsCatalogs,
              onAllowed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CatalogoTiposScreen()),
              ),
            ),
          ),

          _buildConfigItem(
            context,
            'Catálogo de Calibres',
            'Añadir/modificar calibres no estándar.',
            Icons.straighten,
            Colors.blueGrey,
            _accionProtegida(
              capability: LicenseCapability.settingsCatalogs,
              onAllowed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CatalogoCalibresScreen()),
              ),
            ),
          ),

          // 2. AQUÍ VA EL NUEVO BOTÓN (Justo al final de la sección C)
          _buildConfigItem(
            context,
            'Catálogo de Dianas',
            'Definir tipos de diana (Precisión, Duelo...).',
            Icons.adjust, // Icono de diana
            Colors.blueGrey,
            _accionProtegida(
              capability: LicenseCapability.settingsCatalogs,
              onAllowed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CatalogoDianasScreen()),
              ),
            ),
          ),

          const Divider(height: 30),
          _buildSectionHeader('D. Estado de la Aplicación'),
          _buildSubSectionHeader('Licencia'),
          _buildInfoCard(
            leading: const Icon(Icons.key, color: Colors.deepPurple, size: 30),
            title: 'Licencia: $_licenciaEstado',
            subtitle: _licenciaDetalle,
          ),
          if (_ultimoUpgrade != null) ...[
            const SizedBox(height: 6),
            _buildSubSectionHeader('Última solicitud de mejora de plan'),
            _buildInfoCard(
              leading: Icon(
                _ultimoUpgrade!.backendRegistered ? Icons.check_circle : Icons.mark_email_read,
                color: _ultimoUpgrade!.backendRegistered ? Colors.green : Colors.orange,
                size: 30,
              ),
              title:
                  '${_ultimoUpgrade!.requiredPlan} (${_ultimoUpgrade!.capability}) · ${_ultimoUpgrade!.at.toString().split('.').first}',
              subtitle:
                  'Plan actual: ${_ultimoUpgrade!.currentPlan}\n'
                  'Backend: ${_ultimoUpgrade!.backendRegistered ? 'registrado' : 'pendiente'} · '
                  'Email: ${_ultimoUpgrade!.emailOpened ? 'abierto' : 'no abierto'}\n'
                  '${_ultimoUpgrade!.message}',
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _mostrarHistorialUpgrade,
              icon: const Icon(Icons.history),
              label: const Text('Ver historial de solicitudes'),
            ),
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
