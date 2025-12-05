import 'package:flutter/material.dart';
import '../models/sesion_model.dart';
import '../services/entrenamiento_service.dart';
import 'sesion_detalle_screen.dart';
import 'competicion_historial_detalle_screen.dart';
// Asegúrate de que el nombre del archivo de estadísticas coincida con el que tienes
import 'estadisticas_screen.dart'; 

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

  String _formatoFecha(DateTime fecha) => "${fecha.day}/${fecha.month}/${fecha.year}";
  
  String _formatoCorto(DateTime fecha) => "${fecha.day}/${fecha.month}";
  
  String _obtenerMes(int mes) {
    const meses = ['ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', 'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'];
    return meses[mes - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Historial'),
        backgroundColor: Colors.indigo,
        actions: [
          // Botón de Estadísticas contextual
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: _tabController.index == 0 ? "Estadísticas Entrenamientos" : "Estadísticas Competiciones",
            onPressed: () {
              int modo = _tabController.index == 0 ? 1 : 2; 
              Navigator.push(
                context, 
                MaterialPageRoute(builder: (_) => EstadisticasScreen(modo: modo))
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.amber,
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
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              children: [
                Icon(
                  _filtroSeleccionado == 5 ? Icons.date_range : Icons.filter_list, 
                  color: Colors.indigo, 
                  size: 24
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButton<int>(
                    value: _filtroSeleccionado,
                    isExpanded: true,
                    underline: Container(height: 2, color: Colors.indigo.withOpacity(0.2)),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.indigo),
                    style: const TextStyle(color: Colors.black87, fontSize: 16),
                    
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
                      const DropdownMenuItem(value: 1, child: Text('Hoy')), // ¡NUEVO!
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
    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              esCompe ? Icons.emoji_events_outlined : Icons.sports_baseball_outlined, 
              size: 60, 
              color: Colors.grey[300]
            ),
            const SizedBox(height: 10),
            Text(
              'No hay registros para este filtro', 
              style: TextStyle(color: Colors.grey[400])
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: lista.length,
      itemBuilder: (context, index) {
        final item = lista[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
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
                  // FECHA
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: esCompe ? Colors.amber[50] : Colors.teal[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: esCompe ? Colors.amber.withOpacity(0.3) : Colors.teal.withOpacity(0.3))
                    ),
                    child: Column(
                      children: [
                        Text("${item.fecha.day}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: esCompe ? Colors.amber[900] : Colors.teal[900])),
                        Text(_obtenerMes(item.fecha.month), style: TextStyle(fontSize: 12, color: esCompe ? Colors.amber[900] : Colors.teal[900])),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // INFO
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.nombreTitulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(item.nombreEquipo, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                        if (!esCompe && item.nota != null) 
                           Text(
                             item.nota!.replaceAll('Torneo: ', ''), 
                             style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.blueGrey),
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
                          color: esCompe ? Colors.amber[800] : Colors.teal[800]
                        )
                      ),
                      if (item.totalMoscas > 0) Text('${item.totalMoscas}x', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                    ],
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