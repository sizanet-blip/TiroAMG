import 'dart:math'; 
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
// Ocultamos DateTimeRange del servicio para evitar conflictos
import '../services/estadisticas_service.dart' hide DateTimeRange;
import '../services/equipo_service.dart';
import '../services/catalogo_service.dart';
import '../models/equipo_model.dart';
import '../models/tipo_diana_model.dart';
import '../models/disparo_model.dart';

class EstadisticasScreen extends StatefulWidget {
  final int modo; 
  final List<int>? idsSesionFijos; // ¡NUEVO! Para venir directo desde el detalle

  const EstadisticasScreen({
    super.key, 
    required this.modo,
    this.idsSesionFijos,
  });

  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen> {
  final _statsService = EstadisticasService();
  final _equipoService = EquipoService();
  final _catalogoService = CatalogoService();

  List<EquipoDetalle> _equipos = [];
  List<TipoDiana> _dianas = [];

  int _filtroFechaSeleccionado = 0; 
  DateTimeRange? _rangoFechasManual; 
  
  EquipoDetalle? _equipoSel;
  TipoDiana? _dianaSel;
  bool _filtrosAbiertos = true; 
  bool _cargando = true;

  List<Map<String, dynamic>> _datosProgreso = [];
  AnalisisAgrupacion? _analisis;

  // Propiedad para saber si estamos en modo detalle (con IDs fijos)
  bool get _esModoDetalle => widget.idsSesionFijos != null && widget.idsSesionFijos!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Si venimos en modo detalle, cerramos los filtros por defecto
    if (_esModoDetalle) _filtrosAbiertos = false;
    _cargarFiltrosIniciales();
  }

  void _cargarFiltrosIniciales() async {
    final e = await _equipoService.obtenerEquiposDetallados();
    final d = await _catalogoService.obtenerTiposDiana();
    
    if (mounted) {
      setState(() {
        _equipos = e;
        _dianas = d;
        if (d.isNotEmpty) _dianaSel = d.first; 
        if (e.isNotEmpty) _equipoSel = e.first;
      });
      _refrescarDatos();
    }
  }

  void _refrescarDatos() async {
    setState(() => _cargando = true);

    DateTimeRange? rangoCalculado;
    
    // Solo calculamos filtros de fecha si NO estamos en modo detalle
    if (!_esModoDetalle) {
        final now = DateTime.now();
        switch (_filtroFechaSeleccionado) {
          case 1: rangoCalculado = DateTimeRange(start: DateTime(now.year, now.month, 1), end: now); break;
          case 2: rangoCalculado = DateTimeRange(start: now.subtract(const Duration(days: 90)), end: now); break;
          case 3: rangoCalculado = DateTimeRange(start: DateTime(now.year, 1, 1), end: now); break;
          case 4: rangoCalculado = _rangoFechasManual; break;
          default: rangoCalculado = null; break;
        }
    }

    final progreso = await _statsService.obtenerEvolucionPuntos(
      rangoFechas: rangoCalculado,
      idEquipo: _equipoSel?.id,
      idTipoDiana: _dianaSel?.id,
      filtroModo: _esModoDetalle ? null : widget.modo, // Ignoramos modo si es detalle
      idsSesiones: widget.idsSesionFijos, // Pasamos los IDs específicos
    );

    final analisis = await _statsService.calcularAnalisisAgrupacion(
      rangoFechas: rangoCalculado,
      idEquipo: _equipoSel?.id,
      idTipoDiana: _dianaSel?.id,
      filtroModo: _esModoDetalle ? null : widget.modo,
      idsSesiones: widget.idsSesionFijos,
    );

    if (mounted) {
      setState(() {
        _datosProgreso = progreso;
        _analisis = analisis;
        _cargando = false;
      });
    }
  }

  void _seleccionarFechasManuales() async {
    final picked = await showDateRangePicker(
      context: context,
      locale: const Locale('es', 'ES'), 
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _rangoFechasManual,
      builder: (context, child) => Theme(data: ThemeData.light().copyWith(primaryColor: Colors.purple, colorScheme: const ColorScheme.light(primary: Colors.purple)), child: child!),
    );
    if (picked != null) {
      setState(() { _rangoFechasManual = picked; _filtroFechaSeleccionado = 4; });
      _refrescarDatos();
    } else {
      if (_filtroFechaSeleccionado == 4 && _rangoFechasManual == null) { setState(() => _filtroFechaSeleccionado = 0); _refrescarDatos(); }
    }
  }
  
  String _formatoCorto(DateTime fecha) => "${fecha.day}/${fecha.month}";

