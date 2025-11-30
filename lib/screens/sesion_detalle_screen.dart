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
import '../services/perfil_service.dart'; // Nuevo para el PDF
import '../widgets/diana_painter.dart';

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
  final _perfilService = PerfilService(); // Nuevo
  
  final ScrollController _scrollController = ScrollController();

  Sesion? _sesion;
  PlantillaTiempos? _plantilla;
  List<Disparo> _disparos = [];
  bool _cargando = true;

  // Datos extra para PDF y Edición
  EquipoDetalle? _equipoDetalle;

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

  // --- EDITAR DATOS SESIÓN ---
  void _editarDatosSesion() async {
    final equipos = await _equipoService.obtenerEquiposDetallados();
    
    EquipoDetalle? equipoTemp;
    if (_equipoDetalle != null) {
       try { equipoTemp = equipos.firstWhere((e) => e.id == _equipoDetalle!.id); } catch (_) {}
    }
    if (equipoTemp == null && equipos.isNotEmpty) equipoTemp = equipos.first;

    final lugarCtrl = TextEditingController(text: _sesion?.lugar ?? "");
    final notasCtrl = TextEditingController(text: _sesion?.nota ?? "");

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
                    controller: notasCtrl,
                    decoration: const InputDecoration(labelText: 'Observaciones', border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('GUARDAR'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _guardarCambiosEnBD(equipoTemp, notasCtrl.text, lugarCtrl.text);
                },
              )
            ],
          );
        }
      ),
    );
  }

  Future<void> _guardarCambiosEnBD(EquipoDetalle? nuevoEquipo, String nuevasNotas, String nuevoLugar) async {
    if (nuevoEquipo == null || _sesion == null) return;
    setState(() => _cargando = true);

    await _entrenamientoService.actualizarSesion(
      idSesion: _sesion!.id!,
      nuevoIdEquipo: nuevoEquipo.id,
      nuevasNotas: nuevasNotas,
      nuevoLugar: nuevoLugar
    );

    // Recargamos para ver los cambios
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
      municion: null, 
      valorMinimo: _valorMinimo,
      anilloNegro: _anilloNegroInicio,
      esFondoNegro: _esFondoNegro,
      tieneMosca: _tieneMosca,
      tieneGuias: _tieneGuias,
      esEstiloDuelo: _esEstiloDuelo,
      perfil: perfil,
      lugar: _sesion!.lugar, // Usamos lo guardado
      observaciones: _sesion!.nota, // Usamos lo guardado
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    int puntos = _disparos.fold(0, (sum, item) => sum + item.puntuacion.floor());
    int moscas = _disparos.where((d) => d.esMosca).length;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text('Detalle de Tirada'),
        backgroundColor: Colors.indigo,
        elevation: 0,
        actions: [
          // BOTÓN EDITAR
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: "Editar Datos",
            onPressed: _editarDatosSesion,
          ),
          // BOTÓN PDF
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _generarPDF,
            tooltip: 'Imprimir / PDF',
          )
        ],
      ),
      body: Column(
        children: [
          // --- CABECERA ---
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))]
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _plantilla?.nombreDisciplina ?? 'Desconocido', 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo),
                      ),
                      const SizedBox(height: 5),
                      // Mostrar Arma
                      if (_equipoDetalle != null)
                        Row(children: [
                            const Icon(Icons.hardware, size: 14, color: Colors.grey),
                            const SizedBox(width: 5),
                            Text(_equipoDetalle!.nombre, style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w500)),
                        ]),
                      // Mostrar Lugar
                      if (_sesion?.lugar != null && _sesion!.lugar!.isNotEmpty)
                        Row(children: [
                            const Icon(Icons.place, size: 14, color: Colors.grey),
                            const SizedBox(width: 5),
                            Text(_sesion!.lugar!, style: const TextStyle(color: Colors.black87, fontSize: 13)),
                        ]),
                      // Mostrar Nota
                      if (_sesion?.nota != null && _sesion!.nota!.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          _sesion!.nota!, 
                          style: const TextStyle(color: Colors.blueGrey, fontSize: 12, fontStyle: FontStyle.italic),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        "${_sesion!.fecha.day}/${_sesion!.fecha.month}/${_sesion!.fecha.year} ${_sesion!.fecha.hour}:${_sesion!.fecha.minute.toString().padLeft(2,'0')}",
                        style: TextStyle(color: Colors.grey[400], fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 15),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.indigo[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.indigo.withOpacity(0.2))
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$puntos', 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 28, color: Colors.indigo)
                          ),
                          const Text("PUNTOS", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.indigoAccent)),
                        ],
                      ),
                    ),
                    if (moscas > 0) 
                      Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Text(
                          '$moscas moscas (x)', 
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 12)
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // --- DIANA ---
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
                      double centerX = size.width / 2;
                      double centerY = size.height / 2;
                      return Offset((d.x * radio) + centerX, (d.y * radio) + centerY);
                    }).toList();

                    return Hero(
                      tag: 'diana_${widget.sesionId}',
                      child: CustomPaint(
                        size: size,
                        painter: DianaPainter(
                          impactos: impactosPixels,
                          valorMinimo: _valorMinimo,
                          anilloNegroInicio: _anilloNegroInicio,
                          esFondoNegro: _esFondoNegro,
                          tieneMosca: _tieneMosca,
                          tieneGuias: _tieneGuias,
                          esEstiloDuelo: _esEstiloDuelo,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          
          // --- LISTA DE TIROS ---
          Container(
            height: 140, 
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      "Secuencia", 
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _disparos.length,
                        itemBuilder: (context, index) {
                          final tiro = _disparos[index];
                          return Container(
                            width: 64, 
                            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: tiro.esMosca ? Colors.amber.withOpacity(0.1) : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3, offset: const Offset(0, 1))]
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FittedBox(
                                  child: Text('#${tiro.numero}', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                                ),
                                const SizedBox(height: 2),
                                Expanded(
                                  child: Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        '${tiro.puntuacion.toInt()}', 
                                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)
                                      ),
                                    ),
                                  ),
                                ),
                                if(tiro.esMosca) 
                                  const FittedBox(
                                    child: Text('X', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold))
                                  )
                                else 
                                  const SizedBox(height: 12), 
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