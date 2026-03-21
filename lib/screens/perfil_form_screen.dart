import 'package:flutter/material.dart';
import '../services/perfil_service.dart';

class PerfilFormScreen extends StatefulWidget {
  const PerfilFormScreen({super.key});

  @override
  State<PerfilFormScreen> createState() => _PerfilFormScreenState();
}

class _PerfilFormScreenState extends State<PerfilFormScreen> {
  final _service = PerfilService();
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _licenciaCtrl = TextEditingController();
  final _clubCtrl = TextEditingController();
  final _catCtrl = TextEditingController();

  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() async {
    final perfil = await _service.obtenerPerfil();
    setState(() {
      _nombreCtrl.text = perfil.nombre;
      _licenciaCtrl.text = perfil.licencia;
      _clubCtrl.text = perfil.club;
      _catCtrl.text = perfil.categoria;
      _cargando = false;
    });
  }

  void _guardar() async {
    if (_formKey.currentState!.validate()) {
      final perfil = PerfilUsuario(
        nombre: _nombreCtrl.text,
        licencia: _licenciaCtrl.text,
        club: _clubCtrl.text,
        categoria: _catCtrl.text,
      );
      
      await _service.guardarPerfil(perfil);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Datos guardados correctamente')));
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Mis Datos de Tirador'), backgroundColor: Colors.blueGrey),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 420;
            return Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text("Estos datos aparecerán automáticamente en tus Actas y PDFs.", style: TextStyle(color: Colors.grey)),
              SizedBox(height: isNarrow ? 16 : 20),
              
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre y Apellidos', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
              ),
              const SizedBox(height: 15),
              
              TextFormField(
                controller: _licenciaCtrl,
                decoration: const InputDecoration(labelText: 'Nº Licencia Federativa', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge)),
              ),
              const SizedBox(height: 15),
              
              TextFormField(
                controller: _clubCtrl,
                decoration: const InputDecoration(labelText: 'Club / Federación', border: OutlineInputBorder(), prefixIcon: Icon(Icons.groups)),
              ),
              const SizedBox(height: 15),
              
              TextFormField(
                controller: _catCtrl,
                decoration: const InputDecoration(labelText: 'Categoría (Senior, Veterano...)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.stars)),
              ),

              const SizedBox(height: 30),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('GUARDAR PERFIL'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white, padding: const EdgeInsets.all(15)),
                  onPressed: _guardar,
                ),
              )
            ],
          ),
            );
          },
        ),
      ),
    );
  }
}