  @override
  Widget build(BuildContext context) {
    String titulo;
    if (_esModoDetalle) {
        titulo = 'Análisis de Sesión';
    } else {
        titulo = widget.modo == 2 ? 'Análisis Competiciones' : 'Análisis Entrenamientos';
    }

    return Scaffold(
      appBar: AppBar(title: Text(titulo), backgroundColor: Colors.purple),
      body: Column(
        children: [
          // SOLO MOSTRAMOS TARJETA DE FILTROS SI NO ES MODO DETALLE
          if (!_esModoDetalle)
          Card(
            margin: EdgeInsets.zero,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(15))),
            elevation: 4,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.filter_alt, color: Colors.purple),
                  title: const Text("Filtros de Análisis", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(_filtroFechaSeleccionado == 0 ? "Todo el historial" : "Filtros activos...", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  trailing: Icon(_filtrosAbiertos ? Icons.expand_less : Icons.expand_more, color: Colors.purple),
                  onTap: () => setState(() => _filtrosAbiertos = !_filtrosAbiertos),
                ),
                if (_filtrosAbiertos)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Periodo', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                          value: _filtroFechaSeleccionado,
                          items: [
                            const DropdownMenuItem(value: 0, child: Text('Todo', overflow: TextOverflow.ellipsis)),
                            const DropdownMenuItem(value: 1, child: Text('Este Mes', overflow: TextOverflow.ellipsis)),
                            const DropdownMenuItem(value: 2, child: Text('Últimos 3 Meses', overflow: TextOverflow.ellipsis)),
                            const DropdownMenuItem(value: 3, child: Text('Este Año', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 4, child: Text(_filtroFechaSeleccionado == 4 && _rangoFechasManual != null ? '${_formatoCorto(_rangoFechasManual!.start)} - ${_formatoCorto(_rangoFechasManual!.end)}' : 'Personalizado...', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) { if (v == 4) { _seleccionarFechasManuales(); } else { setState(() { _filtroFechaSeleccionado = v!; _refrescarDatos(); }); } },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<EquipoDetalle>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Arma (Necesaria para Clics)', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                          value: _equipoSel,
                          items: [const DropdownMenuItem(value: null, child: Text('Todas las armas')), ..._equipos.map((e) => DropdownMenuItem(value: e, child: Text(e.nombre, overflow: TextOverflow.ellipsis))).toList()],
                          onChanged: (v) => setState(() { _equipoSel = v; _refrescarDatos(); }),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<TipoDiana>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Tipo de Diana', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                          value: _dianaSel,
                          items: _dianas.map((d) => DropdownMenuItem(value: d, child: Text(d.nombre, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (v) => setState(() { _dianaSel = v; _refrescarDatos(); }),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  )
              ],
            ),
          ),
          
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    labelColor: Colors.purple,
                    indicatorColor: Colors.purple,
                    tabs: [
                      Tab(text: 'AGRUPACIÓN', icon: Icon(Icons.gps_fixed)),
                      Tab(text: 'EVOLUCIÓN', icon: Icon(Icons.show_chart)),
                    ],
                  ),
                  Expanded(
                    child: _cargando 
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        children: [
                          _buildMapaCalor(),
                          _buildGraficaProgreso(),
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
    if (_datosProgreso.isEmpty) return const Center(child: Text("No hay datos", style: TextStyle(color: Colors.grey)));
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
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: const TextStyle(fontSize: 10)))),
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
    // En modo detalle, si no hay diana seleccionada, intentamos adivinarla, pero si no, mostramos aviso
    if (_dianaSel == null && !_esModoDetalle) return const Center(child: Text("Selecciona un Tipo de Diana arriba\npara ver el mapa de calor."));
    if (_analisis == null || _analisis!.disparos.isEmpty) return const Center(child: Text("No hay impactos registrados."));

    String consejo = "Agrupación Centrada";
    IconData iconoConsejo = Icons.check_circle;
    Color colorConsejo = Colors.green;
    String detalleClics = "";

    double devX = _analisis!.mpi.x; 
    double devY = _analisis!.mpi.y; 
    
    double radioFisicoMm = 250.0; 
    if (_dianaSel != null && _dianaSel!.nombre.toLowerCase().contains("aire")) radioFisicoMm = 78.0;

    double mmX = devX * radioFisicoMm; 
    double mmY = devY * radioFisicoMm; 

    double valorClic = _equipoSel?.correccionClick ?? 0.0;
    
    if (valorClic > 0) {
      int clicsH = (mmX.abs() / valorClic).round();
      int clicsV = (mmY.abs() / valorClic).round();

      String dirH = mmX > 0 ? "Izquierda (L)" : "Derecha (R)"; 
      String dirV = mmY > 0 ? "Arriba (U)" : "Abajo (D)";      
      
      List<String> correcciones = [];
      if (clicsH > 0) correcciones.add("$clicsH clics $dirH");
      if (clicsV > 0) correcciones.add("$clicsV clics $dirV");
      
      if (correcciones.isNotEmpty) {
        consejo = "CORREGIR MIRAS";
        iconoConsejo = Icons.build_circle;
        colorConsejo = Colors.orange[800]!;
        detalleClics = correcciones.join("  y  ");
      }
    } else {
      String horiz = devX > 0.05 ? "IZQUIERDA" : (devX < -0.05 ? "DERECHA" : "");
      String vert = devY > 0.05 ? "ARRIBA" : (devY < -0.05 ? "ABAJO" : "");
      
      if (horiz != "" || vert != "") {
        consejo = "Mover miras hacia: $horiz $vert";
        detalleClics = "Configura los mm/clic de tu arma para ver el número exacto.";
        iconoConsejo = Icons.info_outline;
        colorConsejo = Colors.blue;
      }
    }

    double puntosPerdidos = _analisis!.puntuacionPotencialMedia - _analisis!.puntuacionRealMedia;
    
    // Config Diana: Si no hay seleccionada, usamos default seguro
    int vm = _dianaSel?.valorMinimo ?? 1;
    int an = _dianaSel?.anilloNegroInicio ?? 7;
    bool fn = _dianaSel?.esFondoNegro ?? false;
    bool tm = _dianaSel?.tieneMosca ?? true;
    bool tg = _dianaSel?.tieneGuias ?? false;
    bool ed = an <= 5;

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: colorConsejo.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: colorConsejo)),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(iconoConsejo, color: colorConsejo), const SizedBox(width: 10), Expanded(child: Text(consejo, style: TextStyle(fontWeight: FontWeight.bold, color: colorConsejo, fontSize: 16)))]),
                if (detalleClics.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(detalleClics, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 10),
                Text(puntosPerdidos > 0.5 ? "Pierdes ${puntosPerdidos.toStringAsFixed(1)} puntos de media por el desvío." : "Ajuste correcto.", style: const TextStyle(fontStyle: FontStyle.italic), textAlign: TextAlign.center),
                const Divider(),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_datoEstadistico("Media Real", _analisis!.puntuacionRealMedia.toStringAsFixed(2)), const Icon(Icons.arrow_forward, color: Colors.grey), _datoEstadistico("Media Potencial", _analisis!.puntuacionPotencialMedia.toStringAsFixed(2), esVerde: true)]),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  double diametro = constraints.maxWidth;
                  return CustomPaint(
                    painter: DianaPainter(
                      impactos: _convertirImpactosAPixeles(_analisis!.disparos, diametro/2),
                      valorMinimo: vm,
                      anilloNegroInicio: an,
                      esFondoNegro: fn,
                      tieneMosca: tm,
                      tieneGuias: tg,
                      esEstiloDuelo: ed,
                      centroGravedad: Offset((_analisis!.mpi.x * (diametro/2)) + (diametro/2), (_analisis!.mpi.y * (diametro/2)) + (diametro/2)),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text("${_analisis!.disparos.length} impactos analizados", style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _datoEstadistico(String label, String valor, {bool esVerde = false}) {
    return Column(children: [Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)), Text(valor, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: esVerde ? Colors.green[700] : Colors.black87))]);
  }

  List<Offset> _convertirImpactosAPixeles(List<Disparo> disparos, double radius) {
    return disparos.map((d) {
      return Offset((d.x * radius) + radius, (d.y * radius) + radius);
    }).toList();
  }
}

