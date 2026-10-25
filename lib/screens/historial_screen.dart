import 'package:flutter/material.dart';
import '../models/sesion_model.dart';
import '../services/entrenamiento_service.dart';
import '../theme/app_theme.dart';
import 'sesion_detalle_screen.dart';
import 'competicion_historial_detalle_screen.dart';
import 'estadisticas_screen.dart';
import '../widgets/tiro_amg_app_bar.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> with SingleTickerProviderStateMixin {
  final _service = EntrenamientoService();
  
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

  /// IDs de entrenamientos seleccionados para análisis.
  final Set<int> _entrenosSeleccionados = {};
  bool get _modoSeleccion => _entrenosSeleccionados.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          // Al salir de entrenamientos, limpia la selección.
          if (_tabController.index != 0) _entrenosSeleccionados.clear();
        });
      }
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
      // Quitar de la selección lo que ya no está visible.
      _entrenosSeleccionados.removeWhere(
        (id) => !_entrenamientosFiltrados.any((s) => s.id == id),
      );
    });
  }

  void _toggleSeleccionEntreno(int id) {
    setState(() {
      if (_entrenosSeleccionados.contains(id)) {
        _entrenosSeleccionados.remove(id);
      } else {
        _entrenosSeleccionados.add(id);
      }
    });
  }

  void _seleccionarTodosEntrenamientosVisibles() {
    setState(() {
      _entrenosSeleccionados
        ..clear()
        ..addAll(_entrenamientosFiltrados.map((s) => s.id));
    });
  }

  void _limpiarSeleccion() {
    setState(() => _entrenosSeleccionados.clear());
  }

  void _borrarSeleccionados() {
    final ids = _entrenosSeleccionados.toList();
    if (ids.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Borrar ${ids.length} entrenamiento${ids.length == 1 ? '' : 's'}'),
        content: const Text('¿Estás seguro? Se borrarán todos los datos asociados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentDanger),
            onPressed: () async {
              Navigator.pop(ctx);
              for (final id in ids) {
                await _service.borrarSesion(id);
              }
              _entrenosSeleccionados.clear();
              _cargarDatos();
            },
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
  }

  void _abrirEstadisticas() {
    final enEntrenamientos = _tabController.index == 0;
    if (enEntrenamientos && _entrenosSeleccionados.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EstadisticasScreen(
            modo: 1,
            idsSesionFijos: _entrenosSeleccionados.toList(),
          ),
        ),
      );
      return;
    }
    final modo = enEntrenamientos ? 1 : 2;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EstadisticasScreen(modo: modo)),
    );
  }

  Future<void> _seleccionarRango() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _rangoSeleccionado,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.primary,
            ),
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
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentDanger),
            onPressed: () async {
              Navigator.pop(ctx);
              if (esCompe) {
                await _service.borrarTorneoDeFecha(item.id, item.fecha);
              } else {
                await _service.borrarSesion(item.id);
              }
              _cargarDatos();
            },
            child: const Text('Borrar'),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: TiroAmgAppBar(
        section: 'Historial',
        title: _modoSeleccion && _tabController.index == 0
            ? Text('${_entrenosSeleccionados.length} seleccionados')
            : null,
        leading: _modoSeleccion && _tabController.index == 0
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancelar selección',
                onPressed: _limpiarSeleccion,
              )
            : null,
        actions: [
          if (_modoSeleccion && _tabController.index == 0) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Seleccionar todos los visibles',
              onPressed: _seleccionarTodosEntrenamientosVisibles,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Borrar selección',
              onPressed: _borrarSeleccionados,
            ),
            IconButton(
              icon: const Icon(Icons.bar_chart),
              tooltip: 'Analizar selección',
              onPressed: _abrirEstadisticas,
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.bar_chart),
              tooltip: _tabController.index == 0
                  ? 'Estadísticas Entrenamientos'
                  : 'Estadísticas Competiciones',
              onPressed: _abrirEstadisticas,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'ENTRENAMIENTOS', icon: Icon(Icons.sports_baseball)),
            Tab(text: 'COMPETICIONES', icon: Icon(Icons.emoji_events)),
          ],
        ),
      ),
      body: Column(
        children: [
          // --- BARRA DE FILTROS ---
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              children: [
                Icon(
                  _filtroSeleccionado == 5 ? Icons.date_range : Icons.filter_list, 
                  color: AppColors.primary, 
                  size: 24
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButton<int>(
                    value: _filtroSeleccionado,
                    isExpanded: true,
                    underline: Container(height: 2, color: AppColors.border),
                    icon: Icon(Icons.arrow_drop_down, color: AppColors.primary),
                    style: TextStyle(color: AppColors.title, fontSize: 16),
                    
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
                      const DropdownMenuItem(value: 0, child: Text('Mostrar Todo')),
                      const DropdownMenuItem(value: 1, child: Text('Hoy')),
                      const DropdownMenuItem(value: 2, child: Text('Este Mes')),
                      const DropdownMenuItem(value: 3, child: Text('Últimos 3 Meses')),
                      const DropdownMenuItem(value: 4, child: Text('Este Año')),
                      DropdownMenuItem(
                        value: 5, 
                        child: Text(
                          _filtroSeleccionado == 5 && _rangoSeleccionado != null
                              ? '${_formatoCorto(_rangoSeleccionado!.start)} - ${_formatoCorto(_rangoSeleccionado!.end)}'
                              : 'Rango Personalizado...'
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_tabController.index == 0 && !_modoSeleccion)
            Material(
              color: AppColors.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Mantén pulsado un entrenamiento para seleccionar varios y analizarlos juntos.',
                  style: TextStyle(fontSize: 12, color: AppColors.subtitle),
                ),
              ),
            ),
          if (_modoSeleccion && _tabController.index == 0)
            Material(
              color: AppColors.accentAnalytics.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: AppColors.accentAnalytics),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Toca para marcar/desmarcar. Estadísticas usará solo la selección.',
                        style: TextStyle(fontSize: 12, color: AppColors.title),
                      ),
                    ),
                    TextButton(
                      onPressed: _abrirEstadisticas,
                      child: const Text('Analizar'),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),

          // --- LISTAS ---
          Expanded(
            child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _construirLista(_entrenamientosFiltrados, false),
                    _construirLista(_competicionesFiltradas, true),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _construirLista(List<SesionResumen> lista, bool esCompe) {
    final accent = esCompe ? AppColors.accentCompetition : AppColors.accentTraining;

    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              esCompe ? Icons.emoji_events_outlined : Icons.sports_baseball_outlined, 
              size: 60, 
              color: AppColors.subtitleSoft,
            ),
            const SizedBox(height: 10),
            Text(
              'No hay registros para este filtro', 
              style: TextStyle(color: AppColors.subtitle),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: lista.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = lista[index];
        final seleccionado = !esCompe && _entrenosSeleccionados.contains(item.id);
        return Card(
          color: seleccionado
              ? AppColors.accentAnalytics.withValues(alpha: 0.08)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
            side: BorderSide(
              color: seleccionado
                  ? AppColors.accentAnalytics.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.card),
            onTap: () {
              if (!esCompe && _modoSeleccion) {
                _toggleSeleccionEntreno(item.id);
                return;
              }
              if (esCompe) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CompeticionHistorialDetalleScreen(
                      idModalidad: item.id,
                      fecha: item.fecha,
                      nombreTorneo: item.nombreTitulo,
                      totalPuntos: item.totalPuntos,
                    ),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SesionDetalleScreen(sesionId: item.id),
                  ),
                );
              }
            },
            onLongPress: () {
              if (esCompe) {
                _borrarItem(item, true);
                return;
              }
              // Entrenamientos: long-press inicia/cambia selección.
              _toggleSeleccionEntreno(item.id);
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  if (!esCompe && _modoSeleccion) ...[
                    Checkbox(
                      value: seleccionado,
                      onChanged: (_) => _toggleSeleccionEntreno(item.id),
                      activeColor: AppColors.accentAnalytics,
                    ),
                    const SizedBox(width: 4),
                  ],
                  // FECHA
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.iconBox),
                      border: Border.all(color: accent.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        Text("${item.fecha.day}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: accent)),
                        Text(_obtenerMes(item.fecha.month), style: TextStyle(fontSize: 12, color: accent)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // INFO
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.nombreTitulo, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.title)),
                        const SizedBox(height: 4),
                        Text(item.nombreEquipo, style: TextStyle(color: AppColors.subtitle, fontSize: 13)),
                        if (item.marcaMunicion != null && item.marcaMunicion!.isNotEmpty)
                          Text(
                            'Munición: ${item.marcaMunicion}${(item.loteMunicion != null && item.loteMunicion!.isNotEmpty) ? ' (${item.loteMunicion})' : ''}',
                            style: TextStyle(fontSize: 11, color: AppColors.subtitleSoft),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (!esCompe && item.nota != null) 
                           Text(
                             item.nota!.replaceAll('Torneo: ', ''), 
                             style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.subtitle),
                             maxLines: 1, overflow: TextOverflow.ellipsis
                           ),
                      ],
                    ),
                  ),
                  
                  // PUNTOS
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${item.totalPuntos}', 
                        style: TextStyle(
                          fontSize: 24, 
                          fontWeight: FontWeight.bold, 
                          color: accent,
                        )
                      ),
                      if (item.totalMoscas > 0) Text('${item.totalMoscas}x', style: TextStyle(fontSize: 12, color: AppColors.subtitle, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (!_modoSeleccion || esCompe)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: AppColors.subtitle),
                      onSelected: (v) {
                        if (v == 'borrar') _borrarItem(item, esCompe);
                        if (v == 'seleccionar' && !esCompe) {
                          _toggleSeleccionEntreno(item.id);
                        }
                      },
                      itemBuilder: (_) => [
                        if (!esCompe)
                          const PopupMenuItem(
                            value: 'seleccionar',
                            child: Text('Seleccionar'),
                          ),
                        const PopupMenuItem(
                          value: 'borrar',
                          child: Text('Borrar'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
