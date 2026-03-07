import 'package:flutter/material.dart';
import '../models/sesion_model.dart';
import '../models/equipo_model.dart';
import '../models/municion_model.dart';
import '../services/entrenamiento_service.dart';
import '../services/pdf_service.dart';
import '../services/perfil_service.dart'; 
import '../services/equipo_service.dart';
import '../services/municion_service.dart';
import 'sesion_detalle_screen.dart';
import 'estadisticas_screen.dart'; // <--- NUEVO IMPORT

class CompeticionHistorialDetalleScreen extends StatefulWidget {
  final int idModalidad;
  final DateTime fecha;
  final String nombreTorneo;
  final int totalPuntos;

  const CompeticionHistorialDetalleScreen({
    super.key,
    required this.idModalidad,
    required this.fecha,
    required this.nombreTorneo,
    required this.totalPuntos,
  });

  @override
  State<CompeticionHistorialDetalleScreen> createState() => _CompeticionHistorialDetalleScreenState();
}

class _CompeticionHistorialDetalleScreenState extends State<CompeticionHistorialDetalleScreen> {
  final _service = EntrenamientoService();
  final _pdfService = PdfService();
  final _perfilService = PerfilService();
  final _equipoService = EquipoService();
  final _municionService = MunicionService();

  List<SesionResumen> _fases = [];
  bool _cargando = true;

  // Datos editables del torneo
  EquipoDetalle? _equipoUsado;
  MunicionDetalle? _municionUsada;
  String _notasGuardadas = "";
  String _lugarGuardado = ""; 
  int? _distanciaMetros;
  String? _posicionTiro;
  bool _esInterior = true;
  double? _temperaturaC;
  double? _humedadPct;
  double? _presionHpa;
  double? _vientoMs;
  String? _vientoDireccion;
  String? _iluminacion;

  String _buildCondicionesTexto() {
    final parts = <String>[];
    if (_distanciaMetros != null) parts.add('${_distanciaMetros}m');
    if (_posicionTiro != null && _posicionTiro!.isNotEmpty) parts.add('Posición: $_posicionTiro');
    parts.add(_esInterior ? 'Interior' : 'Exterior');
    if (_iluminacion != null && _iluminacion!.isNotEmpty) parts.add('Luz: $_iluminacion');
    if (_temperaturaC != null) parts.add('T: ${_temperaturaC!.toStringAsFixed(1)}°C');
    if (_humedadPct != null) parts.add('H: ${_humedadPct!.toStringAsFixed(0)}%');
    if (_presionHpa != null) parts.add('P: ${_presionHpa!.toStringAsFixed(0)} hPa');
    if (_vientoMs != null) {
      final dir = (_vientoDireccion == null || _vientoDireccion!.isEmpty) ? '' : ' $_vientoDireccion';
      parts.add('V: ${_vientoMs!.toStringAsFixed(1)} m/s$dir');
    }
    return parts.join(' | ');
  }

  @override
  void initState() {
    super.initState();
    _cargarDatosCompletos();
  }

