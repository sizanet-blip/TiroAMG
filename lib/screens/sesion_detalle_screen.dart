import 'dart:math';
import 'package:flutter/material.dart';
import '../models/sesion_model.dart';
import '../models/disparo_model.dart';
import '../models/plantilla_tiempos_model.dart';
import '../models/equipo_model.dart';
import '../models/municion_model.dart';
import '../services/entrenamiento_service.dart';
import '../services/plantilla_tiempos_service.dart';
import '../services/catalogo_service.dart';
import '../services/equipo_service.dart';
import '../services/pdf_service.dart';
import '../services/perfil_service.dart';
import '../services/municion_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tiro_amg_app_bar_title.dart';
import '../utils/impacto_visual.dart';
import 'estadisticas_screen.dart'; // <--- IMPORTANTE: Para navegar a estadísticas

class SesionDetalleScreen extends StatefulWidget {
  final int sesionId;

  const SesionDetalleScreen({super.key, required this.sesionId});

  @override
  State<SesionDetalleScreen> createState() => _SesionDetalleScreenState();
}

class _SesionDetalleScreenState extends State<SesionDetalleScreen> {
  final _entrenamientoService = EntrenamientoService();
  final _plantillaService = PlantillaTiemposService();
  final _catalogoService = CatalogoService();
  final _equipoService = EquipoService();
  final _pdfService = PdfService();
  final _perfilService = PerfilService();
  final _municionService = MunicionService();
  
  final ScrollController _scrollController = ScrollController();

  Sesion? _sesion;
  PlantillaTiempos? _plantilla;
  List<Disparo> _disparos = [];
  bool _cargando = true;

  // Datos extra
  EquipoDetalle? _equipoDetalle;
  MunicionDetalle? _municionDetalle;

  // Configuración Diana
  int _valorMinimo = 1;
  int _anilloNegroInicio = 7;
  bool _esFondoNegro = false;
  bool _tieneMosca = true;
  bool _tieneGuias = false;
  bool _esEstiloDuelo = false;

  @override
  void initState() {
    super.initState();
    _cargarDatosCompletos();
  }

