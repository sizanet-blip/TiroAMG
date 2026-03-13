import 'package:flutter/material.dart';
import '../models/sesion_model.dart';
import '../services/entrenamiento_service.dart';
import 'sesion_detalle_screen.dart';
import 'competicion_historial_detalle_screen.dart';
// Asegúrate de que el nombre del archivo de estadísticas coincida con el que tienes
import 'estadisticas_screen.dart'; 
import '../services/license_permissions_service.dart';
import '../utils/license_ui_helper.dart';

class HistorialScreen extends StatefulWidget {
  final bool puedeVerEstadisticas;
  final bool puedeVerCompeticiones;
  final String requiredPlanEstadisticas;

  const HistorialScreen({
    super.key,
    required this.puedeVerEstadisticas,
    this.puedeVerCompeticiones = true,
    this.requiredPlanEstadisticas = 'Medio',
  });

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> with SingleTickerProviderStateMixin {
  final _service = EntrenamientoService();
  final LicensePermissionsService _permissions = const LicensePermissionsService();
  
  // Listas completas (Datos brutos)
  List<SesionResumen> _entrenamientosRaw = [];
  List<SesionResumen> _competicionesRaw = [];
  
  // Listas filtradas (Lo que se ve)
  List<SesionResumen> _entrenamientosFiltrados = [];
  List<SesionResumen> _competicionesFiltradas = [];

  bool _cargando = true;
  late TabController _tabController;

  // Control de Filtros
  // 0: Todo, 1: Hoy, 2: Este Mes, 3: 3 Meses, 4: Este Año, 5: Custom
  int _filtroSeleccionado = 0;
  DateTimeRange? _rangoSeleccionado;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.puedeVerCompeticiones ? 2 : 1,
      vsync: this,
    );
    // Refrescar UI al cambiar pestaña para actualizar el botón de estadísticas
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) setState(() {});
    });
    _cargarDatos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _cargarDatos() async {
    final entrenos = await _service.obtenerEntrenamientos();
    final compes = await _service.obtenerCompeticionesAgrupadas();
    
    if (mounted) {
      setState(() {
        _entrenamientosRaw = entrenos;
        _competicionesRaw = compes;
        _aplicarFiltros();
        _cargando = false;
      });
    }
  }

  // Lógica de filtrado
  void _aplicarFiltros() {
    final now = DateTime.now();
    bool Function(SesionResumen) filtroFecha;

    switch (_filtroSeleccionado) {
      case 1: // Hoy (¡NUEVO!)
        filtroFecha = (s) => s.fecha.day == now.day && s.fecha.month == now.month && s.fecha.year == now.year;
        break;
      case 2: // Este Mes
        filtroFecha = (s) => s.fecha.month == now.month && s.fecha.year == now.year;
        break;
      case 3: // Últimos 3 Meses
        final limite = now.subtract(const Duration(days: 90));
        filtroFecha = (s) => s.fecha.isAfter(limite);
        break;
      case 4: // Este Año
        filtroFecha = (s) => s.fecha.year == now.year;
        break;
      case 5: // Rango Personalizado
        if (_rangoSeleccionado != null) {
          final finAjustado = DateTime(_rangoSeleccionado!.end.year, _rangoSeleccionado!.end.month, _rangoSeleccionado!.end.day, 23, 59, 59);
          filtroFecha = (s) => s.fecha.isAfter(_rangoSeleccionado!.start.subtract(const Duration(seconds: 1))) && 
                               s.fecha.isBefore(finAjustado);
        } else {
          filtroFecha = (s) => true;
        }
        break;
      case 0: // Todo
      default:
        filtroFecha = (s) => true;
        break;
    }

    setState(() {
      _entrenamientosFiltrados = _entrenamientosRaw.where(filtroFecha).toList();
      _competicionesFiltradas = _competicionesRaw.where(filtroFecha).toList();
    });
  }

  Future<void> _seleccionarRango() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _rangoSeleccionado,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: Colors.indigo,
            colorScheme: const ColorScheme.light(primary: Colors.indigo),
            buttonTheme: const ButtonThemeData(textTheme: ButtonTextTheme.primary),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _rangoSeleccionado = picked;
        _filtroSeleccionado = 5; // Modo Custom
        _aplicarFiltros();
      });
    } else {
      if (_filtroSeleccionado == 5 && _rangoSeleccionado == null) {
        setState(() {
          _filtroSeleccionado = 0;
          _aplicarFiltros();
        });
      }
    }
  }

  void _borrarItem(SesionResumen item, bool esCompe) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(esCompe ? 'Borrar Torneo' : 'Borrar Entrenamiento'),
        content: const Text('¿Estás seguro? Se borrarán todos los datos asociados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              if (esCompe) {
                await _service.borrarTorneoDeFecha(item.id, item.fecha);
              } else {
                await _service.borrarSesion(item.id);
              }
              _cargarDatos();
            },
            child: const Text('Borrar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatoCorto(DateTime fecha) => "${fecha.day}/${fecha.month}";
  
  String _obtenerMes(int mes) {
    const meses = ['ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', 'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'];
    return meses[mes - 1];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Historial', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          if (widget.puedeVerEstadisticas)
            IconButton(
              icon: const Icon(Icons.bar_chart_rounded),
              tooltip: (widget.puedeVerCompeticiones && _tabController.index == 1)
                  ? "Estadísticas Competiciones"
                  : "Estadísticas Entrenamientos",
              onPressed: () {
                final modo = (widget.puedeVerCompeticiones && _tabController.index == 1)
                    ? 2
                    : 1;
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => EstadisticasScreen(modo: modo)),
                );
              },
            ),
          if (!widget.puedeVerEstadisticas)
            IconButton(
              icon: Icon(Icons.lock_rounded, color: Colors.orange.shade700),
              tooltip: LicenseUiHelper.blockedTooltip(
                permissions: _permissions,
                capability: LicenseCapability.analytics,
              ),
              onPressed: () {
                LicenseUiHelper.showBlockedSnackBar(
                  context: context,
                  permissions: _permissions,
                  licencia: null,
                  capability: LicenseCapability.analytics,
                );
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          indicatorColor: colorScheme.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
          dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.5),
          tabs: [
            const Tab(text: 'ENTRENOS', icon: Icon(Icons.sports_baseball_rounded)),
            if (widget.puedeVerCompeticiones)
              const Tab(text: 'COMPETICIÓN', icon: Icon(Icons.emoji_events_rounded)),
          ],
        ),
      ),
      body: Column(
        children: [
          // --- BARRA DE FILTROS ---
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(
                  _filtroSeleccionado == 5 ? Icons.date_range_rounded : Icons.filter_list_rounded, 
                  color: colorScheme.primary, 
                  size: 20
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _filtroSeleccionado,
                      isExpanded: true,
                      icon: Icon(Icons.expand_more_rounded, color: colorScheme.primary),
                      style: TextStyle(color: colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w500),
                      dropdownColor: colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                      onChanged: (int? newValue) {
                        if (newValue == 5) {
                          _seleccionarRango();
                        } else if (newValue != null) {
                          setState(() {
                            _filtroSeleccionado = newValue;
                            _rangoSeleccionado = null;
                            _aplicarFiltros();
                          });
                        }
                      },
                      items: [
                        const DropdownMenuItem(value: 0, child: Text('Todos los registros')),
                        const DropdownMenuItem(value: 1, child: Text('Solo de hoy')),
                        const DropdownMenuItem(value: 2, child: Text('Este mes actual')),
                        const DropdownMenuItem(value: 3, child: Text('Últimos 90 días')),
                        const DropdownMenuItem(value: 4, child: Text('Este año completo')),
                        DropdownMenuItem(
                          value: 5, 
                          child: Text(
                            _filtroSeleccionado == 5 && _rangoSeleccionado != null
                                ? '${_formatoCorto(_rangoSeleccionado!.start)} a ${_formatoCorto(_rangoSeleccionado!.end)}'
                                : 'Elegir fechas personalizadas...'
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // --- LISTAS ---
          Expanded(
            child: _cargando
              ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _construirLista(_entrenamientosFiltrados, false, colorScheme, isDark),
                    if (widget.puedeVerCompeticiones)
                      _construirLista(_competicionesFiltradas, true, colorScheme, isDark),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _construirLista(List<SesionResumen> lista, bool esCompe, ColorScheme colorScheme, bool isDark) {
    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                esCompe ? Icons.emoji_events_rounded : Icons.sports_baseball_rounded, 
                size: 64, 
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Aún no hay registros aquí', 
              style: TextStyle(
                color: colorScheme.onSurfaceVariant, 
                fontSize: 18, 
                fontWeight: FontWeight.bold
              )
            ),
            const SizedBox(height: 8),
            Text(
              'Cambia el filtro temporal o empieza una sesión.', 
              style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8))
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: lista.length,
      itemBuilder: (context, index) {
        final item = lista[index];
        final cardColor = esCompe 
            ? (isDark ? Colors.amber.withValues(alpha: 0.1) : Colors.amber.withValues(alpha: 0.05))
            : colorScheme.surfaceContainer;
        
        final iconColor = esCompe ? Colors.amber.shade700 : Colors.teal.shade600;
        final dateBgColor = esCompe 
            ? Colors.amber.withValues(alpha: isDark ? 0.2 : 0.15)
            : Colors.teal.withValues(alpha: isDark ? 0.2 : 0.1);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: esCompe 
                  ? Colors.amber.withValues(alpha: 0.3) 
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
               if (esCompe) {
                 Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (_) => CompeticionHistorialDetalleScreen(
                        idModalidad: item.id, 
                        fecha: item.fecha,
                        nombreTorneo: item.nombreTitulo,
                        totalPuntos: item.totalPuntos,
                    ))
                 );
               } else {
                 Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (_) => SesionDetalleScreen(sesionId: item.id))
                 );
               }
            },
            onLongPress: () => _borrarItem(item, esCompe),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  // CUADRO DE FECHA
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: dateBgColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: esCompe ? Colors.amber.withValues(alpha: 0.4) : Colors.teal.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("${item.fecha.day}", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.1, color: iconColor)),
                        Text(_obtenerMes(item.fecha.month), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: iconColor)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // INFO CENTRAL
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.nombreTitulo, 
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurface)
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.nombreEquipo, 
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)
                        ),
                        if (item.marcaMunicion != null && item.marcaMunicion!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.deepOrange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${item.marcaMunicion}${(item.loteMunicion != null && item.loteMunicion!.isNotEmpty) ? ' · ${item.loteMunicion}' : ''}',
                              style: TextStyle(fontSize: 10, color: isDark ? Colors.orange.shade300 : Colors.deepOrange.shade700, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        if (!esCompe && item.nota != null) ...[
                           const SizedBox(height: 4),
                           Text(
                             item.nota!.replaceAll('Torneo: ', ''), 
                             style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                             maxLines: 1, overflow: TextOverflow.ellipsis
                           ),
                        ],
                      ],
                    ),
                  ),
                  
                  // PUNTOS Y MOSCAS
                  Container(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${item.totalPuntos}', 
                          style: TextStyle(
                            fontSize: 26, 
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1, 
                            color: iconColor
                          )
                        ),
                        if (item.totalMoscas > 0) 
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.onSurface.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.stars_rounded, size: 12, color: iconColor),
                                const SizedBox(width: 4),
                                Text('${item.totalMoscas}x', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}