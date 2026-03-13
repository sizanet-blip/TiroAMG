import 'package:flutter/material.dart';
// Modelos
import '../models/equipo_model.dart';
import '../models/plantilla_tiempos_model.dart';
import '../models/municion_model.dart';
// Servicios
import '../services/equipo_service.dart';
import '../services/plantilla_tiempos_service.dart';
import '../services/municion_service.dart';
// Pantalla de Destino (La Diana)
import 'sesion_disparo_screen.dart';

class EntrenamientoScreen extends StatefulWidget {
  const EntrenamientoScreen({super.key});

  @override
  State<EntrenamientoScreen> createState() => _EntrenamientoScreenState();
}

class _EntrenamientoScreenState extends State<EntrenamientoScreen> {
  // Servicios
  final _equipoService = EquipoService();
  final _plantillaService = PlantillaTiemposService();
  final _municionService = MunicionService();

  // Listas de Datos
  List<EquipoDetalle> _equipos = [];
  List<PlantillaTiempos> _plantillas = [];
  List<MunicionDetalle> _municiones = [];

  // Selecciones del Usuario
  EquipoDetalle? _equipoSeleccionado;
  PlantillaTiempos? _plantillaSeleccionada;
  MunicionDetalle? _municionSeleccionada;
  final _lugarController = TextEditingController();
  final _distanciaController = TextEditingController();
  final _tempController = TextEditingController();
  final _humedadController = TextEditingController();
  final _presionController = TextEditingController();
  final _vientoController = TextEditingController();
  final _vientoDirController = TextEditingController();
  String? _posicionTiro;
  String? _iluminacion;
  bool _esInterior = true;
  bool _usarPuntuacionDecimal = false;
  bool _mostrarCondicionesTiro = false;

  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final equipos = await _equipoService.obtenerEquiposDetallados();
    final plantillas = await _plantillaService.obtenerTodas();
    final municiones = await _municionService.obtenerMunicionDetallada();

