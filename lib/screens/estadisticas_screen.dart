import 'dart:math'; // Para el Point
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
// Ocultamos DateTimeRange del servicio para evitar conflictos con el de Flutter
import '../services/estadisticas_service.dart' hide DateTimeRange;
import '../services/equipo_service.dart';
import '../services/catalogo_service.dart';
import '../models/equipo_model.dart';
import '../models/tipo_diana_model.dart';
import '../models/disparo_model.dart';
import '../widgets/diana_painter.dart';

class EstadisticasScreen extends StatefulWidget {
  // Recibimos el modo inicial, pero luego puede cambiar
  final int modo; // 1: Entrenamientos, 2: Competiciones

  const EstadisticasScreen({super.key, required this.modo});

  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen> {
  final _statsService = EstadisticasService();
  final _equipoService = EquipoService();
  final _catalogoService = CatalogoService();

  // Listas para filtros
  List<EquipoDetalle> _equipos = [];
  List<TipoDiana> _dianas = [];

  // ESTADO DE FILTROS
  int _filtroFechaSeleccionado = 0; 
  DateTimeRange? _rangoFechasManual;
  
  EquipoDetalle? _equipoSel;
  TipoDiana? _dianaSel;
  late int _modoSel; // Lo inicializamos en el initState

  // Control manual del acordeón
  bool _filtrosAbiertos = true; 

  // DATOS
  List<Map<String, dynamic>> _datosProgreso = [];
  List<Disparo> _datosMapa = [];
  Point<double>? _centroGravedad; // MPI
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    // 1. Inicializamos el modo con lo que nos pasan, pero luego es editable
    _modoSel = widget.modo;
    _cargarFiltrosIniciales();
  }

  void _cargarFiltrosIniciales() async {
    final e = await _equipoService.obtenerEquiposDetallados();
    final d = await _catalogoService.obtenerTiposDiana();
    
    if (mounted) {
      setState(() {
        _equipos = e;
        _dianas = d;
        // NO seleccionamos diana por defecto para permitir ver "Todas" al principio
        _dianaSel = null; 
      });
      _refrescarDatos();
    }
  }

  void _refrescarDatos() async {
    setState(() => _cargando = true);

    // Calcular Rango de Fechas
    DateTimeRange? rangoCalculado;
    final now = DateTime.now();

    switch (_filtroFechaSeleccionado) {
      case 1: // Este Mes
        rangoCalculado = DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
        break;
      case 2: // Últimos 3 Meses
        rangoCalculado = DateTimeRange(start: now.subtract(const Duration(days: 90)), end: now);
        break;
      case 3: // Este Año
        rangoCalculado = DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
        break;
      case 4: // Personalizado
        rangoCalculado = _rangoFechasManual;
        break;
      case 0: // Todo
      default:
        rangoCalculado = null;
        break;
    }

    // 2. Llamar al servicio (Usando _modoSel corregido)
    final progreso = await _statsService.obtenerEvolucionPuntos(
      rangoFechas: rangoCalculado,
      idEquipo: _equipoSel?.id,
      idTipoDiana: _dianaSel?.id, // Si es null, trae todas
      filtroModo: _modoSel == 0 ? null : _modoSel, // 0 = Todo
    );

    final analisis = await _statsService.obtenerAnalisisImpactos(
      rangoFechas: rangoCalculado,
      idEquipo: _equipoSel?.id,
      idTipoDiana: _dianaSel?.id,
      filtroModo: _modoSel == 0 ? null : _modoSel,
    );

    if (mounted) {
      setState(() {
        _datosProgreso = progreso;
        _datosMapa = analisis.disparos;
        _centroGravedad = analisis.centroGravedad;
        _cargando = false;
      });
    }
  }

