import 'dart:math'; 
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
// Ocultamos DateTimeRange del servicio para evitar conflictos
import '../services/estadisticas_service.dart' hide DateTimeRange;
import '../services/equipo_service.dart';
import '../services/catalogo_service.dart';
import '../services/pdf_service.dart'; 
import '../models/equipo_model.dart';
import '../models/tipo_diana_model.dart';
import '../models/disparo_model.dart';

class EstadisticasScreen extends StatefulWidget {
  final int modo; 
  final List<int>? idsSesionFijos; 

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
  final _pdfService = PdfService(); 

  List<EquipoDetalle> _equipos = [];
  List<TipoDiana> _dianas = [];

  int _filtroFechaSeleccionado = 0; 
  DateTimeRange? _rangoFechasManual; 
  
  EquipoDetalle? _equipoSel;
  TipoDiana? _dianaSel;
  
  // ESTA ES LA VARIABLE CLAVE QUE CONTIENE LAS PESTAÑAS VISIBLES
  List<TipoDiana> _dianasEnContexto = [];
  TipoDiana? _dianaPestanaSeleccionada;

  bool _filtrosAbiertos = true; 
  bool _cargando = true;
  bool _soyZurdo = false;

  List<Map<String, dynamic>> _datosProgreso = [];
  AnalisisAgrupacion? _analisis;
  List<DiagnosticoTecnico> _diagnostico = [];

  bool get _esModoDetalle => widget.idsSesionFijos != null && widget.idsSesionFijos!.isNotEmpty;