class DianaPainter extends CustomPainter {
  final List<Offset> impactos;
  final int valorMinimo;
  final int anilloNegroInicio;
  final bool esFondoNegro;
  final bool tieneMosca;
  final bool tieneGuias;
  final bool esEstiloDuelo;
  final Offset? centroGravedad;

  DianaPainter({
    required this.impactos,
    required this.valorMinimo,
    required this.anilloNegroInicio,
    required this.esFondoNegro,
    required this.tieneMosca,
    required this.tieneGuias,
    required this.esEstiloDuelo,
    this.centroGravedad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Fondo
    final paintFondo = Paint()..color = esFondoNegro ? const Color(0xFF1A1A1A) : Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paintFondo);

    int totalZonas = 11 - valorMinimo; 
    if (totalZonas < 1) totalZonas = 1;
    
    // VARIABLE QUE FALTABA: Declaramos el ancho de cada zona
    double anchoZona = radius / totalZonas; 

    final paintNegro = Paint()..color = Colors.black..style = PaintingStyle.fill;
    final paintLineaClara = Paint()..color = Colors.grey[400]!..style = PaintingStyle.stroke..strokeWidth = 1.0;
    final paintLineaBlanca = Paint()..color = Colors.white70..style = PaintingStyle.stroke..strokeWidth = 1.0;

    if (esEstiloDuelo) {
       double paso = radius / 6;
       for (int i = 0; i < 6; i++) {
          double r = radius - (i * paso);
          canvas.drawCircle(center, r, paintLineaBlanca);
          int numeroAnillo = 5 + i;
          if (numeroAnillo < 10) _dibujarNumeros4Ejes(canvas, numeroAnillo.toString(), center, r - (paso / 2), Colors.white);
       }
    } else {
       for (int i = 0; i < totalZonas; i++) {
          int numeroAnillo = valorMinimo + i;
          double r = radius - (i * (radius / totalZonas));
          
          if (numeroAnillo >= anilloNegroInicio) {
            canvas.drawCircle(center, r, paintNegro);
            canvas.drawCircle(center, r, paintLineaBlanca);
            if (numeroAnillo < 10) {
               // Ahora 'anchoZona' está definida y se puede usar
               _dibujarNumeros4Ejes(canvas, numeroAnillo.toString(), center, r - (anchoZona / 2), Colors.white);
            }
          } else {
            if (i > 0) canvas.drawCircle(center, r, esFondoNegro ? paintLineaBlanca : paintLineaClara);
            Color colorNum = esFondoNegro ? Colors.white : Colors.black;
            _dibujarNumeros4Ejes(canvas, numeroAnillo.toString(), center, r - (anchoZona / 2), colorNum);
          }
       }
    }

    if (tieneMosca) {
      double radioMosca = (radius / totalZonas) / 2;
      canvas.drawCircle(center, radioMosca, paintLineaBlanca);
    }
    
    if (tieneGuias) {
      Paint guia = Paint()..color = Colors.white..strokeWidth = 2.0;
      double largo = radius * 0.3;
      canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx - radius + largo, center.dy), guia);
      canvas.drawLine(Offset(center.dx + radius, center.dy), Offset(center.dx + radius - largo, center.dy), guia);
    }
    
    canvas.drawLine(Offset(center.dx - 4, center.dy), Offset(center.dx + 4, center.dy), Paint()..color = Colors.white..strokeWidth=1);
    canvas.drawLine(Offset(center.dx, center.dy - 4), Offset(center.dx, center.dy + 4), Paint()..color = Colors.white..strokeWidth=1);

    final paintImpacto = Paint()..color = Colors.greenAccent.withOpacity(0.6)..style = PaintingStyle.fill;
    double tamano = (radius * 0.04) * (10 / totalZonas);
    for(var p in impactos) {
       canvas.drawCircle(p, tamano, paintImpacto);
    }

    if (centroGravedad != null) {
      final paintMPI = Paint()..color = Colors.redAccent..style = PaintingStyle.stroke..strokeWidth = 3.0;
      double sizeCruz = 10.0;
      canvas.drawLine(Offset(centroGravedad!.dx - sizeCruz, centroGravedad!.dy), Offset(centroGravedad!.dx + sizeCruz, centroGravedad!.dy), paintMPI);
      canvas.drawLine(Offset(centroGravedad!.dx, centroGravedad!.dy - sizeCruz), Offset(centroGravedad!.dx, centroGravedad!.dy + sizeCruz), paintMPI);
      canvas.drawCircle(centroGravedad!, sizeCruz / 1.5, paintMPI);
    }
  }

  void _dibujarNumeros4Ejes(Canvas canvas, String texto, Offset center, double dist, Color color) {
    _texto(canvas, texto, Offset(center.dx, center.dy - dist), color);
    _texto(canvas, texto, Offset(center.dx, center.dy + dist), color);
    _texto(canvas, texto, Offset(center.dx + dist, center.dy), color);
    _texto(canvas, texto, Offset(center.dx - dist, center.dy), color);
  }

  void _texto(Canvas canvas, String texto, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: texto, 
        style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold) 
      ),
      textDirection: TextDirection.ltr
    );
    tp.layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant DianaPainter oldDelegate) => true;
}