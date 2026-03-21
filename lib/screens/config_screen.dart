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
import '../utils/license_ui_helper.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final AppUpdateService _updateService = const AppUpdateService();
  final LicenseService _licenseService = const LicenseService();
  final LicensePermissionsService _permissions =
      const LicensePermissionsService();
  String _appVersion = '-';
  String _appBuild = '-';
  int? _dbUserVersion;
  String _dbPath = '-';
  String _licenciaEstado = 'Sin comprobar';
  String _licenciaDetalle = 'Estado de licencia cargado automáticamente.';
  bool _cargandoInfo = true;
  bool _comprobandoActualizacion = false;
  bool _refrescandoLicencia = false;
  LicenciaLocal? _licenciaActual;
  LicenseUpgradeStatus? _ultimoUpgrade;
  String _planDevSeleccionado = 'basic';
  AppDataProfile _perfilDatos = AppDataProfile.personal;

  bool get _bloqueoDemoSoloLectura {
    final lic = _licenciaActual;
    if (lic != null) return lic.esDemoSinPlan;
    // Fallback defensivo mientras carga la licencia.
    return _perfilDatos == AppDataProfile.demo;
  }

  @override
  void initState() {
    super.initState();
    _cargarPerfilDatos();
    _cargarInfoSistema();
    _cargarEstadoLicencia();
  }

  Future<void> _cargarPerfilDatos() async {
    final perfil = await DatabaseProvider.instance.currentProfile;
    if (!mounted) return;
    setState(() => _perfilDatos = perfil);
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

  Future<void> _cargarEstadoLicencia({bool forzarServidor = false}) async {
    final result = await _licenseService.revisarLicencia(
      forzarServidor: forzarServidor,
    );
    final lic = result.licencia;
    await _sincronizarPerfilSegunLicencia(lic);
    final ultimoUpgrade = await _licenseService.obtenerUltimoUpgradeStatus();
    if (!mounted) return;

    final fechaFin =
        lic?.fechaFin?.toLocal().toString().split(' ').first ?? '-';
    final ultimaValidacion =
        lic?.ultimaValidacion?.toLocal().toString().split('.').first ?? '-';
    final estado =
        lic?.estado.toUpperCase() ?? (result.esValida ? 'OK' : 'NO ACTIVA');

    setState(() {
      _licenciaEstado = estado;
      _licenciaDetalle =
          '${result.mensaje}\nVence: $fechaFin\nÚltima validación: $ultimaValidacion';
      _licenciaActual = lic;
      _ultimoUpgrade = ultimoUpgrade;
      _planDevSeleccionado = _normalizarPlan(_licenciaActual?.plan);
    });
    await _cargarPerfilDatos();
    await _cargarInfoSistema();
  }

  Future<void> _sincronizarPerfilSegunLicencia(LicenciaLocal? licencia) async {
    final actual = await DatabaseProvider.instance.currentProfile;
    // Regla:
    // - DEMO (sin plan) => Demo
    // - PLAN => Personal
    // - PLAN + DEMO => selector manual (no forzar cambio)
    if (licencia != null && licencia.esPlanConDemo) {
      if (mounted) {
        setState(() => _perfilDatos = actual);
      }
      return;
    }
    final objetivo = (licencia != null && licencia.esDemoSinPlan)
        ? AppDataProfile.demo
        : AppDataProfile.personal;
    if (actual == objetivo) return;
    await DatabaseProvider.instance.switchProfile(
      profile: objetivo,
      persist: true,
      migrateLicense: true,
    );
  }

  Future<void> _cambiarPerfilDatos(AppDataProfile perfil) async {
    if (!(_licenciaActual?.esPlanConDemo ?? false)) return;
    final cambiado = await DatabaseProvider.instance.switchProfile(
      profile: perfil,
      persist: true,
      migrateLicense: true,
    );
    if (!cambiado) return;
    await _cargarPerfilDatos();
    await _cargarInfoSistema();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Perfil cambiado a ${perfil.label}.')),
    );
  }

  Future<void> _refrescarEstadoLicenciaManual() async {
    if (_refrescandoLicencia) return;
    final planAntes = _permissions.currentPlanLabel(_licenciaActual?.plan);
    final perfilAntes = _perfilDatos;
    setState(() => _refrescandoLicencia = true);
    try {
      await _cargarEstadoLicencia(forzarServidor: true);
      final planDespues = _permissions.currentPlanLabel(_licenciaActual?.plan);
      final perfilDespues = _perfilDatos;
      final huboCambioPlan = planAntes != planDespues;
      final huboCambioPerfil = perfilAntes != perfilDespues;

      late final String mensaje;
      if (huboCambioPlan && huboCambioPerfil) {
        mensaje =
            'Licencia actualizada: plan $planAntes -> $planDespues y modo ${perfilAntes.label} -> ${perfilDespues.label}.';
      } else if (huboCambioPerfil) {
        mensaje =
            'Licencia actualizada: modo cambiado de ${perfilAntes.label} a ${perfilDespues.label}.';
      } else if (huboCambioPlan) {
        mensaje =
            'Licencia actualizada: plan cambiado de $planAntes a $planDespues.';
      } else {
        mensaje = 'Licencia actualizada. No hubo cambios.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No se pudo actualizar la licencia. Inténtalo más tarde.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _refrescandoLicencia = false);
      }
    }
  }

  VoidCallback _accionProtegida({
    required LicenseCapability capability,
    required VoidCallback onAllowed,
  }) {
    return () async {
      final permitidoLocal =
          _permissions.canAccess(_licenciaActual, capability);

      final serverResult = await _licenseService.verificarCapacidadServidor(
        licencia: _licenciaActual,
        capability: _permissions.toServerCapability(capability),
      );

      if (serverResult.known && serverResult.allowed) {
        onAllowed();
        return;
      }

      if (serverResult.known && !serverResult.allowed) {
        if (!mounted) return;
        await _mostrarDialogoUpgrade(
          capability: capability,
          detalleServidor: serverResult.message,
        );
        return;
      }

      // Si servidor no responde con certeza, fallback local.
      if (!permitidoLocal) {
        await _mostrarDialogoUpgrade(capability: capability);
        return;
      }

      onAllowed();
    };
  }

  Future<void> _mostrarBloqueoDemo({
    required String accion,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modo Demo (solo lectura)'),
        content: Text(
          'La opción "$accion" está deshabilitada en Demo sin plan.\n'
          'Con Plan + Demo se aplican permisos según el plan.',
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

  VoidCallback _accionSoloPersonal({
    required String accion,
    required VoidCallback onAllowed,
  }) {
    return () async {
      final licenciaLocal = await _licenseService.obtenerLicenciaLocal();
      if (licenciaLocal != null && mounted) {
        setState(() => _licenciaActual = licenciaLocal);
      }
      final bloqueo = licenciaLocal?.esDemoSinPlan ?? _bloqueoDemoSoloLectura;
      if (bloqueo) {
        await _mostrarBloqueoDemo(accion: accion);
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
      case 'entrenamiento':
      case 'training':
      case 'trial':
      case 'essential':
        return 'basic';
      case 'medio':
      case 'medium':
      case 'competicion':
      case 'competición':
      case 'competition':
        return 'medio';
      case 'pro':
      case 'premium':
      case 'competicion_plus':
      case 'competición_plus':
      case 'competition_plus':
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
        return 'Competición';
      case 'pro':
        return 'Competición Plus';
      case 'completo':
        return 'Completo';
      default:
        return 'Entrenamiento';
    }
  }

  String _featureLabel(String key) {
    switch (key.trim().toLowerCase()) {
      case 'competition_mode':
        return 'Modo competición';
      case 'advanced_stats':
        return 'Análisis avanzado';
      case 'backup_export':
        return 'Copias de seguridad';
      case 'training_rules':
        return 'Reglas de entrenamiento';
      case 'catalog_management':
        return 'Gestión de catálogos';
      case 'target_shot_detection':
        return 'Detección automática';
      default:
        return key.replaceAll('_', ' ');
    }
  }

  String _descripcionFeaturesPlan(Map<String, dynamic> features) {
    final activas = features.entries
        .where((e) => e.value == true)
        .map((e) => _featureLabel(e.key))
        .toList();
    if (activas.isEmpty) {
      return 'Sin funcionalidades adicionales';
    }
    return activas.join(', ');
  }

  Future<void> _aplicarPlanDesarrollo() async {
    final lic = await _licenseService.simularPlanDesarrollo(
      planClave: _planDevSeleccionado,
    );
    if (!mounted) return;
    setState(() => _licenciaActual = lic);
    await _cargarEstadoLicencia();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Plan de desarrollo aplicado: ${_planLabelPorClave(_planDevSeleccionado)}',
        ),
      ),
    );
  }

  Future<void> _solicitarAmpliacionDesdeHistorial() async {
    if (!mounted) return;
    final catalogo = await _licenseService.obtenerCatalogoPlanesComerciales(
      includeFree: true,
    );
    if (!mounted) return;
    if (catalogo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay planes disponibles ahora mismo.'),
        ),
      );
      return;
    }

    var planSeleccionado = catalogo.first;
    final planActualClave = _normalizarPlan(_licenciaActual?.plan);
    for (final item in catalogo) {
      if (_normalizarPlan(item.plan) == planActualClave) {
        planSeleccionado = item;
        break;
      }
    }
    if (_normalizarPlan(planSeleccionado.plan) == planActualClave &&
        catalogo.length > 1) {
      planSeleccionado = catalogo.firstWhere(
        (item) => _normalizarPlan(item.plan) != planActualClave,
        orElse: () => catalogo.first,
      );
    }
    var enviando = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final screenSize = MediaQuery.sizeOf(ctx);
          final dialogColorScheme = Theme.of(ctx).colorScheme;
          final dialogWidth =
              (screenSize.width - 32).clamp(280.0, 780.0).toDouble();
          final dialogMaxHeight =
              (screenSize.height * 0.78).clamp(240.0, 560.0).toDouble();
          final planActual =
              _permissions.currentPlanLabel(_licenciaActual?.plan);
          final planObjetivo = planSeleccionado.label;
          final precio = planSeleccionado.price.toStringAsFixed(2);
          final precioLabel = planSeleccionado.price <= 0
              ? 'Sin coste'
              : '$precio EUR';
          final esMismoPlan =
              _normalizarPlan(planSeleccionado.plan) == planActualClave;

          return AlertDialog(
            title: const Text('Cambiar plan'),
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
                        'Selecciona el plan que quieres activar.',
                      ),
                      const SizedBox(height: 10),
                      Column(
                        children: catalogo
                            .map(
                              (item) => Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: dialogColorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: dialogColorScheme.outlineVariant
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item.label} · ${item.price.toStringAsFixed(2)} EUR',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _descripcionFeaturesPlan(item.features),
                                      softWrap: true,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: dialogColorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: planSeleccionado.plan,
                        decoration: const InputDecoration(
                          labelText: 'Plan que quieres activar',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: catalogo
                            .map((item) => DropdownMenuItem(
                                  value: item.plan,
                                  child: Text(item.label),
                                ))
                            .toList(),
                        onChanged: enviando
                            ? null
                            : (value) {
                                if (value == null) return;
                                final nuevo = catalogo.firstWhere(
                                  (item) => item.plan == value,
                                  orElse: () => catalogo.first,
                                );
                                setDialogState(() => planSeleccionado = nuevo);
                              },
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: dialogColorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: dialogColorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Qué incluye cada plan',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: dialogColorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Entrenamiento: solo modo entrenamiento.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: dialogColorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Competición: entrenamiento + competición (sin análisis avanzado).',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: dialogColorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Competición Plus: añade análisis, copias y catálogos.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: dialogColorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Completo: todo lo anterior + detección automática (en I+D Próximamente).',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: dialogColorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('Plan actual: $planActual'),
                      Text('Plan solicitado: $planObjetivo'),
                      Text('Precio: $precioLabel'),
                      if (esMismoPlan)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'Ya tienes este plan activo.',
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
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
                    : esMismoPlan
                    ? null
                    : () async {
                        setDialogState(() => enviando = true);
                        final confirmar = await showDialog<bool>(
                          context: ctx,
                          builder: (confirmCtx) => AlertDialog(
                            title: const Text('Confirmar cambio de plan'),
                            content: Text(
                              planSeleccionado.price <= 0
                                  ? 'Vas a cambiar al plan ${planSeleccionado.label} (sin coste). ¿Deseas continuar?'
                                  : 'Vas a cambiar al plan ${planSeleccionado.label} por $precio EUR. ¿Deseas continuar?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(confirmCtx, false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(confirmCtx, true),
                                child: const Text('Confirmar'),
                              ),
                            ],
                          ),
                        );
                        if (confirmar != true) {
                          setDialogState(() => enviando = false);
                          return;
                        }

                        final result = await _licenseService.cambiarPlan(
                          licencia: _licenciaActual,
                          targetPlan: planSeleccionado.plan,
                        );

                        if (!mounted) return;
                        if (result.licenciaActualizada != null) {
                          setState(
                              () => _licenciaActual = result.licenciaActualizada);
                          await _cargarEstadoLicencia(forzarServidor: true);
                        }
                        if (!mounted) return;
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(result.message)),
                        );
                      },
                child: const Text('Aplicar cambio'),
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
          final dialogWidth =
              (screenSize.width - 32).clamp(280.0, 760.0).toDouble();
          final listHeight =
              (screenSize.height * 0.45).clamp(170.0, 360.0).toDouble();
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
                            DropdownMenuItem(
                                value: 'todos', child: Text('Todos')),
                            DropdownMenuItem(
                                value: 'backend_ok',
                                child: Text('Backend registrado')),
                            DropdownMenuItem(
                                value: 'backend_pendiente',
                                child: Text('Backend pendiente')),
                            DropdownMenuItem(
                                value: 'email_ok',
                                child: Text('Email abierto')),
                            DropdownMenuItem(
                                value: 'email_no',
                                child: Text('Email no abierto')),
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
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 16),
                                  itemBuilder: (_, i) {
                                    final item = filtrado[i];
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(
                                        item.backendRegistered
                                            ? Icons.check_circle
                                            : Icons.mark_email_read,
                                        color: item.backendRegistered
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                      title: Text(
                                        '${item.requiredPlan} · ${item.capability}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
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
                    final ok =
                        await _licenseService.exportarHistorialUpgradePorEmail(
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
                    final borradas =
                        await _licenseService.limpiarHistorialUpgrade(
                      limpiarUltimoEstado: true,
                    );
                    final ultimo =
                        await _licenseService.obtenerUltimoUpgradeStatus();
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
    final puedeReglas = _permissions.canAccess(
        _licenciaActual, LicenseCapability.settingsRules);
    final puedeCatalogos = _permissions.canAccess(
        _licenciaActual, LicenseCapability.settingsCatalogs);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            pinned: true,
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            elevation: 0,
            title: const Text(
              'Configuración',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildModernSectionHeader('A. Mi Equipo Personal', colorScheme),
                Container(
                  decoration: _modernContainerDecoration(colorScheme),
                  child: Column(
                    children: [
                      _buildModernMenuItem(
                        context: context,
                        title: 'Mis Datos (Perfil)',
                        subtitle: 'Nombre, Licencia, Club...',
                        icon: Icons.account_circle_rounded,
                        color: Colors.teal,
                        onTap: _accionSoloPersonal(
                          accion: 'Mis Datos (Perfil)',
                          onAllowed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PerfilFormScreen(),
                            ),
                          ),
                        ),
                      ),
                      _buildDivider(colorScheme),
                      _buildModernMenuItem(
                        context: context,
                        title: 'Gestión de Armas (Equipos)',
                        subtitle: 'Añadir, modificar y borrar.',
                        icon: Icons.hardware_rounded,
                        color: Colors.teal,
                        onTap: _accionSoloPersonal(
                          accion: 'Gestión de Armas (Equipos)',
                          onAllowed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GestionEquiposScreen(),
                            ),
                          ),
                        ),
                      ),
                      _buildDivider(colorScheme),
                      _buildModernMenuItem(
                        context: context,
                        title: 'Gestión de Munición',
                        subtitle: 'Registro y seguimiento de lotes.',
                        icon: Icons.local_fire_department_rounded,
                        color: Colors.teal,
                        onTap: _accionSoloPersonal(
                          accion: 'Gestión de Munición',
                          onAllowed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GestionMunicionScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (puedeReglas) ...[
                  const SizedBox(height: 24),
                  _buildModernSectionHeader(
                      'B. Reglas de Entrenamiento', colorScheme),
                  Container(
                    decoration: _modernContainerDecoration(colorScheme),
                    child: Column(
                      children: [
                        _buildModernMenuItem(
                          context: context,
                          title: 'Plantillas de Tiempos/Series',
                          subtitle: 'Crear reglas de Duelo (3s/7s), Precisión...',
                          icon: Icons.timer_rounded,
                          color: Colors.indigo,
                        onTap: _accionSoloPersonal(
                          accion: 'Plantillas de Tiempos/Series',
                          onAllowed: _accionProtegida(
                            capability: LicenseCapability.settingsRules,
                            onAllowed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const GestionTiemposScreen(),
                              ),
                            ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (puedeCatalogos) ...[
                  const SizedBox(height: 24),
                  _buildModernSectionHeader(
                      'C. Datos del Sistema (Catálogos)', colorScheme),
                  Container(
                    decoration: _modernContainerDecoration(colorScheme),
                    child: Column(
                      children: [
                        _buildModernMenuItem(
                          context: context,
                          title: 'Catálogo Tipos de Arma',
                          subtitle: 'Añadir categorías.',
                          icon: Icons.category_rounded,
                          color: Colors.blueGrey,
                        onTap: _accionSoloPersonal(
                          accion: 'Catálogo Tipos de Arma',
                          onAllowed: _accionProtegida(
                            capability: LicenseCapability.settingsCatalogs,
                            onAllowed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CatalogoTiposScreen(),
                              ),
                            ),
                            ),
                          ),
                        ),
                        _buildDivider(colorScheme),
                        _buildModernMenuItem(
                          context: context,
                          title: 'Catálogo de Calibres',
                          subtitle: 'Añadir calibres no estándar.',
                          icon: Icons.straighten_rounded,
                          color: Colors.blueGrey,
                        onTap: _accionSoloPersonal(
                          accion: 'Catálogo de Calibres',
                          onAllowed: _accionProtegida(
                            capability: LicenseCapability.settingsCatalogs,
                            onAllowed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CatalogoCalibresScreen(),
                              ),
                            ),
                            ),
                          ),
                        ),
                        _buildDivider(colorScheme),
                        _buildModernMenuItem(
                          context: context,
                          title: 'Catálogo de Dianas',
                          subtitle: 'Definir tipos de diana.',
                          icon: Icons.adjust_rounded,
                          color: Colors.blueGrey,
                        onTap: _accionSoloPersonal(
                          accion: 'Catálogo de Dianas',
                          onAllowed: _accionProtegida(
                            capability: LicenseCapability.settingsCatalogs,
                            onAllowed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CatalogoDianasScreen(),
                              ),
                            ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                _buildModernSectionHeader('D. Estado de la Aplicación', colorScheme),
                _buildSubSectionHeader('Perfil de datos', colorScheme),
                Container(
                  decoration: _modernContainerDecoration(colorScheme),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.storage,
                              color: Colors.deepPurple,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Perfil de uso',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final narrow = box.maxWidth < 380;
                              final leftLabel = (_licenciaActual?.esPlanConDemo ?? false)
                                  ? 'Plan + Demo'
                                  : ((_licenciaActual?.esDemoSinPlan ?? false)
                                      ? 'Demo'
                                      : 'Personal');
                              final rightLabel = (_licenciaActual?.esPlanConDemo ?? false)
                                  ? 'Licencia + selector manual'
                                  : 'Controlado por licencia';
                              final modeIcon = (_licenciaActual?.esDemoSinPlan ?? false)
                                  ? Icons.visibility
                                  : Icons.person;
                              if (narrow) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          modeIcon,
                                          size: 18,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            leftLabel,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: colorScheme.onSurface,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      rightLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Icon(
                                    modeIcon,
                                    size: 18,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    leftLabel,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const Spacer(),
                                  Flexible(
                                    child: Text(
                                      rightLabel,
                                      textAlign: TextAlign.end,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          (_licenciaActual?.esPlanConDemo ?? false)
                              ? 'Modo Plan + Demo activo (datos editables con permisos del plan).'
                              : ((_licenciaActual?.esDemoSinPlan ?? false)
                                  ? 'Modo Demo activo (solo lectura y demostración).'
                                  : 'Modo Personal activo (datos reales de uso diario).'),
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (_licenciaActual?.esPlanConDemo ?? false) ...[
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, box) {
                              final narrow = box.maxWidth < 420;
                              if (!narrow) {
                                return SegmentedButton<AppDataProfile>(
                                  segments: const [
                                    ButtonSegment<AppDataProfile>(
                                      value: AppDataProfile.personal,
                                      icon: Icon(Icons.person, size: 18),
                                      label: Text('Personal'),
                                    ),
                                    ButtonSegment<AppDataProfile>(
                                      value: AppDataProfile.demo,
                                      icon: Icon(Icons.visibility, size: 18),
                                      label: Text('Demo'),
                                    ),
                                  ],
                                  selected: {_perfilDatos},
                                  onSelectionChanged: (selection) {
                                    if (selection.isEmpty) return;
                                    _cambiarPerfilDatos(selection.first);
                                  },
                                );
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _cambiarPerfilDatos(AppDataProfile.personal),
                                    icon: const Icon(Icons.person, size: 18),
                                    label: const Text('Personal'),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: _perfilDatos ==
                                              AppDataProfile.personal
                                          ? colorScheme.primaryContainer
                                          : null,
                                      foregroundColor: _perfilDatos ==
                                              AppDataProfile.personal
                                          ? colorScheme.onPrimaryContainer
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _cambiarPerfilDatos(AppDataProfile.demo),
                                    icon: const Icon(Icons.visibility, size: 18),
                                    label: const Text('Demo'),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: _perfilDatos ==
                                              AppDataProfile.demo
                                          ? colorScheme.primaryContainer
                                          : null,
                                      foregroundColor: _perfilDatos ==
                                              AppDataProfile.demo
                                          ? colorScheme.onPrimaryContainer
                                          : null,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 420;
                    final refreshBtn = TextButton.icon(
                      onPressed: _refrescandoLicencia
                          ? null
                          : _refrescarEstadoLicenciaManual,
                      icon: _refrescandoLicencia
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 18),
                      label: Text(
                          _refrescandoLicencia ? 'Refrescando...' : 'Refrescar'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSubSectionHeader('Licencia', colorScheme),
                          Align(
                            alignment: Alignment.centerRight,
                            child: refreshBtn,
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _buildSubSectionHeader(
                              'Licencia', colorScheme),
                        ),
                        refreshBtn,
                      ],
                    );
                  },
                ),
                Container(
                  decoration: _modernContainerDecoration(colorScheme),
                  child: _buildModernInfoItem(
                    context: context,
                    icon: Icons.key_rounded,
                    color: Colors.deepPurple,
                    title: 'Licencia: $_licenciaEstado',
                    subtitle: _licenciaDetalle,
                  ),
                ),
                const SizedBox(height: 8),
                _buildSubSectionHeader('Qué incluye cada plan', colorScheme),
                Container(
                  decoration: _modernContainerDecoration(colorScheme),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plan actual: ${_permissions.currentPlanLabel(_licenciaActual?.plan)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Entrenamiento: solo modo entrenamiento.',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Competición: entrenamiento + competición (sin análisis avanzado).',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Competición Plus: añade análisis, copias y catálogos.',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Completo: todo lo anterior + detección automática (en I+D Próximamente).',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),

                if (LicenseService.devPlanSelectorEnabled) ...[
                  const SizedBox(height: 16),
                  _buildSubSectionHeader('Modo desarrollo (simulación)', colorScheme),
                  Container(
                    decoration: _modernContainerDecoration(colorScheme),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Permite probar permisos sin activar cuenta real.',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _planDevSeleccionado,
                          decoration: InputDecoration(
                            labelText: 'Plan simulado',
                            labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: colorScheme.outlineVariant),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: colorScheme.outlineVariant),
                            ),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'basic', child: Text('Entrenamiento')),
                            DropdownMenuItem(value: 'medio', child: Text('Competición')),
                            DropdownMenuItem(value: 'pro', child: Text('Competición Plus')),
                            DropdownMenuItem(value: 'completo', child: Text('Completo')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _planDevSeleccionado = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _aplicarPlanDesarrollo,
                            icon: const Icon(Icons.science_rounded, size: 18),
                            label: const Text('Aplicar plan simulado'),
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.primaryContainer,
                              foregroundColor: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_ultimoUpgrade != null) ...[
                  const SizedBox(height: 16),
                  _buildSubSectionHeader('Última solicitud de mejora', colorScheme),
                  Container(
                    decoration: _modernContainerDecoration(colorScheme),
                    child: _buildModernInfoItem(
                      context: context,
                      icon: _ultimoUpgrade!.backendRegistered ? Icons.check_circle_rounded : Icons.mark_email_read_rounded,
                      color: _ultimoUpgrade!.backendRegistered ? Colors.green : Colors.orange,
                      title: '${_ultimoUpgrade!.requiredPlan} (${_ultimoUpgrade!.capability})\n${_ultimoUpgrade!.at.toString().split('.').first}',
                      subtitle: 'Plan actual: ${_ultimoUpgrade!.currentPlan}\n'
                          'Backend: ${_ultimoUpgrade!.backendRegistered ? 'registrado' : 'pendiente'} · '
                          'Email: ${_ultimoUpgrade!.emailOpened ? 'abierto' : 'no abierto'}\n'
                          '${_ultimoUpgrade!.message}',
                    ),
                  ),
                ],
                
                LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 420;
                    final cambiar = TextButton.icon(
                      onPressed: _solicitarAmpliacionDesdeHistorial,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: const Text('Cambiar plan'),
                      style: TextButton.styleFrom(
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    );
                    final historial = TextButton.icon(
                      onPressed: _mostrarHistorialUpgrade,
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('Historial'),
                      style: TextButton.styleFrom(
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    );
                    if (narrow) {
                      return Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 4,
                        runSpacing: 0,
                        children: [cambiar, historial],
                      );
                    }
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        cambiar,
                        const SizedBox(width: 4),
                        historial,
                      ],
                    );
                  },
                ),

                const SizedBox(height: 8),
                _buildSubSectionHeader('Actualizaciones', colorScheme),
                Container(
                  decoration: _modernContainerDecoration(colorScheme),
                  child: _buildModernMenuItem(
                    context: context,
                    icon: Icons.system_update_alt_rounded,
                    color: Colors.deepPurple,
                    title: _comprobandoActualizacion ? 'Buscando actualización...' : 'Buscar actualizaciones',
                    subtitle: 'Consulta versión remota y actualiza.',
                    onTap: _buscarActualizacionesManual,
                  ),
                ),

                const SizedBox(height: 16),
                _buildSubSectionHeader('Información técnica', colorScheme),
                Container(
                  decoration: _modernContainerDecoration(colorScheme),
                  child: _cargandoInfo
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                              ),
                              const SizedBox(width: 16),
                              Text('Cargando versiones...', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            _buildTechInfoItem(
                              context: context,
                              icon: Icons.phone_android_rounded,
                              color: Colors.indigo,
                              title: 'Versión App',
                              subtitle: '$_appVersion+$_appBuild',
                            ),
                            _buildDivider(colorScheme),
                            _buildTechInfoItem(
                              context: context,
                              icon: Icons.storage_rounded,
                              color: Colors.indigo,
                              title: 'Versión Base de Datos',
                              subtitle: 'Actual: ${dbReal ?? '-'} | Esperada: $dbEsperada',
                              trailingIcon: migracionOk ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                              trailingColor: migracionOk ? Colors.green : Colors.orange,
                            ),
                            _buildDivider(colorScheme),
                            _buildTechInfoItem(
                              context: context,
                              icon: Icons.verified_user_rounded,
                              color: Colors.indigo,
                              title: 'Estado de Migración',
                              subtitle: migracionOk ? 'OK' : 'Pendiente o parcial',
                            ),
                            _buildDivider(colorScheme),
                            _buildTechInfoItem(
                              context: context,
                              icon: Icons.folder_rounded,
                              color: Colors.indigo,
                              title: 'Ruta BD',
                              subtitle: _dbPath,
                            ),
                          ],
                        ),
                ),

              ]),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _modernContainerDecoration(ColorScheme colorScheme) {
    return BoxDecoration(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _buildDivider(ColorScheme colorScheme) {
    return Divider(
      height: 1, 
      indent: 52, 
      color: colorScheme.outlineVariant.withValues(alpha: 0.5)
    );
  }

  Widget _buildModernSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: colorScheme.primary,
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  Widget _buildSubSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildModernMenuItem({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    bool locked = false,
    String? lockPlanLabel,
  }) {
    final lockColor = LicenseUiHelper.lockColorForPlan(lockPlanLabel);
    final themeInfo = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: locked ? themeInfo.onSurface.withValues(alpha: 0.6) : themeInfo.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: themeInfo.onSurfaceVariant,
                      height: 1.2,
                    ),
                  )
                ],
              ),
            ),
            if (locked && lockPlanLabel != null)
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  margin: const EdgeInsets.only(right: 8, left: 4),
                  decoration: BoxDecoration(
                    color: lockColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 12, color: lockColor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          lockPlanLabel.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: lockColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: themeInfo.onSurface.withValues(alpha: 0.3),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernInfoItem({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final themeInfo = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: themeInfo.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: themeInfo.onSurfaceVariant,
                    height: 1.3,
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechInfoItem({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    IconData? trailingIcon,
    Color? trailingColor,
  }) {
    final themeInfo = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: themeInfo.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: themeInfo.onSurfaceVariant,
                  ),
                )
              ],
            ),
          ),
          if (trailingIcon != null)
            Icon(trailingIcon, size: 18, color: trailingColor),
        ],
      ),
    );
  }
}