  @override
  void initState() {
    super.initState();
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

  DateTimeRange? _obtenerRangoActual() {
    final now = DateTime.now();
    switch (_filtroFechaSeleccionado) {
      case 1: return DateTimeRange(start: DateTime(now.year, now.month, now.day), end: now);
      case 2: return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case 3: return DateTimeRange(start: now.subtract(const Duration(days: 90)), end: now);
      case 4: return DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
      case 5: return _rangoFechasManual;
      default: return null;
    }
  }

  void _refrescarDatos() async {
    setState(() => _cargando = true);

    DateTimeRange? rangoCalculado;
    if (!_esModoDetalle) {
        rangoCalculado = _obtenerRangoActual();
    }

    final dianasDetectadas = await _statsService.obtenerTiposDianaEnFiltro(
      rangoFechas: rangoCalculado,
      idEquipo: _equipoSel?.id,
      filtroModo: _esModoDetalle ? null : widget.modo,
      idsSesiones: widget.idsSesionFijos,
    );

    TipoDiana? dianaParaAnalisis;
    if (_esModoDetalle || (dianasDetectadas.isNotEmpty && dianasDetectadas.length > 1)) {
        if (dianasDetectadas.isNotEmpty) {
           if (_dianaPestanaSeleccionada != null && dianasDetectadas.any((d) => d.id == _dianaPestanaSeleccionada!.id)) {
             dianaParaAnalisis = _dianaPestanaSeleccionada;
           } else {
             dianaParaAnalisis = dianasDetectadas.first;
             _dianaPestanaSeleccionada = dianaParaAnalisis;
           }
        }
    } else {
        dianaParaAnalisis = _dianaSel;
    }

    final progreso = await _statsService.obtenerEvolucionPuntos(
      rangoFechas: rangoCalculado,
      idEquipo: _equipoSel?.id,
      idTipoDiana: _dianaSel?.id, 
      filtroModo: _esModoDetalle ? null : widget.modo, 
      idsSesiones: widget.idsSesionFijos,
    );

    AnalisisAgrupacion? analisis;
    List<DiagnosticoTecnico> diagnostico = [];

    if (dianaParaAnalisis != null) {
      analisis = await _statsService.calcularAnalisisAgrupacion(
        rangoFechas: rangoCalculado,
        idEquipo: _equipoSel?.id,
        idTipoDiana: dianaParaAnalisis.id,
        filtroModo: _esModoDetalle ? null : widget.modo,
        idsSesiones: widget.idsSesionFijos,
      );
      
      diagnostico = await _statsService.calcularDiagnosticoTecnico(
        rangoFechas: rangoCalculado,
        idEquipo: _equipoSel?.id,
        idTipoDiana: dianaParaAnalisis.id,
        filtroModo: _esModoDetalle ? null : widget.modo,
        idsSesiones: widget.idsSesionFijos,
        esZurdo: _soyZurdo,
        generarEtiquetas: _esModoDetalle, 
      );
    }

    if (mounted) {
      setState(() {
        _dianasEnContexto = dianasDetectadas;
        _dianaPestanaSeleccionada = dianaParaAnalisis;
        _datosProgreso = progreso;
        _analisis = analisis;
        _diagnostico = diagnostico;
        _cargando = false;
      });
    }
  }

  // --- FUNCIÓN DE IMPRESIÓN (ARREGLADA: USA LO QUE VES EN PANTALLA) ---
  void _imprimirInforme() async {
    // 1. Mostrar carga
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

    try {
      List<DatosInformeDiana> resultados = [];
      
      // CAMBIO CLAVE: Usamos DIRECTAMENTE la lista '_dianasEnContexto' que ya tiene las pestañas cargadas.
      // Si la pantalla muestra pestañas, esto NO está vacío.
      List<TipoDiana> dianasAProcesar = [];
      
      if (_dianasEnContexto.isNotEmpty) {
         dianasAProcesar = _dianasEnContexto;
      } else if (_dianaSel != null) {
         // Fallback por si acaso: la seleccionada en el combo
         dianasAProcesar = [_dianaSel!];
      }

      // Preparar filtros idénticos a los que usa la pantalla (_refrescarDatos)
      // Si funciona en pantalla, funcionará aquí porque usamos LOS MISMOS parámetros.
      DateTimeRange? rango = !_esModoDetalle ? _obtenerRangoActual() : null;
      int? filtroEquipo = _equipoSel?.id;
      int? filtroModo = _esModoDetalle ? null : widget.modo; // En detalle anulamos modo

      for (var diana in dianasAProcesar) {
         var analisis = await _statsService.calcularAnalisisAgrupacion(
            rangoFechas: rango,
            idEquipo: filtroEquipo,
            idTipoDiana: diana.id,
            filtroModo: filtroModo,
            idsSesiones: widget.idsSesionFijos, // Esto es vital en modo detalle
         );

         // Validamos que haya datos
         if (analisis != null && (analisis.disparosValidos.isNotEmpty || analisis.disparosDescartados.isNotEmpty)) {
           var diag = await _statsService.calcularDiagnosticoTecnico(
              rangoFechas: rango,
              idEquipo: filtroEquipo,
              idTipoDiana: diana.id,
              filtroModo: filtroModo,
              idsSesiones: widget.idsSesionFijos,
              esZurdo: _soyZurdo,
              generarEtiquetas: _esModoDetalle, 
           );

           resultados.add(DatosInformeDiana(
             diana: diana,
             analisis: analisis,
             diagnostico: diag,
             equipo: _equipoSel
           ));
         }
      }

      // Cerrar carga
      if (mounted) Navigator.pop(context);

      if (resultados.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No hay datos visibles para imprimir.")));
        return;
      }

      // Texto Periodo
      String textoPeriodo = "Histórico";
      if (_esModoDetalle) {
         textoPeriodo = "Detalle de Sesión";
      } else if (rango != null) {
         textoPeriodo = "${rango.start.day}/${rango.start.month} - ${rango.end.day}/${rango.end.month}";
      }

      // Generar PDF
      await _pdfService.generarInformeAnalisisCompleto(
        perfil: null, 
        periodoTexto: textoPeriodo,
        datosDianas: resultados,
        datosProgreso: _datosProgreso,
        observaciones: _esModoDetalle ? "Informe de sesión individual." : "Estadísticas generales."
      );

    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      debugPrint("Error PDF: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }
  
  void _cambiarDianaVisualizada(TipoDiana nuevaDiana) {
    setState(() {
      _dianaPestanaSeleccionada = nuevaDiana;
    });
    _refrescarDatos(); 
  }

  void _seleccionarFechasManuales() async {
    final picked = await showDateRangePicker(context: context, locale: const Locale('es', 'ES'), firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: _rangoFechasManual, saveText: 'ACEPTAR', helpText: 'RANGO', cancelText: 'CANCELAR', confirmText: 'ACEPTAR', builder: (context, child) => Theme(data: ThemeData.light().copyWith(primaryColor: Colors.purple, colorScheme: const ColorScheme.light(primary: Colors.purple)), child: child!));
    if(picked!=null){ setState(() { _rangoFechasManual = picked; _filtroFechaSeleccionado = 5; }); _refrescarDatos(); } else { if (_filtroFechaSeleccionado==5 && _rangoFechasManual==null) { setState(()=>_filtroFechaSeleccionado=0); _refrescarDatos(); } }
  }
  String _formatoCorto(DateTime fecha) => "${fecha.day}/${fecha.month}";

  @override
  Widget build(BuildContext context) {
    String titulo = _esModoDetalle ? 'Análisis de Sesión' : (widget.modo == 2 ? 'Análisis Competiciones' : 'Análisis Entrenamientos');

    return Scaffold(
      appBar: AppBar(
        title: Text(titulo), 
        backgroundColor: Colors.purple,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: "Imprimir PDF",
            onPressed: !_cargando ? _imprimirInforme : null,
          )
        ],
      ),
      body: Column(
        children: [
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
                            const DropdownMenuItem(value: 0, child: Text('Todo')), const DropdownMenuItem(value: 1, child: Text('Hoy')), const DropdownMenuItem(value: 2, child: Text('Este Mes')), const DropdownMenuItem(value: 3, child: Text('Últimos 3 Meses')), const DropdownMenuItem(value: 4, child: Text('Este Año')),
                            DropdownMenuItem(value: 5, child: Text(_filtroFechaSeleccionado == 5 && _rangoFechasManual != null ? '${_formatoCorto(_rangoFechasManual!.start)} - ${_formatoCorto(_rangoFechasManual!.end)}' : 'Personalizado...', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) { if (v == 5) { _seleccionarFechasManuales(); } else { setState(() { _filtroFechaSeleccionado = v!; _refrescarDatos(); }); } },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<EquipoDetalle>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Arma', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
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
                      ],
                    ),
                  )
              ],
            ),
          ),
          
          Expanded(
            child: DefaultTabController(
              length: 3, 
              child: Column(
                children: [
                  const TabBar(
                    labelColor: Colors.purple,
                    indicatorColor: Colors.purple,
                    tabs: [
                      Tab(text: 'AGRUPACIÓN', icon: Icon(Icons.gps_fixed)),
                      Tab(text: 'TÉCNICA', icon: Icon(Icons.psychology)),
                      Tab(text: 'EVOLUCIÓN', icon: Icon(Icons.show_chart)),
                    ],
                  ),
                  Expanded(
                    child: _cargando 
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        children: [
                          _buildVistaAgrupacion(),
                          _buildDiagnosticoTecnico(),
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

  Widget _buildDiagnosticoTecnico() {
    if (_diagnostico.isEmpty) return const Center(child: Text("No hay errores suficientes para analizar.", style: TextStyle(color: Colors.grey)));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Text("Diestro"), Switch(value: _soyZurdo, onChanged: (v) { setState(() => _soyZurdo = v); _refrescarDatos(); }, activeColor: Colors.purple), const Text("Zurdo")]),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: PieChart(PieChartData(sections: _generarSeccionesPastel(), centerSpaceRadius: 40, sectionsSpace: 2)),
          ),
          const SizedBox(height: 20),
          const Text("Errores más frecuentes", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          ..._diagnostico.map((diag) => Card(margin: const EdgeInsets.only(bottom: 8), child: Padding(padding: const EdgeInsets.all(12.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [CircleAvatar(backgroundColor: Colors.purple[100], radius: 18, child: Text("${diag.porcentaje.round()}%", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(diag.nombreError, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), Text("${diag.cantidad} disparos detectados", style: const TextStyle(color: Colors.grey, fontSize: 12))]))]),
                  if (diag.etiquetas.isNotEmpty) ...[const SizedBox(height: 10), const Divider(height: 1), const SizedBox(height: 8), Wrap(spacing: 6, runSpacing: 6, children: diag.etiquetas.map((tag) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.purple.withOpacity(0.05), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.purple.withOpacity(0.2))), child: Text(tag, style: TextStyle(fontSize: 11, color: Colors.purple[900], fontWeight: FontWeight.w500)))).toList())]
          ])))).toList(),
        ],
      ),
    );
  }

  List<PieChartSectionData> _generarSeccionesPastel() {
    List<Color> colores = [Colors.redAccent, Colors.orangeAccent, Colors.blueAccent, Colors.greenAccent];
    return List.generate(_diagnostico.length, (i) {
      final diag = _diagnostico[i];
      final isLarge = i == 0;
      return PieChartSectionData(color: colores[i % colores.length], value: diag.cantidad.toDouble(), title: "${diag.porcentaje.round()}%", radius: isLarge ? 60 : 50, titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white));
    });
  }

  Widget _buildVistaAgrupacion() {
    if (_dianasEnContexto.isEmpty && _dianaSel == null && !_esModoDetalle) return const Center(child: Text("No hay datos para mostrar."));
    return Column(children: [
        if (_dianasEnContexto.length > 1) Container(height: 50, margin: const EdgeInsets.symmetric(vertical: 10), child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _dianasEnContexto.length, itemBuilder: (ctx, i) { final d = _dianasEnContexto[i]; bool isSel = d.id == _dianaPestanaSeleccionada?.id; return Padding(padding: const EdgeInsets.only(right: 8.0), child: ChoiceChip(label: Text(d.nombre), selected: isSel, selectedColor: Colors.purple[100], onSelected: (val) { if (val) { _cambiarDianaVisualizada(d); } })); })),
        Expanded(child: _buildMapaCalorContent()),
    ]);
  }

  Widget _buildMapaCalorContent() {
    TipoDiana? dianaActiva = _dianaPestanaSeleccionada ?? _dianaSel;
    if (dianaActiva == null) return const Center(child: Text("Selecciona Diana"));
    if (_analisis == null || (_analisis!.disparosValidos.isEmpty && _analisis!.disparosDescartados.isEmpty)) return const Center(child: Text("No hay impactos."));

    String consejo = "Agrupación Centrada";
    IconData iconoConsejo = Icons.check_circle;
    Color colorConsejo = Colors.green;
    String detalleClics = "";
    double devX = _analisis!.mpi.x; double devY = _analisis!.mpi.y; 
    double radioFisicoMm = 250.0; 
    if (dianaActiva.nombre.toLowerCase().contains("aire")) radioFisicoMm = 78.0;
    double mmX = devX * radioFisicoMm; double mmY = devY * radioFisicoMm; 
    double valorClic = _equipoSel?.correccionClick ?? 0.0;
    
    if (valorClic > 0) {
      int clicsH = (mmX.abs() / valorClic).round();
      int clicsV = (mmY.abs() / valorClic).round();
      String dirH = mmX > 0 ? "Izquierda (L)" : "Derecha (R)"; String dirV = mmY > 0 ? "Arriba (U)" : "Abajo (D)";      
      List<String> correcciones = [];
      if (clicsH > 0) correcciones.add("$clicsH clics $dirH");
      if (clicsV > 0) correcciones.add("$clicsV clics $dirV");
      if (correcciones.isNotEmpty) { consejo = "CORREGIR MIRAS"; iconoConsejo = Icons.build_circle; colorConsejo = Colors.orange[800]!; detalleClics = correcciones.join("  y  "); }
    } else {
      String horiz = devX > 0.05 ? "IZQUIERDA" : (devX < -0.05 ? "DERECHA" : ""); String vert = devY > 0.05 ? "ARRIBA" : (devY < -0.05 ? "ABAJO" : "");
      if (horiz != "" || vert != "") { consejo = "Mover miras: $horiz $vert"; detalleClics = "Configura los mm/clic de tu arma."; iconoConsejo = Icons.info; colorConsejo = Colors.blue; }
    }
    double puntosPerdidos = _analisis!.puntuacionPotencialMedia - _analisis!.puntuacionRealMedia;
    int vm = dianaActiva.valorMinimo; int an = dianaActiva.anilloNegroInicio; bool fn = dianaActiva.esFondoNegro; bool tm = dianaActiva.tieneMosca; bool tg = dianaActiva.tieneGuias; bool ed = an <= 5;
    int numDescartes = _analisis!.disparosDescartados.length;

    return SingleChildScrollView(child: Column(children: [
          Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: colorConsejo.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: colorConsejo)), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(iconoConsejo, color: colorConsejo), const SizedBox(width: 10), Expanded(child: Text(consejo, style: TextStyle(fontWeight: FontWeight.bold, color: colorConsejo, fontSize: 16)))]), if (detalleClics.isNotEmpty) ...[const SizedBox(height: 8), Text(detalleClics, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center)], const SizedBox(height: 10), Text(puntosPerdidos > 0.5 ? "Pierdes ${puntosPerdidos.toStringAsFixed(1)} puntos de media." : "Ajuste correcto.", style: const TextStyle(fontStyle: FontStyle.italic), textAlign: TextAlign.center), const Divider(), Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_datoEstadistico("Media Real", _analisis!.puntuacionRealMedia.toStringAsFixed(2)), const Icon(Icons.arrow_forward, color: Colors.grey), _datoEstadistico("Media Potencial", _analisis!.puntuacionPotencialMedia.toStringAsFixed(2), esVerde: true)]), if (numDescartes > 0) ...[const Divider(), Text("⚠️ Se han ignorado $numDescartes disparos extremos.", style: TextStyle(fontSize: 11, color: Colors.red[800], fontWeight: FontWeight.bold))]])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: AspectRatio(aspectRatio: 1, child: LayoutBuilder(builder: (context, constraints) { double diametro = constraints.maxWidth; return CustomPaint(painter: DianaPainter(validos: _convertirImpactosAPixeles(_analisis!.disparosValidos, diametro/2), descartados: _convertirImpactosAPixeles(_analisis!.disparosDescartados, diametro/2), valorMinimo: vm, anilloNegroInicio: an, esFondoNegro: fn, tieneMosca: tm, tieneGuias: tg, esEstiloDuelo: ed, centroGravedad: Offset((_analisis!.mpi.x * (diametro/2)) + (diametro/2), (_analisis!.mpi.y * (diametro/2)) + (diametro/2)))); }))),
          const SizedBox(height: 10), Text("${_analisis!.disparosValidos.length} impactos válidos", style: const TextStyle(color: Colors.grey)), const SizedBox(height: 20),
    ]));
  }

  Widget _buildGraficaProgreso() {
    if (_datosProgreso.isEmpty) return const Center(child: Text("No hay datos", style: TextStyle(color: Colors.grey)));
    List<FlSpot> puntos = [];
    for (int i = 0; i < _datosProgreso.length; i++) { puntos.add(FlSpot(i.toDouble(), (_datosProgreso[i]['total'] as num).toDouble())); }
    return Padding(padding: const EdgeInsets.all(24.0), child: LineChart(LineChartData(gridData: FlGridData(show: true, drawVerticalLine: false), titlesData: FlTitlesData(leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: const TextStyle(fontSize: 10)))), bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))), borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey[300]!)), lineBarsData: [LineChartBarData(spots: puntos, isCurved: true, color: Colors.purple, barWidth: 3, dotData: FlDotData(show: true), belowBarData: BarAreaData(show: true, color: Colors.purple.withOpacity(0.1)))])));
  }
  
  Widget _datoEstadistico(String label, String valor, {bool esVerde = false}) { return Column(children: [Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)), Text(valor, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: esVerde ? Colors.green[700] : Colors.black87))]); }
  List<Offset> _convertirImpactosAPixeles(List<Disparo> disparos, double radius) { return disparos.map((d) => Offset((d.x * radius) + radius, (d.y * radius) + radius)).toList(); }
}