  Future<void> _cargarDatosCompletos() async {
    final sesion = await _entrenamientoService.obtenerSesionPorId(widget.sesionId);
    if (sesion == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final disparos = await _entrenamientoService.obtenerDisparosDeSesion(widget.sesionId);
    final plantilla = await _plantillaService.obtenerPorId(sesion.idPlantilla);
    
    try {
      var listEquipos = await _equipoService.obtenerEquiposDetallados();
      _equipoDetalle = listEquipos.firstWhere((e) => e.id == sesion.idEquipo);
    } catch(e) {}

    if (sesion.idMunicion != null) {
      _municionDetalle = await _municionService.obtenerDetallePorId(sesion.idMunicion!);
    } else {
      _municionDetalle = null;
    }

    if (plantilla != null && plantilla.idTipoDiana != null) {
      final dianas = await _catalogoService.obtenerTiposDiana();
      try {
        final dianaConfig = dianas.firstWhere((d) => d.id == plantilla.idTipoDiana);
        setState(() {
          _valorMinimo = dianaConfig.valorMinimo;
          _anilloNegroInicio = dianaConfig.anilloNegroInicio;
          _esFondoNegro = dianaConfig.esFondoNegro;
          _tieneMosca = dianaConfig.tieneMosca;
          _tieneGuias = dianaConfig.tieneGuias;
          _esEstiloDuelo = _anilloNegroInicio <= 5;
        });
      } catch (e) {}
    }

    if (mounted) {
      setState(() {
        _sesion = sesion;
        _disparos = disparos;
        _plantilla = plantilla;
        _cargando = false;
      });
    }
  }

  int? _parseInt(String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    return int.tryParse(v);
  }

  double? _parseDouble(String value) {
    final v = value.trim().replaceAll(',', '.');
    if (v.isEmpty) return null;
    return double.tryParse(v);
  }

  String _buildCondicionesTexto() {
    if (_sesion == null) return '';
    final s = _sesion!;
    final parts = <String>[];
    if (s.distanciaMetros != null) parts.add('${s.distanciaMetros}m');
    if (s.posicionTiro != null && s.posicionTiro!.isNotEmpty) parts.add('Posición: ${s.posicionTiro}');
    if (s.esInterior != null) parts.add(s.esInterior! ? 'Interior' : 'Exterior');
    if (s.iluminacion != null && s.iluminacion!.isNotEmpty) parts.add('Luz: ${s.iluminacion}');
    if (s.temperaturaC != null) parts.add('T: ${s.temperaturaC!.toStringAsFixed(1)}°C');
    if (s.humedadPct != null) parts.add('H: ${s.humedadPct!.toStringAsFixed(0)}%');
    if (s.presionHpa != null) parts.add('P: ${s.presionHpa!.toStringAsFixed(0)} hPa');
    if (s.vientoMs != null) {
      final dir = (s.vientoDireccion == null || s.vientoDireccion!.isEmpty) ? '' : ' ${s.vientoDireccion}';
      parts.add('V: ${s.vientoMs!.toStringAsFixed(1)} m/s$dir');
    }
    return parts.join(' | ');
  }

  void _editarDatosSesion() async {
    final equipos = await _equipoService.obtenerEquiposDetallados();
    
    EquipoDetalle? equipoTemp;
    if (_equipoDetalle != null) {
       try { equipoTemp = equipos.firstWhere((e) => e.id == _equipoDetalle!.id); } catch (_) {}
    }
    if (equipoTemp == null && equipos.isNotEmpty) equipoTemp = equipos.first;

    final lugarCtrl = TextEditingController(text: _sesion?.lugar ?? "");
    final notasCtrl = TextEditingController(text: _sesion?.nota ?? "");
    final distanciaCtrl = TextEditingController(text: _sesion?.distanciaMetros?.toString() ?? "");
    final tempCtrl = TextEditingController(text: _sesion?.temperaturaC?.toString() ?? "");
    final humedadCtrl = TextEditingController(text: _sesion?.humedadPct?.toString() ?? "");
    final presionCtrl = TextEditingController(text: _sesion?.presionHpa?.toString() ?? "");
    final vientoCtrl = TextEditingController(text: _sesion?.vientoMs?.toString() ?? "");
    final vientoDirCtrl = TextEditingController(text: _sesion?.vientoDireccion ?? "");
    String? posicionTemp = _sesion?.posicionTiro;
    String? iluminacionTemp = _sesion?.iluminacion;
    bool interiorTemp = _sesion?.esInterior ?? true;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Editar Datos'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<EquipoDetalle>(
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Arma Utilizada', border: OutlineInputBorder()),
                    value: equipoTemp,
                    items: equipos.map((e) => DropdownMenuItem(value: e, child: Text(e.nombre, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setStateDialog(() => equipoTemp = v),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: lugarCtrl,
                    decoration: const InputDecoration(labelText: 'Lugar / Campo de Tiro', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: distanciaCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Distancia (m)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      const Text('Interior'),
                      Switch(
                        value: interiorTemp,
                        onChanged: (v) => setStateDialog(() => interiorTemp = v),
                      ),
                      Text(interiorTemp ? 'Si' : 'No'),
                    ],
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    value: posicionTemp,
                    decoration: const InputDecoration(labelText: 'Posicion de tiro', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'Pie', child: Text('Pie')),
                      DropdownMenuItem(value: 'Rodilla', child: Text('Rodilla')),
                      DropdownMenuItem(value: 'Tendido', child: Text('Tendido')),
                      DropdownMenuItem(value: 'Banco', child: Text('Banco')),
                    ],
                    onChanged: (v) => setStateDialog(() => posicionTemp = v),
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    value: iluminacionTemp,
                    decoration: const InputDecoration(labelText: 'Iluminacion', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'Artificial', child: Text('Artificial')),
                      DropdownMenuItem(value: 'Natural', child: Text('Natural')),
                      DropdownMenuItem(value: 'Mixta', child: Text('Mixta')),
                    ],
                    onChanged: (v) => setStateDialog(() => iluminacionTemp = v),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: tempCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Temperatura (°C)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: humedadCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Humedad (%)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: presionCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Presion (hPa)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: vientoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Viento (m/s)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: vientoDirCtrl,
                    decoration: const InputDecoration(labelText: 'Direccion del viento', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: notasCtrl,
                    decoration: const InputDecoration(labelText: 'Observaciones', border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('GUARDAR'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _guardarCambiosEnBD(
                    equipoTemp,
                    notasCtrl.text,
                    lugarCtrl.text,
                    distanciaMetros: _parseInt(distanciaCtrl.text),
                    posicionTiro: posicionTemp,
                    esInterior: interiorTemp,
                    temperaturaC: _parseDouble(tempCtrl.text),
                    humedadPct: _parseDouble(humedadCtrl.text),
                    presionHpa: _parseDouble(presionCtrl.text),
                    vientoMs: _parseDouble(vientoCtrl.text),
                    vientoDireccion: vientoDirCtrl.text.trim().isEmpty ? null : vientoDirCtrl.text.trim(),
                    iluminacion: iluminacionTemp,
                  );
                },
              )
            ],
          );
        }
      ),
    );
  }

  Future<void> _guardarCambiosEnBD(
    EquipoDetalle? nuevoEquipo,
    String nuevasNotas,
    String nuevoLugar, {
    int? distanciaMetros,
    String? posicionTiro,
    bool? esInterior,
    double? temperaturaC,
    double? humedadPct,
    double? presionHpa,
    double? vientoMs,
    String? vientoDireccion,
    String? iluminacion,
  }) async {
    if (nuevoEquipo == null || _sesion == null) return;
    setState(() => _cargando = true);

    await _entrenamientoService.actualizarSesion(
      idSesion: _sesion!.id!,
      nuevoIdEquipo: nuevoEquipo.id,
      nuevasNotas: nuevasNotas,
      nuevoLugar: nuevoLugar,
      distanciaMetros: distanciaMetros,
      posicionTiro: posicionTiro,
      esInterior: esInterior,
      temperaturaC: temperaturaC,
      humedadPct: humedadPct,
      presionHpa: presionHpa,
      vientoMs: vientoMs,
      vientoDireccion: vientoDireccion,
      iluminacion: iluminacion,
    );

    _cargarDatosCompletos();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sesión actualizada')));
  }

  void _generarPDF() async {
    if (_sesion == null) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generando PDF...'), duration: Duration(seconds: 1)));
    final perfil = await _perfilService.obtenerPerfil();
    await _pdfService.generarYMostrarPdf(
      sesion: _sesion!,
      disparos: _disparos,
      plantilla: _plantilla!,
      equipo: _equipoDetalle,
      municion: _municionDetalle,
      valorMinimo: _valorMinimo,
      anilloNegro: _anilloNegroInicio,
      esFondoNegro: _esFondoNegro,
      tieneMosca: _tieneMosca,
      tieneGuias: _tieneGuias,
      esEstiloDuelo: _esEstiloDuelo,
      perfil: perfil,
      lugar: _sesion!.lugar,
      observaciones: _sesion!.nota,
      condicionesTexto: _buildCondicionesTexto(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Scaffold(backgroundColor: AppColors.background, body: Center(child: CircularProgressIndicator()));

    int puntos = _disparos.fold(0, (sum, item) => sum + item.puntuacion.floor());
    int moscas = _disparos.where((d) => d.esMosca).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const TiroAmgAppBarTitle(section: 'Detalle de Tirada'),
        actions: [
          // --- 1. BOTÓN ESTADÍSTICAS (NUEVO) ---
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: "Analizar esta sesión",
            onPressed: () {
              Navigator.push(
                context, 
                MaterialPageRoute(
                  builder: (_) => EstadisticasScreen(
                    modo: 1, // Modo entrenamiento (o genérico)
                    idsSesionFijos: [widget.sesionId] // Pasamos el ID específico
                  )
                )
              );
            },
          ),
          
          // --- 2. BOTÓN EDITAR ---
          IconButton(icon: const Icon(Icons.edit), tooltip: "Editar Datos", onPressed: _editarDatosSesion),
          
          // --- 3. BOTÓN IMPRIMIR ---
          IconButton(icon: const Icon(Icons.print), onPressed: _generarPDF, tooltip: 'Imprimir / PDF')
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_plantilla?.nombreDisciplina ?? 'Desconocido', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.title)),
                      if (_sesion?.esCorreccionMira == true) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accentAnalytics.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadii.iconBox),
                            border: Border.all(color: AppColors.accentAnalytics.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            'Corrección de miras',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accentAnalytics,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 5),
                      if (_equipoDetalle != null)
                        Row(children: [Icon(Icons.hardware, size: 14, color: AppColors.subtitle), const SizedBox(width: 5), Text(_equipoDetalle!.nombre, style: TextStyle(color: AppColors.title, fontSize: 13, fontWeight: FontWeight.w500))]),
                      if (_municionDetalle != null)
                        Row(children: [Icon(Icons.local_fire_department, size: 14, color: AppColors.subtitle), const SizedBox(width: 5), Text('${_municionDetalle!.marca} (${_municionDetalle!.lote})', style: TextStyle(color: AppColors.title, fontSize: 13))]),
                      if (_sesion?.lugar != null && _sesion!.lugar!.isNotEmpty)
                        Row(children: [Icon(Icons.place, size: 14, color: AppColors.subtitle), const SizedBox(width: 5), Text(_sesion!.lugar!, style: TextStyle(color: AppColors.title, fontSize: 13))]),
                      if (_sesion?.distanciaMetros != null)
                        Row(children: [Icon(Icons.straighten, size: 14, color: AppColors.subtitle), const SizedBox(width: 5), Text('${_sesion!.distanciaMetros} m', style: TextStyle(color: AppColors.title, fontSize: 13))]),
                      if (_sesion?.temperaturaC != null || _sesion?.humedadPct != null || _sesion?.vientoMs != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Met: ${_sesion?.temperaturaC?.toStringAsFixed(1) ?? '-'}°C | '
                          'Hum: ${_sesion?.humedadPct?.toStringAsFixed(0) ?? '-'}% | '
                          'Viento: ${_sesion?.vientoMs?.toStringAsFixed(1) ?? '-'} m/s ${_sesion?.vientoDireccion ?? ''}',
                          style: TextStyle(color: AppColors.subtitle, fontSize: 12),
                        ),
                      ],
                      if (_sesion?.nota != null && _sesion!.nota!.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(_sesion!.nota!, style: TextStyle(color: AppColors.subtitle, fontSize: 12, fontStyle: FontStyle.italic), maxLines: 3, overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 8),
                      Text("${_sesion!.fecha.day}/${_sesion!.fecha.month}/${_sesion!.fecha.year} ${_sesion!.fecha.hour}:${_sesion!.fecha.minute.toString().padLeft(2,'0')}", style: TextStyle(color: AppColors.subtitleSoft, fontSize: 11)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$puntos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28, color: AppColors.accentTraining)),
                    Text("PUNTOS", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.accentTraining)),
                    if (moscas > 0) Text('$moscas moscas (x)', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accentCompetition, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          Expanded(
            child: Center(
              child: Padding(
                padding: _esFondoNegro ? const EdgeInsets.all(4.0) : const EdgeInsets.all(16.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    double diametro = min(constraints.maxWidth, constraints.maxHeight);
                    Size size = Size(diametro, diametro);
                    List<Offset> impactosPixels = _disparos.map((d) {
                      double radio = size.width / 2;
                      double cx = size.width / 2;
                      double cy = size.height / 2;
                      return Offset((d.x * radio) + cx, (d.y * radio) + cy);
                    }).toList();

                    return CustomPaint(
                      size: size,
                      painter: DianaPainter(
                        impactos: impactosPixels,
                        valorMinimo: _valorMinimo,
                        anilloNegroInicio: _anilloNegroInicio,
                        esFondoNegro: _esFondoNegro,
                        tieneMosca: _tieneMosca,
                        tieneGuias: _tieneGuias,
                        esEstiloDuelo: _esEstiloDuelo,
                        nombreCalibre: _equipoDetalle?.nombreCalibre,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text("Secuencia", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.subtitle)),
                  ),
                  const Divider(height: 1),
                  SizedBox(
                    height: 76,
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        itemCount: _disparos.length,
                        itemBuilder: (context, index) {
                          final tiro = _disparos[index];
                          final usaDecimal = _plantilla?.puntuacionDecimal == true;
                          final textoPuntos = usaDecimal
                              ? tiro.puntuacion.toStringAsFixed(1)
                              : '${tiro.puntuacion.round()}';
                          return Container(
                            width: 64,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                            decoration: BoxDecoration(
                              color: tiro.esMosca
                                  ? AppColors.accentCompetition.withValues(alpha: 0.1)
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(AppRadii.iconBox),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('#${tiro.numero}', style: TextStyle(fontSize: 10, color: AppColors.subtitle)),
                                Text(
                                  textoPuntos,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.title),
                                ),
                                SizedBox(
                                  height: 12,
                                  child: tiro.esMosca
                                      ? Text('X', style: TextStyle(fontSize: 11, color: AppColors.accentCompetition, fontWeight: FontWeight.bold))
                                      : null,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
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
  final String? nombreCalibre;
  final Offset? centroGravedad;

  DianaPainter({
    required this.impactos,
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

    final paintFondo = Paint()
      ..color = esFondoNegro ? const Color(0xFF1A1A1A) : Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paintFondo);

    int totalZonas = 11 - valorMinimo; 
    if (totalZonas < 1) totalZonas = 1;
    
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
       anchoZona = paso;
    } else {
       for (int i = 0; i < totalZonas; i++) {
          int numeroAnillo = valorMinimo + i;
          double r = radius - (i * (radius / totalZonas));
          
          if (numeroAnillo >= anilloNegroInicio) {
            canvas.drawCircle(center, r, paintNegro);
            canvas.drawCircle(center, r, paintLineaBlanca);
            if (numeroAnillo < 10) {
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

    final radioImpacto = ImpactoVisual.radioPx(
      anchoZona: anchoZona,
      nombreCalibre: nombreCalibre,
    );
    for (final p in impactos) {
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
        style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold) 
      ),
      textDirection: TextDirection.ltr
    );
    tp.layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant DianaPainter oldDelegate) =>
      oldDelegate.impactos != impactos ||
      oldDelegate.nombreCalibre != nombreCalibre ||
      oldDelegate.valorMinimo != valorMinimo ||
      oldDelegate.anilloNegroInicio != anilloNegroInicio ||
      oldDelegate.esFondoNegro != esFondoNegro ||
      oldDelegate.tieneMosca != tieneMosca ||
      oldDelegate.tieneGuias != tieneGuias ||
      oldDelegate.esEstiloDuelo != esEstiloDuelo ||
      oldDelegate.centroGravedad != centroGravedad;
}