  void _seleccionarFechasManuales() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _rangoFechasManual,
    );
    
    if (picked != null) {
      setState(() {
        _rangoFechasManual = picked;
        _filtroFechaSeleccionado = 4;
      });
      _refrescarDatos();
    } else {
      if (_filtroFechaSeleccionado == 4 && _rangoFechasManual == null) {
        setState(() => _filtroFechaSeleccionado = 0);
        _refrescarDatos(); 
      }
    }
  }
  
  String _formatoCorto(DateTime fecha) => "${fecha.day}/${fecha.month}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Análisis y Estadísticas'), backgroundColor: Colors.purple),
      body: Column(
        children: [
          // --- PANEL DE FILTROS ---
          Card(
            margin: EdgeInsets.zero,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(15))),
            elevation: 4,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.filter_alt, color: Colors.purple),
                  title: const Text("Filtros", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    _filtroFechaSeleccionado == 0 ? "Mostrando todo el historial" : "Filtros aplicados",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  trailing: Icon(_filtrosAbiertos ? Icons.expand_less : Icons.expand_more, color: Colors.purple),
                  onTap: () => setState(() => _filtrosAbiertos = !_filtrosAbiertos),
                ),
                
                if (_filtrosAbiertos)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        // 1. Periodo y Modo
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<int>(
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Periodo', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0)),
                                value: _filtroFechaSeleccionado,
                                items: [
                                  const DropdownMenuItem(value: 0, child: Text('Todo', overflow: TextOverflow.ellipsis)),
                                  const DropdownMenuItem(value: 1, child: Text('Este Mes', overflow: TextOverflow.ellipsis)),
                                  const DropdownMenuItem(value: 2, child: Text('Últimos 3 Meses', overflow: TextOverflow.ellipsis)),
                                  const DropdownMenuItem(value: 3, child: Text('Este Año', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(
                                    value: 4, 
                                    child: Text(
                                      _filtroFechaSeleccionado == 4 && _rangoFechasManual != null
                                          ? '${_formatoCorto(_rangoFechasManual!.start)} - ${_formatoCorto(_rangoFechasManual!.end)}'
                                          : 'Personalizado...',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v == 4) {
                                    _seleccionarFechasManuales();
                                  } else {
                                    setState(() {
                                      _filtroFechaSeleccionado = v!;
                                      _refrescarDatos();
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Modo', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0)),
                                value: _modoSel,
                                items: const [
                                  DropdownMenuItem(value: 0, child: Text('Todo', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(value: 1, child: Text('Entrenos', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(value: 2, child: Text('Compes', overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (v) => setState(() { _modoSel = v!; _refrescarDatos(); }),
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 10),
                        
                        // 2. Arma
                        DropdownButtonFormField<EquipoDetalle>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Arma', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0)),
                          value: _equipoSel,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Todas las armas')),
                            ..._equipos.map((e) => DropdownMenuItem(value: e, child: Text(e.nombre, overflow: TextOverflow.ellipsis))).toList(),
                          ],
                          onChanged: (v) => setState(() { _equipoSel = v; _refrescarDatos(); }),
                        ),
                        const SizedBox(height: 10),
                        
                        // 3. Diana
                        DropdownButtonFormField<TipoDiana>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Tipo de Diana', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0)),
                          value: _dianaSel,
                          items: [
                             // OPCIÓN IMPORTANTE: Permite ver gráfica general
                             const DropdownMenuItem(value: null, child: Text('Todas (Solo Evolución)')),
                             ..._dianas.map((d) => DropdownMenuItem(value: d, child: Text(d.nombre, overflow: TextOverflow.ellipsis))).toList()
                          ],
                          onChanged: (v) => setState(() { _dianaSel = v; _refrescarDatos(); }),
                        ),
                      ],
                    ),
                  )
              ],
            ),
          ),

          // --- CONTENIDO ---
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    labelColor: Colors.purple,
                    indicatorColor: Colors.purple,
                    tabs: [
                      Tab(text: 'EVOLUCIÓN', icon: Icon(Icons.show_chart)),
                      Tab(text: 'AGRUPACIÓN', icon: Icon(Icons.gps_fixed)),
                    ],
                  ),
                  Expanded(
                    child: _cargando 
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        children: [
                          _buildGraficaProgreso(),
                          _buildMapaCalor(),
                        ],
                      ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraficaProgreso() {
    if (_datosProgreso.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.bar_chart, size: 50, color: Colors.grey),
            SizedBox(height: 10),
            Text("No hay datos suficientes para la gráfica", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    
    List<FlSpot> puntos = [];
    for (int i = 0; i < _datosProgreso.length; i++) {
      puntos.add(FlSpot(i.toDouble(), (_datosProgreso[i]['total'] as num).toDouble()));
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 10)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), 
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey[300]!)),
          lineBarsData: [
            LineChartBarData(
              spots: puntos,
              isCurved: true,
              color: Colors.purple,
              barWidth: 3,
              dotData: FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: Colors.purple.withOpacity(0.1)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapaCalor() {
    if (_datosMapa.isEmpty) return const Center(child: Text("No hay impactos registrados con estos filtros."));
    
    // Si no hay diana seleccionada, no podemos pintar el mapa correctamente
    if (_dianaSel == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.adjust, size: 50, color: Colors.orange),
            SizedBox(height: 10),
            Text("Selecciona un 'Tipo de Diana' arriba", style: TextStyle(fontWeight: FontWeight.bold)),
            Text("para ver la agrupación correcta.", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    String consejo = "";
    if (_centroGravedad != null) {
      double devX = _centroGravedad!.x;
      double devY = _centroGravedad!.y;
      
      String horiz = devX > 0.05 ? "IZQUIERDA" : (devX < -0.05 ? "DERECHA" : "CENTRADO");
      String vert = devY > 0.05 ? "ARRIBA" : (devY < -0.05 ? "ABAJO" : "CENTRADO");
      
      if (horiz != "CENTRADO" || vert != "CENTRADO") {
        consejo = "CORRECCIÓN: Mover miras a $horiz y $vert";
      } else {
        consejo = "¡Agrupación Centrada!";
      }
    }

    return Column(
      children: [
        if (consejo.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            color: Colors.amber[100],
            width: double.infinity,
            child: Text(consejo, textAlign: TextAlign.center, style: TextStyle(color: Colors.amber[900], fontWeight: FontWeight.bold)),
          ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  double diametro = min(constraints.maxWidth, constraints.maxHeight);
                  return SizedBox(
                    width: diametro,
                    height: diametro,
                    child: CustomPaint(
                      painter: DianaPainter(
                        impactos: _convertirImpactosAPixeles(_datosMapa, diametro/2),
                        valorMinimo: _dianaSel!.valorMinimo,
                        anilloNegroInicio: _dianaSel!.anilloNegroInicio,
                        esFondoNegro: _dianaSel!.esFondoNegro,
                        tieneMosca: _dianaSel!.tieneMosca,
                        tieneGuias: _dianaSel!.tieneGuias,
                        esEstiloDuelo: _dianaSel!.anilloNegroInicio <= 5,
                        centroGravedad: _centroGravedad != null 
                            ? Offset((_centroGravedad!.x * (diametro/2)) + (diametro/2), (_centroGravedad!.y * (diametro/2)) + (diametro/2))
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text("Visualizando ${_datosMapa.length} impactos", style: const TextStyle(color: Colors.grey)),
        )
      ],
    );
  }

  List<Offset> _convertirImpactosAPixeles(List<Disparo> disparos, double radius) {
    return disparos.map((d) {
      return Offset(
        (d.x * radius) + radius,
        (d.y * radius) + radius
      );
    }).toList();
  }
}