  void _cargarDatosCompletos() async {
    final datos = await _service.obtenerFasesDeTorneoRealizado(widget.idModalidad, widget.fecha);
    
    EquipoDetalle? equipoDetectado;
    String notasDetectadas = "";
    String lugarDetectado = "";
    int? distanciaDetectada;
    String? posicionDetectada;
    bool interiorDetectado = true;
    double? temperaturaDetectada;
    double? humedadDetectada;
    double? presionDetectada;
    double? vientoDetectado;
    String? vientoDirDetectada;
    String? iluminacionDetectada;

    if (datos.isNotEmpty) {
      int idSesion = datos.first.id;
      final sesionFull = await _service.obtenerSesionPorId(idSesion);
      if (sesionFull != null) {
        try {
          final equipos = await _equipoService.obtenerEquiposDetallados();
          equipoDetectado = equipos.firstWhere((e) => e.id == sesionFull.idEquipo);
        } catch (_) {}
        
        if (sesionFull.nota != null && !sesionFull.nota!.contains("Torneo:")) {
            notasDetectadas = sesionFull.nota!;
        }
        lugarDetectado = sesionFull.lugar ?? "";
        if (sesionFull.idMunicion != null) {
          _municionUsada = await _municionService.obtenerDetallePorId(sesionFull.idMunicion!);
        }
        distanciaDetectada = sesionFull.distanciaMetros;
        posicionDetectada = sesionFull.posicionTiro;
        interiorDetectado = sesionFull.esInterior ?? true;
        temperaturaDetectada = sesionFull.temperaturaC;
        humedadDetectada = sesionFull.humedadPct;
        presionDetectada = sesionFull.presionHpa;
        vientoDetectado = sesionFull.vientoMs;
        vientoDirDetectada = sesionFull.vientoDireccion;
        iluminacionDetectada = sesionFull.iluminacion;
      }
    }

    if (mounted) {
      setState(() {
        _fases = datos;
        _equipoUsado = equipoDetectado;
        _notasGuardadas = notasDetectadas;
        _lugarGuardado = lugarDetectado;
        _distanciaMetros = distanciaDetectada;
        _posicionTiro = posicionDetectada;
        _esInterior = interiorDetectado;
        _temperaturaC = temperaturaDetectada;
        _humedadPct = humedadDetectada;
        _presionHpa = presionDetectada;
        _vientoMs = vientoDetectado;
        _vientoDireccion = vientoDirDetectada;
        _iluminacion = iluminacionDetectada;
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

  void _editarDatosTorneo() async {
    final equipos = await _equipoService.obtenerEquiposDetallados();
    
    EquipoDetalle? equipoTemp;
    if (_equipoUsado != null) {
      try {
        equipoTemp = equipos.firstWhere((e) => e.id == _equipoUsado!.id);
      } catch (_) {}
    }
    if (equipoTemp == null && equipos.isNotEmpty) equipoTemp = equipos.first;
    
    final lugarCtrl = TextEditingController(text: _lugarGuardado);
    final notasCtrl = TextEditingController(text: _notasGuardadas);
    final distanciaCtrl = TextEditingController(text: _distanciaMetros?.toString() ?? "");
    final tempCtrl = TextEditingController(text: _temperaturaC?.toString() ?? "");
    final humedadCtrl = TextEditingController(text: _humedadPct?.toString() ?? "");
    final presionCtrl = TextEditingController(text: _presionHpa?.toString() ?? "");
    final vientoCtrl = TextEditingController(text: _vientoMs?.toString() ?? "");
    final vientoDirCtrl = TextEditingController(text: _vientoDireccion ?? "");
    String? posicionTemp = _posicionTiro;
    String? iluminacionTemp = _iluminacion;
    bool interiorTemp = _esInterior;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Editar Datos del Torneo'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<EquipoDetalle>(
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Arma Utilizada', border: OutlineInputBorder()),
                    initialValue: equipoTemp,
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
                    initialValue: posicionTemp,
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
                    initialValue: iluminacionTemp,
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
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('GUARDAR CAMBIOS'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
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
    if (nuevoEquipo == null) return;
    setState(() => _cargando = true);

    await _service.actualizarDatosTorneoCompleto(
      idModalidad: widget.idModalidad,
      fecha: widget.fecha,
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

    if (!mounted) return;
    setState(() {
        _equipoUsado = nuevoEquipo;
        _notasGuardadas = nuevasNotas;
        _lugarGuardado = nuevoLugar;
        _distanciaMetros = distanciaMetros;
        _posicionTiro = posicionTiro;
        _esInterior = esInterior ?? true;
        _temperaturaC = temperaturaC;
        _humedadPct = humedadPct;
        _presionHpa = presionHpa;
        _vientoMs = vientoMs;
        _vientoDireccion = vientoDireccion;
        _iluminacion = iluminacion;
        _cargando = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Datos actualizados y guardados.')));
  }

  void _generarPDF() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generando PDF...'), duration: Duration(seconds: 1)));

    final grupos = await _service.obtenerDatosInformeTorneo(widget.idModalidad, widget.fecha);
    if (grupos.isEmpty) return;

    final perfil = await _perfilService.obtenerPerfil();
    
    await _pdfService.generarInformeTorneoProfesional(
      nombreTorneo: widget.nombreTorneo,
      fecha: widget.fecha,
      grupos: grupos,
      perfil: perfil,
      equipo: _equipoUsado,
      municion: _municionUsada,
      observaciones: _notasGuardadas, 
      lugar: _lugarGuardado, 
      condicionesTexto: _buildCondicionesTexto(),
    );
  }

  // --- FUNCIÓN NUEVA: IR A ESTADÍSTICAS ---
  void _irAEstadisticas() {
    if (_fases.isEmpty) return;
    
    // Extraemos los IDs de todas las sesiones que componen este torneo
    List<int> idsSesiones = _fases.map((f) => f.id).toList();
    
    Navigator.push(
      context, 
      MaterialPageRoute(
        builder: (_) => EstadisticasScreen(
          modo: 2, // Modo competición
          idsSesionFijos: idsSesiones, // Filtramos SOLO por este torneo
        )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Detalle Competición'),
        backgroundColor: Colors.amber[800],
        actions: [
          // BOTÓN ESTADÍSTICAS (¡NUEVO!)
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: "Analizar Torneo",
            onPressed: _irAEstadisticas,
          ),
          IconButton(icon: const Icon(Icons.edit), tooltip: "Editar Datos", onPressed: _editarDatosTorneo),
          IconButton(icon: const Icon(Icons.print), tooltip: "Imprimir Acta", onPressed: _generarPDF)
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                     Expanded(child: Text(widget.nombreTorneo, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                     Container(
                       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                       decoration: BoxDecoration(color: Colors.amber[100], borderRadius: BorderRadius.circular(20)),
                       child: Text('${widget.totalPuntos} pts', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber[900])),
                     )
                  ]
                ),
                const SizedBox(height: 10),
                Row(children: [
                    const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                    const SizedBox(width: 5),
                    Text("${widget.fecha.day}/${widget.fecha.month}/${widget.fecha.year}", style: const TextStyle(color: Colors.black87)),
                ]),
                const SizedBox(height: 5),
                Row(children: [
                    const Icon(Icons.hardware, size: 14, color: Colors.grey),
                    const SizedBox(width: 5),
                    Text(_equipoUsado?.nombre ?? "Arma no especificada", style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                ]),
                if (_municionUsada != null) ...[
                    const SizedBox(height: 5),
                    Row(children: [
                        const Icon(Icons.local_fire_department, size: 14, color: Colors.grey),
                        const SizedBox(width: 5),
                        Text('${_municionUsada!.marca} (${_municionUsada!.lote})', style: const TextStyle(color: Colors.black87)),
                    ]),
                ],
                if (_lugarGuardado.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(children: [
                        const Icon(Icons.place, size: 14, color: Colors.grey),
                        const SizedBox(width: 5),
                        Text(_lugarGuardado, style: const TextStyle(color: Colors.black87)),
                    ]),
                ],
                if (_distanciaMetros != null) ...[
                    const SizedBox(height: 5),
                    Row(children: [
                        const Icon(Icons.straighten, size: 14, color: Colors.grey),
                        const SizedBox(width: 5),
                        Text('$_distanciaMetros m', style: const TextStyle(color: Colors.black87)),
                    ]),
                ],
                if (_temperaturaC != null || _humedadPct != null || _vientoMs != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      'Met: ${_temperaturaC?.toStringAsFixed(1) ?? '-'}°C | '
                      'Hum: ${_humedadPct?.toStringAsFixed(0) ?? '-'}% | '
                      'Viento: ${_vientoMs?.toStringAsFixed(1) ?? '-'} m/s ${_vientoDireccion ?? ''}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                ],
                if (_notasGuardadas.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.comment, size: 14, color: Colors.grey),
                        const SizedBox(width: 5),
                        Expanded(child: Text(_notasGuardadas, style: const TextStyle(color: Colors.black87, fontStyle: FontStyle.italic))),
                    ]),
                ]
              ],
            ),
          ),
          
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text("Fases del Torneo", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
          ),

          Expanded(
            child: _cargando 
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
              itemCount: _fases.length,
              itemBuilder: (context, index) {
                final fase = _fases[index];
                String descripcion = fase.nota?.split('|').last.trim() ?? "Serie ${index + 1}";
                bool esEnsayo = fase.nota != null && fase.nota!.toLowerCase().contains('ensayo');

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  color: esEnsayo ? Colors.orange[50] : Colors.white,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: esEnsayo ? Colors.orange[200] : Colors.amber.withValues(alpha: 0.2),
                      child: Text('${index + 1}', style: TextStyle(color: Colors.amber[900], fontWeight: FontWeight.bold)),
                    ),
                    title: Text(fase.nombreTitulo),
                    subtitle: Text(descripcion + (esEnsayo ? " (No suma)" : "")),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${fase.totalPuntos} pts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: esEnsayo ? Colors.grey : Colors.black)),
                        const SizedBox(width: 10),
                        const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      ],
                    ),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SesionDetalleScreen(sesionId: fase.id))),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}