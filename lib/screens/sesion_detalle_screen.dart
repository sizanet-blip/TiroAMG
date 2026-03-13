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
import '../services/license_service.dart';
import '../services/license_permissions_service.dart';
import '../models/licencia_model.dart';
import '../utils/license_ui_helper.dart';
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
  final LicenseService _licenseService = const LicenseService();
  final LicensePermissionsService _permissions =
      const LicensePermissionsService();

  final ScrollController _scrollController = ScrollController();

  Sesion? _sesion;
  PlantillaTiempos? _plantilla;
  List<Disparo> _disparos = [];
  bool _cargando = true;
  LicenciaLocal? _licenciaActual;

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
  double? _dianaAnchoExteriorMm;
  double? _calibreMm;

  @override
  void initState() {
    super.initState();
    _cargarDatosCompletos();
    _cargarLicenciaActual();
  }

  Future<void> _cargarLicenciaActual() async {
    final licencia = await _licenseService.obtenerLicenciaLocal();
    if (!mounted) return;
    setState(() => _licenciaActual = licencia);
  }

  Future<void> _cargarDatosCompletos() async {
    final sesion =
        await _entrenamientoService.obtenerSesionPorId(widget.sesionId);
    if (sesion == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final disparos =
        await _entrenamientoService.obtenerDisparosDeSesion(widget.sesionId);
    final plantilla = await _plantillaService.obtenerPorId(sesion.idPlantilla);

    try {
      var listEquipos = await _equipoService.obtenerEquiposDetallados();
      _equipoDetalle = listEquipos.firstWhere((e) => e.id == sesion.idEquipo);
    } catch (e) {
      debugPrint('No se pudo resolver el equipo de la sesión: $e');
    }

    if (sesion.idMunicion != null) {
      _municionDetalle =
          await _municionService.obtenerDetallePorId(sesion.idMunicion!);
    } else {
      _municionDetalle = null;
    }

    if (plantilla != null && plantilla.idTipoDiana != null) {
      final dianas = await _catalogoService.obtenerTiposDiana();
      try {
        final dianaConfig =
            dianas.firstWhere((d) => d.id == plantilla.idTipoDiana);
        setState(() {
          _valorMinimo = dianaConfig.valorMinimo;
          _anilloNegroInicio = dianaConfig.anilloNegroInicio;
          _esFondoNegro = dianaConfig.esFondoNegro;
          _tieneMosca = dianaConfig.tieneMosca;
          _tieneGuias = dianaConfig.tieneGuias;
          _esEstiloDuelo = _anilloNegroInicio <= 5;
          _dianaAnchoExteriorMm = dianaConfig.anchoExteriorMm;
        });
      } catch (e) {
        debugPrint('No se pudo cargar la configuración de diana: $e');
      }
    }

    _calibreMm = _resolverCalibreMm(
      _municionDetalle?.nombreCalibre,
      _equipoDetalle?.nombreCalibre,
    );

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
    if (s.posicionTiro != null && s.posicionTiro!.isNotEmpty) {
      parts.add('Posición: ${s.posicionTiro}');
    }
    if (s.esInterior != null) {
      parts.add(s.esInterior! ? 'Interior' : 'Exterior');
    }
    if (s.iluminacion != null && s.iluminacion!.isNotEmpty) {
      parts.add('Luz: ${s.iluminacion}');
    }
    if (s.temperaturaC != null) {
      parts.add('T: ${s.temperaturaC!.toStringAsFixed(1)}°C');
    }
    if (s.humedadPct != null) {
      parts.add('H: ${s.humedadPct!.toStringAsFixed(0)}%');
    }
    if (s.presionHpa != null) {
      parts.add('P: ${s.presionHpa!.toStringAsFixed(0)} hPa');
    }
    if (s.vientoMs != null) {
      final dir = (s.vientoDireccion == null || s.vientoDireccion!.isEmpty)
          ? ''
          : ' ${s.vientoDireccion}';
      parts.add('V: ${s.vientoMs!.toStringAsFixed(1)} m/s$dir');
    }
    return parts.join(' | ');
  }

  _ScoredShot _calcularDesdePosicion({
    required double x,
    required double y,
  }) {
    final distancia = sqrt((x * x) + (y * y));
    if (distancia > 1.0) {
      return const _ScoredShot(puntuacion: 0, esMosca: false);
    }

    final totalZonas = (11 - _valorMinimo) <= 0 ? 1 : (11 - _valorMinimo);
    var valor = (11 - (distancia * totalZonas)).floor();
    if (valor < _valorMinimo) valor = 0;
    if (valor > 10) valor = 10;

    final esMosca = _tieneMosca && distancia < (0.05 * (10 / totalZonas));
    return _ScoredShot(puntuacion: valor, esMosca: esMosca);
  }

  String _formatearPuntuacionEditable(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.0001) {
      return rounded.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }

  double? _resolverCalibreMm(String? calibreMunicion, String? calibreEquipo) {
    final fromMunicion = _extraerCalibreMm(calibreMunicion);
    if (fromMunicion != null) {
      return fromMunicion;
    }
    return _extraerCalibreMm(calibreEquipo);
  }

  double? _extraerCalibreMm(String? texto) {
    if (texto == null || texto.trim().isEmpty) {
      return null;
    }
    final source = texto.toLowerCase().replaceAll(',', '.');

    final mmMatch = RegExp(r'(\d+(?:\.\d+)?)\s*mm').firstMatch(source);
    if (mmMatch != null) {
      final value = double.tryParse(mmMatch.group(1)!);
      if (value != null && value >= 2.0 && value <= 20.0) {
        return value;
      }
    }

    final inchMatch = RegExp(r'(?<!\d)\.(\d{2,3})(?!\d)').firstMatch(source);
    if (inchMatch != null) {
      final raw = inchMatch.group(1)!;
      final inches =
          raw.length == 2 ? int.parse(raw) / 100.0 : int.parse(raw) / 1000.0;
      final mm = inches * 25.4;
      if (mm >= 2.0 && mm <= 20.0) {
        return mm;
      }
    }

    return null;
  }

  Future<void> _editarPosicionVisual({
    required BuildContext parentContext,
    required _EditableDisparo row,
    required StateSetter setDialogState,
  }) async {
    var xTemp = row.x;
    var yTemp = row.y;
    var paso = 0.01;

    void updateFromLocal(Offset local, Size size, StateSetter setVisualState) {
      final center = Offset(size.width / 2, size.height / 2);
      final radius = size.width / 2;
      final vector = local - center;
      final clamped = vector.distance <= radius
          ? local
          : center + (vector / vector.distance) * radius;
      setVisualState(() {
        xTemp = (clamped.dx - center.dx) / radius;
        yTemp = (clamped.dy - center.dy) / radius;
      });
    }

    void nudge(double dx, double dy, StateSetter setVisualState) {
      final candidato = Offset(xTemp + dx, yTemp + dy);
      final distancia = candidato.distance;
      setVisualState(() {
        if (distancia <= 1.0) {
          xTemp = candidato.dx;
          yTemp = candidato.dy;
          return;
        }
        xTemp = candidato.dx / distancia;
        yTemp = candidato.dy / distancia;
      });
    }

    await showDialog<void>(
      context: parentContext,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setVisualState) {
          final auto = _calcularDesdePosicion(x: xTemp, y: yTemp);
          final screen = MediaQuery.sizeOf(ctx);
          final side = (screen.width * 0.72).clamp(220.0, 360.0).toDouble();
          final radio = side / 2;
          final cx = side / 2;
          final cy = side / 2;
          final marker = Offset((xTemp * radio) + cx, (yTemp * radio) + cy);

          return AlertDialog(
            title: Text('Posición del tiro #${row.numero}'),
            content: SizedBox(
              width: side,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Toca o arrastra sobre la diana para colocar el impacto.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: GestureDetector(
                      onTapDown: (details) => updateFromLocal(
                        details.localPosition,
                        Size(side, side),
                        setVisualState,
                      ),
                      onPanUpdate: (details) => updateFromLocal(
                        details.localPosition,
                        Size(side, side),
                        setVisualState,
                      ),
                      child: SizedBox(
                        width: side,
                        height: side,
                        child: CustomPaint(
                          painter: DianaPainter(
                            impactos: [marker],
                            valorMinimo: _valorMinimo,
                            anilloNegroInicio: _anilloNegroInicio,
                            esFondoNegro: _esFondoNegro,
                            tieneMosca: _tieneMosca,
                            tieneGuias: _tieneGuias,
                            esEstiloDuelo: _esEstiloDuelo,
                            diametroImpactoMm: _calibreMm,
                            diametroDianaMm: _dianaAnchoExteriorMm,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                          label: Text(
                              'Auto: ${auto.puntuacion}${auto.esMosca ? 'X' : ''}')),
                      Chip(label: Text('X: ${xTemp.toStringAsFixed(3)}')),
                      Chip(label: Text('Y: ${yTemp.toStringAsFixed(3)}')),
                      Chip(
                          label: Text(
                              'Paso: ${paso.toStringAsFixed(3)} (${(paso * 100).toStringAsFixed(1)}%)')),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SegmentedButton<double>(
                        segments: const [
                          ButtonSegment<double>(value: 0.02, label: Text('2%')),
                          ButtonSegment<double>(value: 0.01, label: Text('1%')),
                          ButtonSegment<double>(
                              value: 0.005, label: Text('0.5%')),
                        ],
                        selected: {paso},
                        onSelectionChanged: (values) {
                          setVisualState(() => paso = values.first);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Arriba',
                        onPressed: () => nudge(0, -paso, setVisualState),
                        icon: const Icon(Icons.keyboard_arrow_up),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Izquierda',
                        onPressed: () => nudge(-paso, 0, setVisualState),
                        icon: const Icon(Icons.keyboard_arrow_left),
                      ),
                      const SizedBox(width: 14),
                      IconButton(
                        tooltip: 'Abajo',
                        onPressed: () => nudge(0, paso, setVisualState),
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                      const SizedBox(width: 14),
                      IconButton(
                        tooltip: 'Derecha',
                        onPressed: () => nudge(paso, 0, setVisualState),
                        icon: const Icon(Icons.keyboard_arrow_right),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              OutlinedButton(
                onPressed: () {
                  setDialogState(() {
                    row.x = xTemp;
                    row.y = yTemp;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Aplicar posición'),
              ),
              FilledButton(
                onPressed: () {
                  setDialogState(() {
                    row.x = xTemp;
                    row.y = yTemp;
                    row.puntuacion = auto.puntuacion.toDouble();
                    row.esMosca = auto.esMosca;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Aplicar + auto puntuar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _editarTirosSesion() async {
    if (_sesion == null || _disparos.isEmpty) return;

    final editable = _disparos
        .map(
          (d) => _EditableDisparo(
            id: d.id,
            numero: d.numero,
            x: d.x,
            y: d.y,
            puntuacion: d.puntuacion,
            esMosca: d.esMosca,
          ),
        )
        .toList();

    var guardando = false;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final screenSize = MediaQuery.sizeOf(ctx);
          final dialogWidth =
              (screenSize.width - 24).clamp(320.0, 920.0).toDouble();
          final dialogMaxHeight =
              (screenSize.height * 0.78).clamp(280.0, 650.0).toDouble();

          return AlertDialog(
            title: const Text('Editar tiros'),
            content: SizedBox(
              width: dialogWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: dialogMaxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: guardando
                              ? null
                              : () {
                                  setDialogState(() {
                                    for (final row in editable) {
                                      final calc = _calcularDesdePosicion(
                                        x: row.x,
                                        y: row.y,
                                      );
                                      row.puntuacion =
                                          calc.puntuacion.toDouble();
                                      row.esMosca = calc.esMosca;
                                    }
                                  });
                                },
                          icon: const Icon(Icons.auto_fix_high),
                          label: const Text('Auto puntuar desde posición'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Edita posición de forma visual (sin coordenadas) y '
                      'ajusta la puntuación solo cuando lo necesites.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        itemCount: editable.length,
                        separatorBuilder: (_, __) => const Divider(height: 10),
                        itemBuilder: (_, i) {
                          final row = editable[i];
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: 38,
                                child: Text(
                                  '#${row.numero}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: guardando
                                    ? null
                                    : () => _editarPosicionVisual(
                                          parentContext: ctx,
                                          row: row,
                                          setDialogState: setDialogState,
                                        ),
                                icon: const Icon(Icons.control_camera),
                                label: const Text('Posición'),
                              ),
                              SizedBox(
                                width: 88,
                                child: TextFormField(
                                  initialValue: _formatearPuntuacionEditable(
                                      row.puntuacion),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: 'Ptos',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  onChanged: (v) {
                                    final parsed = double.tryParse(
                                      v.trim().replaceAll(',', '.'),
                                    );
                                    if (parsed != null) {
                                      row.puntuacion = parsed;
                                    }
                                  },
                                ),
                              ),
                              Column(
                                children: [
                                  const Text(
                                    'Mosca',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  Switch(
                                    value: row.esMosca,
                                    onChanged: guardando
                                        ? null
                                        : (v) => setDialogState(
                                              () => row.esMosca = v,
                                            ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: guardando ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: guardando
                    ? null
                    : () async {
                        setDialogState(() => guardando = true);
                        final nuevosDisparos = editable
                            .map(
                              (e) => Disparo(
                                id: e.id,
                                idSesion: _sesion!.id,
                                numero: e.numero,
                                x: e.x,
                                y: e.y,
                                puntuacion: e.puntuacion,
                                esMosca: e.esMosca,
                              ),
                            )
                            .toList();

                        await _entrenamientoService.actualizarDisparosSesion(
                          idSesion: _sesion!.id!,
                          disparos: nuevosDisparos,
                        );

                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        await _cargarDatosCompletos();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Tiros actualizados correctamente.'),
                          ),
                        );
                      },
                icon: const Icon(Icons.save),
                label: Text(guardando ? 'Guardando...' : 'Guardar cambios'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _editarDatosSesion() async {
    final equipos = await _equipoService.obtenerEquiposDetallados();

    EquipoDetalle? equipoTemp;
    if (_equipoDetalle != null) {
      try {
        equipoTemp = equipos.firstWhere((e) => e.id == _equipoDetalle!.id);
      } catch (_) {}
    }
    if (equipoTemp == null && equipos.isNotEmpty) equipoTemp = equipos.first;

    final lugarCtrl = TextEditingController(text: _sesion?.lugar ?? "");
    final notasCtrl = TextEditingController(text: _sesion?.nota ?? "");
    final distanciaCtrl =
        TextEditingController(text: _sesion?.distanciaMetros?.toString() ?? "");
    final tempCtrl =
        TextEditingController(text: _sesion?.temperaturaC?.toString() ?? "");
    final humedadCtrl =
        TextEditingController(text: _sesion?.humedadPct?.toString() ?? "");
    final presionCtrl =
        TextEditingController(text: _sesion?.presionHpa?.toString() ?? "");
    final vientoCtrl =
        TextEditingController(text: _sesion?.vientoMs?.toString() ?? "");
    final vientoDirCtrl =
        TextEditingController(text: _sesion?.vientoDireccion ?? "");
    String? posicionTemp = _sesion?.posicionTiro;
    String? iluminacionTemp = _sesion?.iluminacion;
    bool interiorTemp = _sesion?.esInterior ?? true;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setStateDialog) {
        return AlertDialog(
          title: const Text('Editar Datos'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<EquipoDetalle>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Arma Utilizada',
                      border: OutlineInputBorder()),
                  initialValue: equipoTemp,
                  items: equipos
                      .map((e) => DropdownMenuItem(
                          value: e,
                          child:
                              Text(e.nombre, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => equipoTemp = v),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: lugarCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Lugar / Campo de Tiro',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: distanciaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Distancia (m)', border: OutlineInputBorder()),
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
                  decoration: const InputDecoration(
                      labelText: 'Posicion de tiro',
                      border: OutlineInputBorder()),
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
                  decoration: const InputDecoration(
                      labelText: 'Iluminacion', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'Artificial', child: Text('Artificial')),
                    DropdownMenuItem(value: 'Natural', child: Text('Natural')),
                    DropdownMenuItem(value: 'Mixta', child: Text('Mixta')),
                  ],
                  onChanged: (v) => setStateDialog(() => iluminacionTemp = v),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: tempCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Temperatura (°C)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: humedadCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Humedad (%)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: presionCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Presion (hPa)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: vientoCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Viento (m/s)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: vientoDirCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Direccion del viento',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: notasCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Observaciones', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('GUARDAR'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white),
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
                  vientoDireccion: vientoDirCtrl.text.trim().isEmpty
                      ? null
                      : vientoDirCtrl.text.trim(),
                  iluminacion: iluminacionTemp,
                );
              },
            )
          ],
        );
      }),
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

    if (!mounted) return;
    _cargarDatosCompletos();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Sesión actualizada')));
  }

  void _generarPDF() async {
    if (_sesion == null) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Generando PDF...'), duration: Duration(seconds: 1)));
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

  bool _permitido(LicenseCapability capability) {
    return _permissions.canAccess(_licenciaActual, capability);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_cargando) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: Center(child: CircularProgressIndicator(color: colorScheme.primary))
      );
    }

    int puntos = _disparos.fold(0, (sum, item) => sum + item.puntuacion.floor());
    int moscas = _disparos.where((d) => d.esMosca).length;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Detalle de Tirada', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _permitido(LicenseCapability.analytics) ? Icons.bar_chart_rounded : Icons.lock_rounded,
              color: _permitido(LicenseCapability.analytics) ? colorScheme.primary : Colors.orange,
            ),
            tooltip: _permitido(LicenseCapability.analytics)
                ? "Analizar esta sesión"
                : LicenseUiHelper.blockedTooltip(
                    permissions: _permissions,
                    capability: LicenseCapability.analytics,
                  ),
            onPressed: () {
              if (!_permitido(LicenseCapability.analytics)) {
                LicenseUiHelper.showBlockedSnackBar(
                  context: context,
                  permissions: _permissions,
                  licencia: _licenciaActual,
                  capability: LicenseCapability.analytics,
                );
                return;
              }
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => EstadisticasScreen(
                              modo: 1, // Modo entrenamiento (o genérico)
                              idsSesionFijos: [widget.sesionId]
                              )));
            },
          ),
          IconButton(
              icon: const Icon(Icons.edit_rounded),
              tooltip: "Editar Datos",
              onPressed: _editarDatosSesion),
          IconButton(
            icon: const Icon(Icons.my_location_rounded),
            tooltip: "Editar tiros",
            onPressed: _editarTirosSesion,
          ),
          IconButton(
            icon: Icon(
              _permitido(LicenseCapability.backup) ? Icons.print_rounded : Icons.lock_rounded,
              color: _permitido(LicenseCapability.backup) ? null : Colors.orange,
            ),
            tooltip: _permitido(LicenseCapability.backup)
                ? 'Imprimir / PDF'
                : LicenseUiHelper.blockedTooltip(
                    permissions: _permissions,
                    capability: LicenseCapability.backup,
                  ),
            onPressed: () {
              if (!_permitido(LicenseCapability.backup)) {
                LicenseUiHelper.showBlockedSnackBar(
                  context: context,
                  permissions: _permissions,
                  licencia: _licenciaActual,
                  capability: LicenseCapability.backup,
                );
                return;
              }
              _generarPDF();
            },
          )
        ],
      ),
      body: Column(
        children: [
          // CONTENEDOR DE INFORMACIÓN SUPERIOR
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
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
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: colorScheme.primary, letterSpacing: -0.5)
                      ),
                      const SizedBox(height: 8),
                      if (_equipoDetalle != null)
                        Row(children: [
                          Icon(Icons.hardware_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_equipoDetalle!.nombre,
                                style: TextStyle(color: colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                          )
                        ]),
                      if (_municionDetalle != null)
                        Row(children: [
                          Icon(Icons.local_fire_department_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('${_municionDetalle!.marca} (${_municionDetalle!.lote})',
                                style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
                                overflow: TextOverflow.ellipsis),
                          )
                        ]),
                      if (_sesion?.lugar != null && _sesion!.lugar!.isNotEmpty)
                        Row(children: [
                          Icon(Icons.place_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_sesion!.lugar!, style: TextStyle(color: colorScheme.onSurface, fontSize: 13), overflow: TextOverflow.ellipsis),
                          )
                        ]),
                      if (_sesion?.distanciaMetros != null)
                        Row(children: [
                          Icon(Icons.straighten_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text('${_sesion!.distanciaMetros} m', style: TextStyle(color: colorScheme.onSurface, fontSize: 13))
                        ]),
                      if (_sesion?.temperaturaC != null || _sesion?.humedadPct != null || _sesion?.vientoMs != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Met: ${_sesion?.temperaturaC?.toStringAsFixed(1) ?? '-'}°C | '
                          'Hum: ${_sesion?.humedadPct?.toStringAsFixed(0) ?? '-'}% | '
                          'Viento: ${_sesion?.vientoMs?.toStringAsFixed(1) ?? '-'} m/s ${_sesion?.vientoDireccion ?? ''}',
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                      if (_sesion?.nota != null && _sesion!.nota!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(8)
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.notes_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _sesion!.nota!,
                                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12, fontStyle: FontStyle.italic),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis
                                ),
                              ),
                            ],
                          ),
                        )
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                          const SizedBox(width: 6),
                          Text(
                            "${_sesion!.fecha.day.toString().padLeft(2, '0')}/${_sesion!.fecha.month.toString().padLeft(2, '0')}/${_sesion!.fecha.year} ${_sesion!.fecha.hour.toString().padLeft(2, '0')}:${_sesion!.fecha.minute.toString().padLeft(2, '0')}",
                            style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600)
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '$puntos',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 36, letterSpacing: -1.5, color: colorScheme.primary, height: 1.0)
                      ),
                      Text(
                        "PUNTOS",
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: colorScheme.onSurfaceVariant)
                      ),
                      if (moscas > 0) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, size: 12, color: Colors.orange),
                              const SizedBox(width: 4),
                              Text(
                                '$moscas (x)',
                                style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.orange.shade300 : Colors.orange.shade800, fontSize: 12)
                              ),
                            ],
                          ),
                        )
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // DIANA
          Expanded(
            child: Center(
              child: Padding(
                padding: _esFondoNegro
                    ? const EdgeInsets.all(4.0)
                    : const EdgeInsets.all(24.0),
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

                    return Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                            blurRadius: 30,
                            spreadRadius: 5,
                            offset: const Offset(0, 10),
                          )
                        ]
                      ),
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
                          diametroImpactoMm: _calibreMm,
                          diametroDianaMm: _dianaAnchoExteriorMm,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          
          // SECUENCIA INFERIOR
          Container(
            height: 110,
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10, offset: const Offset(0, -5)
                )
              ]
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      "SECUENCIA DE TIROS",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5, color: colorScheme.primary)
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _disparos.length,
                        itemBuilder: (context, index) {
                          final tiro = _disparos[index];
                          return Container(
                            width: 64,
                            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                                color: tiro.esMosca
                                    ? Colors.amber.withValues(alpha: isDark ? 0.2 : 0.1)
                                    : colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: tiro.esMosca
                                    ? Colors.amber.withValues(alpha: 0.5)
                                    : colorScheme.outlineVariant.withValues(alpha: 0.5)
                                ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FittedBox(
                                    child: Text('#${tiro.numero}',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onSurfaceVariant))),
                                const SizedBox(height: 4),
                                Expanded(
                                    child: Center(
                                        child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                                '${tiro.puntuacion.toInt()}',
                                                style: TextStyle(
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.w900,
                                                    color: tiro.esMosca ? (isDark ? Colors.amber.shade200 : Colors.amber.shade800) : colorScheme.onSurface))))),
                                if (tiro.esMosca)
                                  Icon(Icons.star_rounded, size: 14, color: isDark ? Colors.orange.shade300 : Colors.orange.shade700)
                                else
                                  const SizedBox(height: 14),
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
  final Offset? centroGravedad;
  final double? diametroImpactoMm;
  final double? diametroDianaMm;

  DianaPainter({
    required this.impactos,
    required this.valorMinimo,
    required this.anilloNegroInicio,
    required this.esFondoNegro,
    required this.tieneMosca,
    required this.tieneGuias,
    required this.esEstiloDuelo,
    this.centroGravedad,
    this.diametroImpactoMm,
    this.diametroDianaMm,
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

    // VARIABLE QUE FALTABA: Declaramos el ancho de cada zona
    double anchoZona = radius / totalZonas;

    final paintNegro = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    final paintLineaClara = Paint()
      ..color = Colors.grey[400]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final paintLineaBlanca = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    if (esEstiloDuelo) {
      double paso = radius / 6;
      for (int i = 0; i < 6; i++) {
        double r = radius - (i * paso);
        canvas.drawCircle(center, r, paintLineaBlanca);
        int numeroAnillo = 5 + i;
        if (numeroAnillo < 10) {
          _dibujarNumeros4Ejes(canvas, numeroAnillo.toString(), center,
              r - (paso / 2), Colors.white);
        }
      }
    } else {
      for (int i = 0; i < totalZonas; i++) {
        int numeroAnillo = valorMinimo + i;
        double r = radius - (i * (radius / totalZonas));

        if (numeroAnillo >= anilloNegroInicio) {
          canvas.drawCircle(center, r, paintNegro);
          canvas.drawCircle(center, r, paintLineaBlanca);
          if (numeroAnillo < 10) {
            _dibujarNumeros4Ejes(canvas, numeroAnillo.toString(), center,
                r - (anchoZona / 2), Colors.white);
          }
        } else {
          if (i > 0) {
            canvas.drawCircle(
                center, r, esFondoNegro ? paintLineaBlanca : paintLineaClara);
          }
          Color colorNum = esFondoNegro ? Colors.white : Colors.black;
          _dibujarNumeros4Ejes(canvas, numeroAnillo.toString(), center,
              r - (anchoZona / 2), colorNum);
        }
      }
    }

    if (tieneMosca) {
      double radioMosca = (radius / totalZonas) / 2;
      canvas.drawCircle(center, radioMosca, paintLineaBlanca);
    }

    if (tieneGuias) {
      Paint guia = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.0;
      double largo = radius * 0.3;
      canvas.drawLine(Offset(center.dx - radius, center.dy),
          Offset(center.dx - radius + largo, center.dy), guia);
      canvas.drawLine(Offset(center.dx + radius, center.dy),
          Offset(center.dx + radius - largo, center.dy), guia);
    }

    canvas.drawLine(
        Offset(center.dx - 4, center.dy),
        Offset(center.dx + 4, center.dy),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1);
    canvas.drawLine(
        Offset(center.dx, center.dy - 4),
        Offset(center.dx, center.dy + 4),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1);

    final paintImpacto = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    double tamano = (radius * 0.04) * (10 / totalZonas);
    if (diametroImpactoMm != null &&
        diametroDianaMm != null &&
        diametroImpactoMm! > 0 &&
        diametroDianaMm! > 0) {
      tamano = radius * (diametroImpactoMm! / diametroDianaMm!);
      tamano = tamano.clamp(1.4, radius * 0.14);
    }
    for (var p in impactos) {
      canvas.drawCircle(p, tamano, paintImpacto);
    }

    if (centroGravedad != null) {
      final paintMPI = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      double sizeCruz = 10.0;
      canvas.drawLine(Offset(centroGravedad!.dx - sizeCruz, centroGravedad!.dy),
          Offset(centroGravedad!.dx + sizeCruz, centroGravedad!.dy), paintMPI);
      canvas.drawLine(Offset(centroGravedad!.dx, centroGravedad!.dy - sizeCruz),
          Offset(centroGravedad!.dx, centroGravedad!.dy + sizeCruz), paintMPI);
      canvas.drawCircle(centroGravedad!, sizeCruz / 1.5, paintMPI);
    }
  }

  void _dibujarNumeros4Ejes(
      Canvas canvas, String texto, Offset center, double dist, Color color) {
    _texto(canvas, texto, Offset(center.dx, center.dy - dist), color);
    _texto(canvas, texto, Offset(center.dx, center.dy + dist), color);
    _texto(canvas, texto, Offset(center.dx + dist, center.dy), color);
    _texto(canvas, texto, Offset(center.dx - dist, center.dy), color);
  }

  void _texto(Canvas canvas, String texto, Offset pos, Color color) {
    final tp = TextPainter(
        text: TextSpan(
            text: texto,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant DianaPainter oldDelegate) => true;
}

class _EditableDisparo {
  final int? id;
  final int numero;
  double x;
  double y;
  double puntuacion;
  bool esMosca;

  _EditableDisparo({
    required this.id,
    required this.numero,
    required this.x,
    required this.y,
    required this.puntuacion,
    required this.esMosca,
  });
}

class _ScoredShot {
  final int puntuacion;
  final bool esMosca;

  const _ScoredShot({
    required this.puntuacion,
    required this.esMosca,
  });
}