class DianaPainter extends CustomPainter {
  final List<Offset> validos;
  final List<Offset> descartados;
  final int valorMinimo;
  final int anilloNegroInicio;
  final bool esFondoNegro;
  final bool tieneMosca;
  final bool tieneGuias;
  final bool esEstiloDuelo;
  final Offset? centroGravedad;

  DianaPainter({
    required this.validos,
    required this.descartados,
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

    final paintFondo = Paint()..color = esFondoNegro ? const Color(0xFF1A1A1A) : Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paintFondo);

    final paintNegro = Paint()..color = Colors.black..style = PaintingStyle.fill;
    final paintLineaBlanca = Paint()..color = Colors.white.withOpacity(0.9)..style = PaintingStyle.stroke..strokeWidth = 1.2;
    final paintLineaGris = Paint()..color = Colors.grey[400]!..style = PaintingStyle.stroke..strokeWidth = 1.0;

    if (esEstiloDuelo) {
       double paso = radius / 6;
       for (int i = 0; i < 6; i++) {
          double r = radius - (i * paso);
          canvas.drawCircle(center, r, paintLineaBlanca);
          int numeroAnillo = 5 + i;
          if (numeroAnillo < 10) _dibujarNumeros4Ejes(canvas, numeroAnillo.toString(), center, r - (paso / 2), Colors.white);
       }
    } else {
       int totalZonas = 11 - valorMinimo; 
       if (totalZonas < 1) totalZonas = 1;
       double anchoZona = radius / totalZonas;

       for (int i = 0; i < totalZonas; i++) {
          int numeroAnillo = valorMinimo + i;
          double r = radius - (i * anchoZona);
          
          if (numeroAnillo >= anilloNegroInicio) {
            canvas.drawCircle(center, r, paintNegro);
            canvas.drawCircle(center, r, paintLineaBlanca);
            if (numeroAnillo < 10) {
               _dibujarNumeros4Ejes(canvas, numeroAnillo.toString(), center, r - (anchoZona / 2), Colors.white);
            }
          } else {
            if (i > 0) canvas.drawCircle(center, r, esFondoNegro ? paintLineaBlanca : paintLineaGris);
            Color colorNum = esFondoNegro ? Colors.white : Colors.black;
            _dibujarNumeros4Ejes(canvas, numeroAnillo.toString(), center, r - (anchoZona / 2), colorNum);
          }
       }
    }

    if (tieneMosca) {
      double radioMosca = (esEstiloDuelo ? (radius/6) : (radius/(11-valorMinimo))) / 2;
      canvas.drawCircle(center, radioMosca, paintLineaBlanca);
    }
    
    if (tieneGuias) {
      Paint guia = Paint()..color = esFondoNegro ? Colors.white54 : Colors.grey..strokeWidth = 2.0;
      double largo = radius * 0.3;
      canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx - radius + largo, center.dy), guia);
      canvas.drawLine(Offset(center.dx + radius, center.dy), Offset(center.dx + radius - largo, center.dy), guia);
      canvas.drawLine(Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy - radius + largo), guia); 
      canvas.drawLine(Offset(center.dx, center.dy + radius), Offset(center.dx, center.dy + radius - largo), guia);
    }
    
    canvas.drawLine(Offset(center.dx - 4, center.dy), Offset(center.dx + 4, center.dy), Paint()..color = esFondoNegro?Colors.white:Colors.black..strokeWidth=1);
    canvas.drawLine(Offset(center.dx, center.dy - 4), Offset(center.dx, center.dy + 4), Paint()..color = esFondoNegro?Colors.white:Colors.black..strokeWidth=1);

    final paintDescartado = Paint()..color = Colors.grey.withOpacity(0.5)..style = PaintingStyle.fill;
    final paintValido = Paint()..color = const Color(0xFF00C853).withOpacity(0.8)..style = PaintingStyle.fill;
    final paintBordeImpacto = Paint()..color = Colors.white.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth=1;

    double tamano = radius * 0.04; 

    for(var p in descartados) {
       canvas.drawCircle(p, tamano, paintDescartado);
    }
    for(var p in validos) {
       canvas.drawCircle(p, tamano, paintValido);
       canvas.drawCircle(p, tamano, paintBordeImpacto);
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
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold) 
      ),
      textDirection: TextDirection.ltr
    );
    tp.layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant DianaPainter oldDelegate) => true;
}