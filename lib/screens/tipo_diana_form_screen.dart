import 'package:flutter/material.dart';
import '../models/tipo_diana_model.dart';
import '../services/catalogo_service.dart';

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
  
  // Valores por defecto
  int _valorMinimo = 1;       // Anillo exterior
  int _anilloNegro = 7;       // Inicio del negro
  bool _esFondoNegro = false; // Papel crema por defecto
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
    }
  }

  void _guardar() async {
    if (_formKey.currentState!.validate()) {
      final nuevaDiana = TipoDiana(
        id: widget.diana?.id,
        nombre: _nombreController.text,
        valorMinimo: _valorMinimo,
        anilloNegroInicio: _anilloNegro,
        esFondoNegro: _esFondoNegro,
        tieneMosca: _tieneMosca,
        tieneGuias: _tieneGuias,
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.diana == null ? 'Diseñar Diana' : 'Editar Diana'),
        backgroundColor: Colors.blueGrey,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // NOMBRE
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(labelText: 'Nombre de la Diana', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 20),
              
              const Text('Geometría y Puntuación', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal)),
              const Divider(),

              // 1. VALOR MÍNIMO (Tamaño visible)
              ListTile(
                title: const Text('Anillo exterior (Borde de la diana)'),
                subtitle: Text('Valor actual: $_valorMinimo'),
                trailing: DropdownButton<int>(
                  value: _valorMinimo,
                  items: [1, 2, 3, 4, 5, 6, 7].map((v) => DropdownMenuItem(value: v, child: Text(v.toString()))).toList(),
                  onChanged: (val) => setState(() => _valorMinimo = val!),
                ),
              ),
              const Text('   • Usa 1 para dianas completas (Precisión).\n   • Usa 5 para dianas con zoom (Duelo).', style: TextStyle(color: Colors.grey, fontSize: 12)),
              
              const SizedBox(height: 10),

              // 2. INICIO NEGRO
              ListTile(
                title: const Text('¿Dónde empieza el color NEGRO?'),
                subtitle: Text('Desde el anillo: $_anilloNegro'),
                trailing: DropdownButton<int>(
                  value: _anilloNegro,
                  items: [4, 5, 6, 7, 8, 9, 10].map((v) => DropdownMenuItem(value: v, child: Text(v.toString()))).toList(),
                  onChanged: (val) => setState(() => _anilloNegro = val!),
                ),
              ),

              const SizedBox(height: 20),
              const Text('Estilo Visual', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal)),
              const Divider(),

              // 3. COLOR DE FONDO
              SwitchListTile(
                title: const Text('Fondo Negro Total'),
                subtitle: const Text('Activar para dianas de Duelo/Velocidad.'),
                value: _esFondoNegro,
                activeColor: Colors.black,
                onChanged: (val) => setState(() => _esFondoNegro = val),
              ),

              // 4. GUIAS
              SwitchListTile(
                title: const Text('Guías Horizontales'),
                subtitle: const Text('Líneas blancas a las 3 y a las 9.'),
                value: _tieneGuias,
                activeColor: Colors.blueGrey,
                onChanged: (val) => setState(() => _tieneGuias = val),
              ),

              // 5. MOSCA
              SwitchListTile(
                title: const Text('Tiene Mosca (X-Ring)'),
                value: _tieneMosca,
                onChanged: (val) => setState(() => _tieneMosca = val),
              ),

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('GUARDAR DISEÑO'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(15), 
                    backgroundColor: Colors.teal, 
                    foregroundColor: Colors.white
                  ),
                  onPressed: _guardar,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}