    if (mounted) {
      setState(() {
        _equipos = equipos;
        _plantillas = plantillas;
        _municiones = municiones;
        _cargando = false;

        // Pre-seleccionar el primero si existe para facilitar
        if (_equipos.isNotEmpty) _equipoSeleccionado = _equipos.first;
        if (_plantillas.isNotEmpty) _plantillaSeleccionada = _plantillas.first;
      });
    }
  }

  void _iniciarSesion() {
    if (_equipoSeleccionado == null || _plantillaSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Debes seleccionar un Arma y una Disciplina')),
      );
      return;
    }

    // Navegar a la pantalla de disparo enviando los datos configurados
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SesionDisparoScreen(
          equipo: _equipoSeleccionado!,
          plantilla: _plantillaSeleccionada!,
          municion: _municionSeleccionada,
          lugar: _textOrNull(_lugarController.text),
          distanciaMetros: _parseInt(_distanciaController.text),
          posicionTiro: _posicionTiro,
          esInterior: _esInterior,
          temperaturaC: _parseDouble(_tempController.text),
          humedadPct: _parseDouble(_humedadController.text),
          presionHpa: _parseDouble(_presionController.text),
          vientoMs: _parseDouble(_vientoController.text),
          vientoDireccion: _textOrNull(_vientoDirController.text),
          iluminacion: _iluminacion,
          usarPuntuacionDecimal: _usarPuntuacionDecimal,
        ),
      ),
    );
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

  String? _textOrNull(String value) {
    final v = value.trim();
    return v.isEmpty ? null : v;
  }

  @override
  void dispose() {
    _lugarController.dispose();
    _distanciaController.dispose();
    _tempController.dispose();
    _humedadController.dispose();
    _presionController.dispose();
    _vientoController.dispose();
    _vientoDirController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_cargando) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_equipos.isEmpty || _plantillas.isEmpty) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: const Text('Entrenamiento'),
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange),
                ),
                const SizedBox(height: 32),
                Text(
                  'Faltan datos clave',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
                const SizedBox(height: 16),
                Text(
                  'Necesitas crear al menos un Arma (Equipo) y una Regla/Disciplina (Plantilla de Tiempos) para poder empezar a entrenar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            pinned: true,
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            elevation: 0,
            title: const Text(
              'Configurar Sesión',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), // Padding extra abajo para el botón flotante
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildModernSectionHeader('Selección principal', colorScheme),
                Container(
                  decoration: _modernContainerDecoration(colorScheme),
                  child: Column(
                    children: [
                      _buildModernSelectionCard(
                        context: context,
                        title: '1. Elige tu Arma',
                        icon: Icons.hardware_rounded,
                        color: Colors.teal,
                        child: DropdownButtonFormField<EquipoDetalle>(
                          decoration: _dropdownDecoration(colorScheme),
                          initialValue: _equipoSeleccionado,
                          isExpanded: true,
                          items: _equipos.map((e) {
                            return DropdownMenuItem(
                              value: e,
                              child: Text('${e.nombre} (${e.nombreCalibre})'),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _equipoSeleccionado = val),
                        ),
                      ),
                      _buildDivider(colorScheme),
                      _buildModernSelectionCard(
                        context: context,
                        title: '2. Reglas / Disciplina',
                        icon: Icons.timer_rounded,
                        color: Colors.indigo,
                        child: DropdownButtonFormField<PlantillaTiempos>(
                          decoration: _dropdownDecoration(colorScheme),
                          initialValue: _plantillaSeleccionada,
                          isExpanded: true,
                          items: _plantillas.map((p) {
                            return DropdownMenuItem(
                              value: p,
                              child: Text(
                                p.nombreDisciplina,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _plantillaSeleccionada = val),
                        ),
                      ),
                      _buildDivider(colorScheme),
                      _buildModernSelectionCard(
                        context: context,
                        title: '3. Sistema de puntuación',
                        icon: Icons.calculate_rounded,
                        color: Colors.blueGrey,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Usar puntuación decimal', style: TextStyle(fontSize: 15)),
                          subtitle: const Text('Si se desactiva, se usará la puntuación clásica entera.'),
                          value: _usarPuntuacionDecimal,
                          activeThumbColor: Colors.blueGrey,
                          onChanged: (v) => setState(() => _usarPuntuacionDecimal = v),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                _buildModernSectionHeader('Opciones Adicionales', colorScheme),
                Container(
                  decoration: _modernContainerDecoration(colorScheme),
                  child: Column(
                    children: [
                      _buildModernSelectionCard(
                        context: context,
                        title: '4. Munición (Opcional)',
                        icon: Icons.local_fire_department_rounded,
                        color: Colors.deepOrange,
                        child: DropdownButtonFormField<MunicionDetalle>(
                          decoration: _dropdownDecoration(colorScheme).copyWith(
                            labelText: 'Seleccionar lote...',
                          ),
                          initialValue: _municionSeleccionada,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<MunicionDetalle>(
                              value: null,
                              child: Text('Sin especificar'),
                            ),
                            ..._municiones.map((m) {
                              return DropdownMenuItem(
                                value: m,
                                child: Text('${m.marca} - ${m.lote} (Stock: ${m.cantidadActual})'),
                              );
                            }),
                          ],
                          onChanged: (val) => setState(() => _municionSeleccionada = val),
                        ),
                      ),
                      _buildDivider(colorScheme),
                      _buildModernSelectionCard(
                        context: context,
                        title: '5. Condiciones del entorno',
                        icon: Icons.thermostat_rounded,
                        color: Colors.amber.shade800,
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => setState(() => _mostrarCondicionesTiro = !_mostrarCondicionesTiro),
                                icon: Icon(_mostrarCondicionesTiro ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                                label: Text(_mostrarCondicionesTiro ? 'Ocultar formulario' : 'Añadir variables climáticas'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  side: BorderSide(color: colorScheme.outlineVariant),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            if (_mostrarCondicionesTiro) ...[
                              const SizedBox(height: 16),
                              _buildModernTextField(controller: _lugarController, label: 'Lugar / Campo', icon: Icons.place_rounded, colorScheme: colorScheme),
                              const SizedBox(height: 12),
                              _buildModernTextField(controller: _distanciaController, label: 'Distancia (m)', icon: Icons.straighten_rounded, isNumber: true, colorScheme: colorScheme),
                              const SizedBox(height: 12),
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: colorScheme.outlineVariant),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SwitchListTile(
                                  title: const Text('Galería Interior'),
                                  value: _esInterior,
                                  activeThumbColor: colorScheme.primary,
                                  onChanged: (v) => setState(() => _esInterior = v),
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _posicionTiro,
                                decoration: _dropdownDecoration(colorScheme).copyWith(labelText: 'Posición de tiro'),
                                items: const [
                                  DropdownMenuItem(value: 'Pie', child: Text('Pie')),
                                  DropdownMenuItem(value: 'Rodilla', child: Text('Rodilla')),
                                  DropdownMenuItem(value: 'Tendido', child: Text('Tendido')),
                                  DropdownMenuItem(value: 'Banco', child: Text('Banco')),
                                ],
                                onChanged: (v) => setState(() => _posicionTiro = v),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _iluminacion,
                                decoration: _dropdownDecoration(colorScheme).copyWith(labelText: 'Iluminación'),
                                items: const [
                                  DropdownMenuItem(value: 'Artificial', child: Text('Artificial')),
                                  DropdownMenuItem(value: 'Natural', child: Text('Natural')),
                                  DropdownMenuItem(value: 'Mixta', child: Text('Mixta')),
                                ],
                                onChanged: (v) => setState(() => _iluminacion = v),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(child: _buildModernTextField(controller: _tempController, label: 'Temp. (°C)', isNumber: true, icon: Icons.device_thermostat_rounded, colorScheme: colorScheme)),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildModernTextField(controller: _humedadController, label: 'Humedad (%)', isNumber: true, icon: Icons.water_drop_rounded, colorScheme: colorScheme)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: _buildModernTextField(controller: _presionController, label: 'Presión (hPa)', isNumber: true, icon: Icons.speed_rounded, colorScheme: colorScheme)),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildModernTextField(controller: _vientoController, label: 'Viento (m/s)', isNumber: true, icon: Icons.air_rounded, colorScheme: colorScheme)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildModernTextField(controller: _vientoDirController, label: 'Dirección del viento', icon: Icons.explore_rounded, colorScheme: colorScheme),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          width: double.infinity,
          height: 60,
          child: FilledButton.icon(
            onPressed: _iniciarSesion,
            icon: const Icon(Icons.play_arrow_rounded, size: 28),
            label: const Text(
              'EMPEZAR ENTRENAMIENTO',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 4,
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _modernContainerDecoration(ColorScheme colorScheme) {
    return BoxDecoration(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _buildDivider(ColorScheme colorScheme) {
    return Divider(
      height: 1, 
      indent: 56, 
      color: colorScheme.outlineVariant.withValues(alpha: 0.5)
    );
  }

  Widget _buildModernSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 16, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: colorScheme.primary,
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  InputDecoration _dropdownDecoration(ColorScheme colorScheme) {
    return InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      filled: true,
      fillColor: colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ColorScheme colorScheme,
    bool isNumber = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        filled: true,
        fillColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }

  Widget _buildModernSelectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    final themeInfo = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: themeInfo.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
