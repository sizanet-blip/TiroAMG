import 'package:flutter/material.dart';
import '../models/sesion_model.dart';
import '../models/informe_model.dart';
import '../models/equipo_model.dart';
import '../models/municion_model.dart';
import '../services/entrenamiento_service.dart';
import '../services/pdf_service.dart';
import '../services/perfil_service.dart'; 
import '../services/equipo_service.dart';
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

  List<SesionResumen> _fases = [];
  bool _cargando = true;

  // Datos editables del torneo
  EquipoDetalle? _equipoUsado;
  String _notasGuardadas = "";
  String _lugarGuardado = ""; 

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
      }
    }

    if (mounted) {
      setState(() {
        _fases = datos;
        _equipoUsado = equipoDetectado;
        _notasGuardadas = notasDetectadas;
        _lugarGuardado = lugarDetectado;
        _cargando = false;
      });
    }
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
                label: const Text('GUARDAR CAMBIOS'),
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
    if (nuevoEquipo == null) return;
    setState(() => _cargando = true);

    await _service.actualizarDatosTorneoCompleto(
      idModalidad: widget.idModalidad,
      fecha: widget.fecha,
      nuevoIdEquipo: nuevoEquipo.id,
      nuevasNotas: nuevasNotas,
      nuevoLugar: nuevoLugar,
    );

    setState(() {
        _equipoUsado = nuevoEquipo;
        _notasGuardadas = nuevasNotas;
        _lugarGuardado = nuevoLugar;
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
      observaciones: _notasGuardadas, 
      lugar: _lugarGuardado, 
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
                if (_lugarGuardado.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(children: [
                        const Icon(Icons.place, size: 14, color: Colors.grey),
                        const SizedBox(width: 5),
                        Text(_lugarGuardado, style: const TextStyle(color: Colors.black87)),
                    ]),
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
                      backgroundColor: esEnsayo ? Colors.orange[200] : Colors.amber.withOpacity(0.2),
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