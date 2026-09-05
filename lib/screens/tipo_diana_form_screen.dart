import 'package:flutter/material.dart';
import '../models/tipo_diana_model.dart';
import '../services/catalogo_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

class TipoDianaFormScreen extends StatefulWidget {
  final TipoDiana? diana;
  const TipoDianaFormScreen({super.key, this.diana});

  @override
  State<TipoDianaFormScreen> createState() => _TipoDianaFormScreenState();
}

class _TipoDianaFormScreenState extends State<TipoDianaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = CatalogoService();

  final _nombreController = TextEditingController();
  // Controladores para las nuevas dimensiones físicas
  final _anchoMmController = TextEditingController(); 
  final _altoMmController = TextEditingController();   
  
  // Valores por defecto
  int _valorMinimo = 1;       
  int _anilloNegro = 7;       
  bool _esFondoNegro = false; 
  bool _tieneMosca = true;
  bool _tieneGuias = false;

  @override
  void initState() {
    super.initState();
    if (widget.diana != null) {
      _nombreController.text = widget.diana!.nombre;
      _valorMinimo = widget.diana!.valorMinimo;
      _anilloNegro = widget.diana!.anilloNegroInicio;
      _esFondoNegro = widget.diana!.esFondoNegro;
      _tieneMosca = widget.diana!.tieneMosca;
      _tieneGuias = widget.diana!.tieneGuias;
      
      // Cargar dimensiones físicas (Corrección aplicada)
      _anchoMmController.text = widget.diana!.anchoExteriorMm?.toString() ?? ''; 
      _altoMmController.text = widget.diana!.altoExteriorMm?.toString() ?? '';   
    } else {
      // Inicializar controladores a vacío si es una nueva diana
      _anchoMmController.text = '';
      _altoMmController.text = '';
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _anchoMmController.dispose();
    _altoMmController.dispose();
    super.dispose();
  }

  void _guardar() async {
    if (_formKey.currentState!.validate()) {
      // Intentar parsear las dimensiones a double
      final ancho = double.tryParse(_anchoMmController.text);
      final alto = double.tryParse(_altoMmController.text);
      
      final nuevaDiana = TipoDiana(
        id: widget.diana?.id,
        nombre: _nombreController.text,
        valorMinimo: _valorMinimo,
        anilloNegroInicio: _anilloNegro,
        esFondoNegro: _esFondoNegro,
        tieneMosca: _tieneMosca,
        tieneGuias: _tieneGuias,
        // Asignar nuevas dimensiones
        anchoExteriorMm: ancho, 
        altoExteriorMm: alto,   
      );

      if (widget.diana == null) {
        await _service.crearTipoDiana(nuevaDiana);
      } else {
        await _service.actualizarTipoDiana(nuevaDiana);
      }
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: widget.diana == null ? 'Diseñar Diana' : 'Editar Diana',
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionCard(
              title: 'Identificación',
              titleIcon: Icons.adjust,
              child: TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(labelText: 'Nombre de la Diana'),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
            ),

            const SizedBox(height: 16),

            AppSectionCard(
              title: 'Geometría y puntuación',
              titleIcon: Icons.straighten,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _anchoMmController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Ancho Exterior (mm)',
                          ),
                          validator: (v) {
                            if (v!.isEmpty) return 'Requerido';
                            if (double.tryParse(v) == null) return 'Número inválido';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _altoMmController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Alto Exterior (mm)',
                          ),
                          validator: (v) {
                            if (v!.isEmpty) return 'Requerido';
                            if (double.tryParse(v) == null) return 'Número inválido';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 12),
                    child: Text(
                      'Dimensión física total del papel (ej: 170mm).',
                      style: TextStyle(color: AppColors.subtitleSoft, fontSize: 12),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Anillo exterior (Borde de la diana)'),
                    subtitle: Text('Valor actual: $_valorMinimo'),
                    trailing: DropdownButton<int>(
                      value: _valorMinimo,
                      items: [1, 2, 3, 4, 5, 6, 7].map((v) => DropdownMenuItem(value: v, child: Text(v.toString()))).toList(),
                      onChanged: (val) => setState(() => _valorMinimo = val!),
                    ),
                  ),
                  Text(
                    '• Usa 1 para dianas completas (Precisión).\n• Usa 5 para dianas con zoom (Duelo).',
                    style: TextStyle(color: AppColors.subtitleSoft, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('¿Dónde empieza el color NEGRO?'),
                    subtitle: Text('Desde el anillo: $_anilloNegro'),
                    trailing: DropdownButton<int>(
                      value: _anilloNegro,
                      items: [4, 5, 6, 7, 8, 9, 10].map((v) => DropdownMenuItem(value: v, child: Text(v.toString()))).toList(),
                      onChanged: (val) => setState(() => _anilloNegro = val!),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            AppSectionCard(
              title: 'Estilo visual',
              titleIcon: Icons.palette_outlined,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fondo Negro Total'),
                    subtitle: const Text('Activar para dianas de Duelo/Velocidad.'),
                    value: _esFondoNegro,
                    onChanged: (val) => setState(() => _esFondoNegro = val),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Guías Horizontales'),
                    subtitle: const Text('Líneas blancas a las 3 y a las 9.'),
                    value: _tieneGuias,
                    onChanged: (val) => setState(() => _tieneGuias = val),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tiene Mosca (X-Ring)'),
                    value: _tieneMosca,
                    onChanged: (val) => setState(() => _tieneMosca = val),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            AppPrimaryButton(
              label: 'Guardar diseño',
              icon: Icons.save,
              onPressed: _guardar,
            ),
          ],
        ),
      ),
    );
  }
}
