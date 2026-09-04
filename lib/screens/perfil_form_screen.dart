import 'package:flutter/material.dart';
import '../services/perfil_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

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
    if (_cargando) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return AppPageScaffold(
      title: 'Mis Datos de Tirador',
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Estos datos aparecerán automáticamente en tus Actas y PDFs.',
              style: TextStyle(color: AppColors.subtitle),
            ),
            const SizedBox(height: 16),

            AppSectionCard(
              title: 'Datos personales',
              titleIcon: Icons.person_outline,
              child: Column(
                children: [
                  TextFormField(
                    controller: _nombreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre y Apellidos',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _licenciaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nº Licencia Federativa',
                      prefixIcon: Icon(Icons.badge),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _clubCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Club / Federación',
                      prefixIcon: Icon(Icons.groups),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _catCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Categoría (Senior, Veterano...)',
                      prefixIcon: Icon(Icons.stars),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            AppPrimaryButton(
              label: 'Guardar perfil',
              icon: Icons.save,
              onPressed: _guardar,
            ),
          ],
        ),
      ),
    );
  }
}
