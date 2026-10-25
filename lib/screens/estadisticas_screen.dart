import 'dart:math'; 
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/estadisticas_service.dart' hide DateTimeRange;
import '../services/equipo_service.dart';
import '../services/catalogo_service.dart';
import '../services/municion_service.dart';
import '../services/entrenamiento_service.dart';
import '../services/pdf_service.dart';
import '../models/equipo_model.dart';
import '../models/tipo_diana_model.dart';
import '../models/disparo_model.dart';
import '../models/municion_model.dart';
import '../theme/app_theme.dart';
import '../utils/impacto_visual.dart';
import '../widgets/tiro_amg_app_bar.dart';

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
  final _municionService = MunicionService();
  final _entrenamientoService = EntrenamientoService();
  final _pdfService = PdfService(); 

  final Color _colorTema = AppColors.accentAnalytics;
  final Color _colorTemaClaro = AppColors.accentAnalytics.withValues(alpha: 0.12);
  final Color _colorTemaOscuro = AppColors.primary;

  List<EquipoDetalle> _equipos = [];
  List<TipoDiana> _dianas = [];
  List<MunicionDetalle> _municiones = [];

  int _filtroFechaSeleccionado = 0; 
  DateTimeRange? _rangoFechasManual; 
  EquipoDetalle? _equipoSel;
  MunicionDetalle? _municionSel;
  TipoDiana? _dianaSel; 
  List<TipoDiana> _dianasEnContexto = []; 
  TipoDiana? _dianaPestanaSeleccionada;  
  bool _filtrosAbiertos = true; 
  bool _cargando = true;
  bool _soyZurdo = false;
  /// Solo aplica en detalle de sesión: análisis de clics vs técnica.
  bool _esCorreccionMira = false;

  List<Map<String, dynamic>> _datosProgreso = [];
  AnalisisAgrupacion? _analisis;
  List<DiagnosticoTecnico> _diagnostico = []; 
  List<ResumenMunicionStats> _resumenMunicion = [];
  List<ComparativoLotesContexto> _comparativoLotes = [];

  bool get _esModoDetalle => widget.idsSesionFijos != null && widget.idsSesionFijos!.isNotEmpty;
  bool get _esSesionUnica =>
      _esModoDetalle && widget.idsSesionFijos!.length == 1;
  /// Clics de mira solo en análisis de una sesión marcada para corrección.
  bool get _mostrarCorreccionMira => _esSesionUnica && _esCorreccionMira;
  bool get _mostrarTecnica => !_mostrarCorreccionMira;

  @override
  void initState() {
    super.initState();
    if (_esModoDetalle) _filtrosAbiertos = false;
    _cargarFiltrosIniciales();
  }

  void _cargarFiltrosIniciales() async {
    final e = await _equipoService.obtenerEquiposDetallados();
    final d = await _catalogoService.obtenerTiposDiana();
    final m = await _municionService.obtenerMunicionDetallada();

    bool correccion = false;
    EquipoDetalle? equipoDeSesion;
    if (_esModoDetalle && widget.idsSesionFijos!.isNotEmpty) {
      final sesion =
          await _entrenamientoService.obtenerSesionPorId(widget.idsSesionFijos!.first);
      if (sesion != null) {
        // Corrección de miras solo aplica al analizar una sola sesión.
        correccion = widget.idsSesionFijos!.length == 1 && sesion.esCorreccionMira;
        try {
          equipoDeSesion = e.firstWhere((eq) => eq.id == sesion.idEquipo);
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        _equipos = e;
        _dianas = d;
        _municiones = m;
        if (d.isNotEmpty) _dianaSel = d.first;
        _esCorreccionMira = correccion;
        if (equipoDeSesion != null) {
          _equipoSel = equipoDeSesion;
        } else if (!_esModoDetalle && e.isNotEmpty) {
          _equipoSel = e.first;
        }
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
    if (!_esModoDetalle) rangoCalculado = _obtenerRangoActual();

    final dianasDetectadas = await _statsService.obtenerTiposDianaEnFiltro(
      rangoFechas: rangoCalculado,
      idEquipo: _equipoSel?.id,
      idMunicion: _municionSel?.id,
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
      idMunicion: _municionSel?.id,
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
        idMunicion: _municionSel?.id,
        idTipoDiana: dianaParaAnalisis.id,
        filtroModo: _esModoDetalle ? null : widget.modo,
        idsSesiones: widget.idsSesionFijos,
      );
      
      diagnostico = await _statsService.calcularDiagnosticoTecnico(
        rangoFechas: rangoCalculado,
        idEquipo: _equipoSel?.id,
        idMunicion: _municionSel?.id,
        idTipoDiana: dianaParaAnalisis.id,
        filtroModo: _esModoDetalle ? null : widget.modo,
        idsSesiones: widget.idsSesionFijos,
        esZurdo: _soyZurdo,
        generarEtiquetas: _esModoDetalle, 
      );
    }

    final resumenMun = await _statsService.obtenerResumenMunicion(
      rangoFechas: rangoCalculado,
      idEquipo: _equipoSel?.id,
      filtroModo: _esModoDetalle ? null : widget.modo,
      idsSesiones: widget.idsSesionFijos,
    );
    final comparativo = await _statsService.obtenerComparativoLotes(
      rangoFechas: rangoCalculado,
      idEquipo: _equipoSel?.id,
      idMunicion: _municionSel?.id,
      filtroModo: _esModoDetalle ? null : widget.modo,
      idsSesiones: widget.idsSesionFijos,
    );

    if (mounted) {
      setState(() {
        _dianasEnContexto = dianasDetectadas;
        _dianaPestanaSeleccionada = dianaParaAnalisis;
        _datosProgreso = progreso;
        _analisis = analisis;
        _diagnostico = diagnostico;
        _resumenMunicion = resumenMun;
        _comparativoLotes = comparativo;
        _cargando = false;
      });
    }
  }

  void _imprimirInforme() async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

    try {
      List<DatosInformeDiana> resultados = [];
      List<TipoDiana> dianasAProcesar = [];

      if (_esModoDetalle) {
         dianasAProcesar = await _statsService.obtenerTiposDianaEnFiltro(
            idsSesiones: widget.idsSesionFijos, 
            rangoFechas: null, idEquipo: null, filtroModo: null   
         );
      } else {
         if (_dianasEnContexto.isNotEmpty) dianasAProcesar = _dianasEnContexto;
         else if (_dianaSel != null) dianasAProcesar = [_dianaSel!];
      }

      DateTimeRange? rangoPdf = _esModoDetalle ? null : _obtenerRangoActual();
      int? equipoPdf = _esModoDetalle ? null : _equipoSel?.id;
      int? modoPdf = _esModoDetalle ? null : widget.modo;
      List<int>? sesionesPdf = _esModoDetalle ? widget.idsSesionFijos : null;

      for (var diana in dianasAProcesar) {
         var analisis = await _statsService.calcularAnalisisAgrupacion(
            idTipoDiana: diana.id,
            idMunicion: _municionSel?.id,
            rangoFechas: rangoPdf, idEquipo: equipoPdf, filtroModo: modoPdf, idsSesiones: sesionesPdf,
         );

         if (analisis != null && (analisis.disparosValidos.isNotEmpty || analisis.disparosDescartados.isNotEmpty)) {
           var diag = await _statsService.calcularDiagnosticoTecnico(
              idTipoDiana: diana.id,
              idMunicion: _municionSel?.id,
              rangoFechas: rangoPdf, idEquipo: equipoPdf, filtroModo: modoPdf, idsSesiones: sesionesPdf,
              esZurdo: _soyZurdo, generarEtiquetas: _esModoDetalle, 
           );

           resultados.add(DatosInformeDiana(
             diana: diana,
             analisis: analisis,
             diagnostico: _mostrarTecnica ? diag : const [],
             equipo: _equipoSel,
           ));
         }
      }

      if (mounted) Navigator.pop(context); 

      if (resultados.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No hay datos para imprimir.")));
        return;
      }

      String textoPeriodo = "Histórico";
      final nSel = widget.idsSesionFijos?.length ?? 0;
      if (_esModoDetalle) {
        textoPeriodo = nSel == 1 ? "Detalle de Sesión" : "$nSel sesiones seleccionadas";
      } else if (rangoPdf != null) {
        textoPeriodo =
            "${rangoPdf.start.day}/${rangoPdf.start.month} - ${rangoPdf.end.day}/${rangoPdf.end.month}";
      }

      await _pdfService.generarInformeAnalisisCompleto(
        perfil: null, 
        periodoTexto: textoPeriodo,
        datosDianas: resultados,
        datosProgreso: _datosProgreso,
        comparativoLotes: _comparativoLotes,
        observaciones: _esModoDetalle
            ? (nSel == 1
                ? 'Informe detallado de sesión.'
                : 'Informe de $nSel sesiones seleccionadas.')
            : 'Informe de evolución.',
        mostrarCorreccionMira: _mostrarCorreccionMira,
        incluirDiagnosticoTecnico: _mostrarTecnica,
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
    final picked = await showDateRangePicker(
      context: context,
      locale: const Locale('es', 'ES'),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _rangoFechasManual,
      saveText: 'ACEPTAR',
      helpText: 'RANGO',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if(picked!=null){ setState(() { _rangoFechasManual = picked; _filtroFechaSeleccionado = 5; }); _refrescarDatos(); } else { if (_filtroFechaSeleccionado==5 && _rangoFechasManual==null) { setState(()=>_filtroFechaSeleccionado=0); _refrescarDatos(); } }
  }
  String _formatoCorto(DateTime fecha) => "${fecha.day}/${fecha.month}";

  @override
  Widget build(BuildContext context) {
    final nSel = widget.idsSesionFijos?.length ?? 0;
    String titulo = _esModoDetalle
        ? (nSel == 1
            ? 'Análisis de Sesión'
            : 'Análisis ($nSel sesiones)')
        : (widget.modo == 2 ? 'Análisis Competiciones' : 'Análisis Entrenamientos');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: TiroAmgAppBar(
        section: titulo,
        actions: [
          IconButton(icon: const Icon(Icons.print), tooltip: "Imprimir PDF", onPressed: !_cargando ? _imprimirInforme : null)
        ],
      ),
      body: Column(
        children: [
          if (!_esModoDetalle)
          Card(
            margin: EdgeInsets.zero,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppRadii.card)),
              side: BorderSide(color: AppColors.border),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.filter_alt, color: _colorTema),
                  title: Text("Filtros de Análisis", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.title)),
                  subtitle: Text(_filtroFechaSeleccionado == 0 ? "Todo el historial" : "Filtros activos...", style: TextStyle(fontSize: 12, color: AppColors.subtitle)),
                  trailing: Icon(_filtrosAbiertos ? Icons.expand_less : Icons.expand_more, color: _colorTema),
                  onTap: () => setState(() => _filtrosAbiertos = !_filtrosAbiertos),
                ),
                if (_filtrosAbiertos)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Periodo', contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                          value: _filtroFechaSeleccionado,
                          items: [const DropdownMenuItem(value: 0, child: Text('Todo')), const DropdownMenuItem(value: 1, child: Text('Hoy')), const DropdownMenuItem(value: 2, child: Text('Este Mes')), const DropdownMenuItem(value: 3, child: Text('Últimos 3 Meses')), const DropdownMenuItem(value: 4, child: Text('Este Año')), DropdownMenuItem(value: 5, child: Text(_filtroFechaSeleccionado == 5 && _rangoFechasManual != null ? '${_formatoCorto(_rangoFechasManual!.start)} - ${_formatoCorto(_rangoFechasManual!.end)}' : 'Personalizado...', overflow: TextOverflow.ellipsis))],
                          onChanged: (v) { if (v == 5) { _seleccionarFechasManuales(); } else { setState(() { _filtroFechaSeleccionado = v!; _refrescarDatos(); }); } },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<EquipoDetalle>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Arma', contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                          value: _equipoSel,
                          items: [const DropdownMenuItem(value: null, child: Text('Todas las armas')), ..._equipos.map((e) => DropdownMenuItem(value: e, child: Text(e.nombre, overflow: TextOverflow.ellipsis))).toList()],
                          onChanged: (v) => setState(() { _equipoSel = v; _refrescarDatos(); }),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<MunicionDetalle>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Munición', contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                          value: _municionSel,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Toda la munición')),
                            ..._municiones.map((m) => DropdownMenuItem(
                              value: m,
                              child: Text('${m.marca} (${m.lote})', overflow: TextOverflow.ellipsis),
                            )),
                          ],
                          onChanged: (v) => setState(() { _municionSel = v; _refrescarDatos(); }),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<TipoDiana>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Tipo de Diana', contentPadding: EdgeInsets.symmetric(horizontal: 10)),
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
              key: ValueKey(_mostrarTecnica ? 5 : 4),
              length: _mostrarTecnica ? 5 : 4,
              child: Column(
                children: [
                  TabBar(
                    labelColor: _colorTema,
                    unselectedLabelColor: AppColors.subtitle,
                    indicatorColor: _colorTema,
                    isScrollable: true,
                    tabs: [
                      const Tab(text: 'AGRUPACIÓN', icon: Icon(Icons.gps_fixed)),
                      if (_mostrarTecnica)
                        const Tab(text: 'TÉCNICA', icon: Icon(Icons.psychology)),
                      const Tab(text: 'EVOLUCIÓN', icon: Icon(Icons.show_chart)),
                      const Tab(text: 'MUNICIÓN', icon: Icon(Icons.local_fire_department)),
                      const Tab(text: 'COMPARATIVO', icon: Icon(Icons.compare_arrows)),
                    ],
                  ),
                  Expanded(
                    child: _cargando 
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        children: [
                          _buildVistaAgrupacion(),
                          if (_mostrarTecnica) _buildDiagnosticoTecnico(),
                          _buildGraficaProgreso(),
                          _buildResumenMunicion(),
                          _buildComparativoLotes(),
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
    if (_diagnostico.isEmpty) return Center(child: Text("No hay errores suficientes.", style: TextStyle(color: AppColors.subtitle)));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text("Diestro", style: TextStyle(color: AppColors.title)), Switch(value: _soyZurdo, onChanged: (v) { setState(() => _soyZurdo = v); _refrescarDatos(); }, activeColor: _colorTema), Text("Zurdo", style: TextStyle(color: AppColors.title))]),
          const SizedBox(height: 10),
          SizedBox(height: 200, child: PieChart(PieChartData(sections: _generarSeccionesPastel(), centerSpaceRadius: 40, sectionsSpace: 2))),
          const SizedBox(height: 20),
          Text("Errores más frecuentes", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.title)),
          const SizedBox(height: 10),
          ..._diagnostico.map((diag) => Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(padding: const EdgeInsets.all(12.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [CircleAvatar(backgroundColor: _colorTemaClaro, radius: 18, child: Text("${diag.porcentaje.round()}%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _colorTemaOscuro))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(diag.nombreError, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.title)), Text("${diag.cantidad} disparos detectados", style: TextStyle(color: AppColors.subtitle, fontSize: 12))]))]),
                  if (diag.detalles.isNotEmpty) ...[
                    const SizedBox(height: 10), 
                    const Divider(height: 1), 
                    const SizedBox(height: 8), 
                    Wrap(
                      spacing: 6, 
                      runSpacing: 6, 
                      children: diag.detalles.map((detalle) {
                        Color colorBg;
                        Color colorTxt;
                        if (detalle.puntuacion < 7) { colorBg = Colors.red[50]!; colorTxt = Colors.red[900]!; } 
                        else if (detalle.puntuacion < 9) { colorBg = Colors.orange[50]!; colorTxt = Colors.orange[900]!; } 
                        else { colorBg = AppColors.primary.withValues(alpha: 0.08); colorTxt = AppColors.title; } 

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), 
                          decoration: BoxDecoration(color: colorBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: colorTxt.withValues(alpha: 0.3))), 
                          child: Text(detalle.etiqueta, style: TextStyle(fontSize: 11, color: colorTxt, fontWeight: FontWeight.bold))
                        );
                      }).toList()
                    )
                  ]
          ])))).toList(),
        ],
      ),
    );
  }

  List<PieChartSectionData> _generarSeccionesPastel() {
    List<Color> colores = [Colors.redAccent, Colors.orangeAccent, Colors.blueAccent, Colors.greenAccent];
    return List.generate(_diagnostico.length, (i) {
      final diag = _diagnostico[i];
      return PieChartSectionData(color: colores[i % colores.length], value: diag.cantidad.toDouble(), title: "${diag.porcentaje.round()}%", radius: i == 0 ? 60 : 50, titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white));
    });
  }

  Widget _buildVistaAgrupacion() {
    if (_dianasEnContexto.isEmpty && _dianaSel == null && !_esModoDetalle) return const Center(child: Text("No hay datos para mostrar."));
    return Column(children: [
        if (_dianasEnContexto.length > 1) Container(height: 50, margin: const EdgeInsets.symmetric(vertical: 10), child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _dianasEnContexto.length, itemBuilder: (ctx, i) { final d = _dianasEnContexto[i]; bool isSel = d.id == _dianaPestanaSeleccionada?.id; return Padding(padding: const EdgeInsets.only(right: 8.0), child: ChoiceChip(label: Text(d.nombre), selected: isSel, selectedColor: _colorTemaClaro, onSelected: (val) { if (val) { _cambiarDianaVisualizada(d); } })); })),
        Expanded(child: _buildMapaCalorContent()),
    ]);
  }

  Widget _buildMapaCalorContent() {
    TipoDiana? dianaActiva = _dianaPestanaSeleccionada ?? _dianaSel;
    if (dianaActiva == null) return const Center(child: Text("Selecciona Diana"));
    if (_analisis == null || _analisis!.disparosValidos.isEmpty) return const Center(child: Text("No hay impactos."));

    String consejo = "Agrupación Centrada";
    IconData iconoConsejo = Icons.check_circle;
    Color colorConsejo = Colors.green;
    String detalleClics = "";
    double devX = _analisis!.mpi.x; double devY = _analisis!.mpi.y; 
    double radioFisicoMm = 250.0; 
    if (dianaActiva.nombre.toLowerCase().contains("aire")) radioFisicoMm = 78.0;
    double mmX = devX * radioFisicoMm; double mmY = devY * radioFisicoMm; 
    double valorClic = _equipoSel?.correccionClick ?? 0.0;
    
    // Solo sugerir clics si la sesión se marcó como corrección de miras.
    if (_mostrarCorreccionMira) {
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
          consejo = "Mover miras: $horiz $vert";
          detalleClics = "Configura los mm/clic de tu arma.";
          iconoConsejo = Icons.info;
          colorConsejo = _colorTema;
        }
      }
    } else {
      // Entrenamiento normal: sin sugerencias de clics.
      consejo = "Análisis de agrupación";
      iconoConsejo = Icons.gps_fixed;
      colorConsejo = _colorTema;
    }
    double puntosPerdidos = _analisis!.puntuacionPotencialMedia - _analisis!.puntuacionRealMedia;
    int vm = dianaActiva.valorMinimo; int an = dianaActiva.anilloNegroInicio; bool fn = dianaActiva.esFondoNegro; bool tm = dianaActiva.tieneMosca; bool tg = dianaActiva.tieneGuias; bool ed = an <= 5;
    int numDescartes = _analisis!.disparosDescartados.length;

    return SingleChildScrollView(child: Column(children: [
          Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: colorConsejo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadii.card), border: Border.all(color: colorConsejo)), child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(iconoConsejo, color: colorConsejo), const SizedBox(width: 10), Expanded(child: Text(consejo, style: TextStyle(fontWeight: FontWeight.bold, color: colorConsejo, fontSize: 16)))]), 
            
            // --- AQUI ESTA EL CAMBIO DE "TENDENCIA" EN PANTALLA ---
            if (_analisis?.consejoTendencia != null && _analisis!.consejoTendencia.isNotEmpty && _analisis!.consejoTendencia != "Agrupación Circular (Equilibrada)")
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(_analisis!.consejoTendencia, style: TextStyle(fontWeight: FontWeight.bold, color: _colorTemaOscuro, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
              ),
            // -----------------------------------------------------

            if (detalleClics.isNotEmpty) ...[const SizedBox(height: 8), Text(detalleClics, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center)], 
            const SizedBox(height: 10), Text(puntosPerdidos > 0.5 ? "Pierdes ${puntosPerdidos.toStringAsFixed(1)} puntos de media." : "Ajuste correcto.", style: const TextStyle(fontStyle: FontStyle.italic), textAlign: TextAlign.center), const Divider(), Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_datoEstadistico("Media Real", _analisis!.puntuacionRealMedia.toStringAsFixed(2)), const Icon(Icons.arrow_forward, color: Colors.grey), _datoEstadistico("Media Potencial", _analisis!.puntuacionPotencialMedia.toStringAsFixed(2), esVerde: true)]), if (numDescartes > 0) ...[const Divider(), Text("⚠️ Se han ignorado $numDescartes disparos extremos.", style: TextStyle(fontSize: 11, color: Colors.red[800], fontWeight: FontWeight.bold))]])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: AspectRatio(aspectRatio: 1, child: LayoutBuilder(builder: (context, constraints) { 
            double diametro = constraints.maxWidth; 
            return CustomPaint(painter: DianaPainter(
              validos: _convertirImpactosAPixeles(_analisis!.disparosValidos, diametro/2), 
              descartados: _convertirImpactosAPixeles(_analisis!.disparosDescartados, diametro/2), 
              valorMinimo: vm, anilloNegroInicio: an, esFondoNegro: fn, tieneMosca: tm, tieneGuias: tg, esEstiloDuelo: ed,
              nombreCalibre: _equipoSel?.nombreCalibre,
              centroGravedad: Offset((_analisis!.mpi.x * (diametro/2)) + (diametro/2), (_analisis!.mpi.y * (diametro/2)) + (diametro/2)))); 
          }))),
          const SizedBox(height: 10), Text("${_analisis!.disparosValidos.length} impactos válidos", style: const TextStyle(color: Colors.grey)), const SizedBox(height: 20),
    ]));
  }

  Widget _buildGraficaProgreso() {
    if (_datosProgreso.isEmpty) return const Center(child: Text("No hay datos", style: TextStyle(color: Colors.grey)));
    List<FlSpot> puntos = [];
    for (int i = 0; i < _datosProgreso.length; i++) { puntos.add(FlSpot(i.toDouble(), (_datosProgreso[i]['total'] as num).toDouble())); }
    
    // DEGRADADO AZUL PARA LA GRÁFICA EN PANTALLA
    final List<Color> gradientColors = [
      _colorTema,
      _colorTema.withOpacity(0.0),
    ];

    return Padding(padding: const EdgeInsets.all(24.0), child: LineChart(LineChartData(
      gridData: FlGridData(
        show: true, 
        drawVerticalLine: false,
        getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
      ), 
      titlesData: FlTitlesData(leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.grey)))), bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))), 
      borderData: FlBorderData(show: false), 
      lineBarsData: [
        LineChartBarData(
          spots: puntos, 
          isCurved: true, 
          color: _colorTema, 
          barWidth: 4, 
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 4, color: Colors.white, strokeWidth: 2, strokeColor: _colorTema)
          ), 
          belowBarData: BarAreaData(
            show: true, 
            gradient: LinearGradient(
              colors: gradientColors.map((color) => color.withOpacity(0.3)).toList(),
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            )
          )
        )
      ]
    )));
  }

  Widget _buildResumenMunicion() {
    if (_resumenMunicion.isEmpty) {
      return const Center(
        child: Text("No hay datos de munición para este filtro.", style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _resumenMunicion.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final r = _resumenMunicion[index];
        final titulo = (r.idMunicion == null) ? 'Sin munición asociada' : '${r.marca} (${r.lote})';
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _colorTemaClaro,
              child: Icon(Icons.local_fire_department, color: AppColors.accentCompetition),
            ),
            title: Text(titulo, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.title)),
            subtitle: Text('Sesiones: ${r.sesiones} | Disparos: ${r.disparos} | Puntos: ${r.totalPuntos.toStringAsFixed(0)}', style: TextStyle(color: AppColors.subtitle)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Media', style: TextStyle(fontSize: 11, color: AppColors.subtitle)),
                Text(r.media.toStringAsFixed(2), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _colorTemaOscuro)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildComparativoLotes() {
    if (_comparativoLotes.isEmpty) {
      return const Center(
        child: Text(
          "No hay contextos con al menos 2 lotes comparables.\nPrueba ampliando periodo o quitando filtros.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _comparativoLotes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final c = _comparativoLotes[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.modalidad, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.title)),
                const SizedBox(height: 4),
                Text('Temp: ${c.rangoTemperatura} | Viento: ${c.rangoViento}', style: TextStyle(color: AppColors.subtitle)),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.accentTraining.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadii.iconBox),
                          border: Border.all(color: AppColors.accentTraining.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('MEJOR LOTE', style: TextStyle(color: AppColors.accentTraining, fontWeight: FontWeight.bold)),
                            Text('${c.mejor.marca} (${c.mejor.lote})'),
                            Text('Media: ${c.mejor.media.toStringAsFixed(2)} | Disparos: ${c.mejor.disparos}', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.accentDanger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadii.iconBox),
                          border: Border.all(color: AppColors.accentDanger.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('PEOR LOTE', style: TextStyle(color: AppColors.accentDanger, fontWeight: FontWeight.bold)),
                            Text('${c.peor.marca} (${c.peor.lote})'),
                            Text('Media: ${c.peor.media.toStringAsFixed(2)} | Disparos: ${c.peor.disparos}', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Diferencia: ${c.diferencia.toStringAsFixed(2)} pts/disparo',
                  style: TextStyle(
                    color: c.diferencia >= 0 ? AppColors.primary : AppColors.accentDanger,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
  final String? nombreCalibre;
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
    this.nombreCalibre,
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

    double anchoZona;
    if (esEstiloDuelo) {
       anchoZona = radius / 6;
       for (int i = 0; i < 6; i++) {
          double r = radius - (i * anchoZona);
          canvas.drawCircle(center, r, paintLineaBlanca);
          int numeroAnillo = 5 + i;
          if (numeroAnillo < 10) _dibujarNumeros4Ejes(canvas, numeroAnillo.toString(), center, r - (anchoZona / 2), Colors.white);
       }
    } else {
       int totalZonas = 11 - valorMinimo; 
       if (totalZonas < 1) totalZonas = 1;
       anchoZona = radius / totalZonas;

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

    final radioImpacto = ImpactoVisual.radioPx(
      anchoZona: anchoZona,
      nombreCalibre: nombreCalibre,
    );
    for (final p in descartados) {
      ImpactoVisual.dibujar(canvas, p, radioImpacto, color: ImpactoVisual.colorDescartado);
    }
    for (final p in validos) {
      ImpactoVisual.dibujar(canvas, p, radioImpacto);
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