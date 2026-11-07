import 'package:flutter/material.dart';

import '../help/privacy_content.dart';
import '../help/terms_content.dart';
import '../services/license_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_exit.dart';
import '../widgets/app_ui.dart';
import '../screens/ayuda_documento_screen.dart';

/// Diálogo de registro: privacidad + condiciones obligatorias; email opcional u obligatorio.
///
/// Con [salirAlCancelar] (arranque), Salir cierra la aplicación.
/// Con [emailOpcional] se puede continuar solo aceptando lo legal.
Future<bool> showIdentificarInstalacionDialog({
  required BuildContext context,
  required LicenseService licenseService,
  String? emailInicial,
  bool permitirOmitir = false,
  bool salirAlCancelar = false,
  bool emailOpcional = false,
  bool privacidadYaAceptada = false,
  bool condicionesYaAceptadas = false,
  RegExp? emailRegex,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _IdentificarInstalacionDialog(
      licenseService: licenseService,
      emailInicial: emailInicial,
      permitirOmitir: permitirOmitir,
      salirAlCancelar: salirAlCancelar,
      emailOpcional: emailOpcional,
      privacidadYaAceptada: privacidadYaAceptada,
      condicionesYaAceptadas: condicionesYaAceptadas,
      emailRegex: emailRegex ?? RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$'),
    ),
  );
  return result == true;
}

class _IdentificarInstalacionDialog extends StatefulWidget {
  final LicenseService licenseService;
  final String? emailInicial;
  final bool permitirOmitir;
  final bool salirAlCancelar;
  final bool emailOpcional;
  final bool privacidadYaAceptada;
  final bool condicionesYaAceptadas;
  final RegExp emailRegex;

  const _IdentificarInstalacionDialog({
    required this.licenseService,
    required this.emailInicial,
    required this.permitirOmitir,
    required this.salirAlCancelar,
    required this.emailOpcional,
    required this.privacidadYaAceptada,
    required this.condicionesYaAceptadas,
    required this.emailRegex,
  });

  @override
  State<_IdentificarInstalacionDialog> createState() =>
      _IdentificarInstalacionDialogState();
}

class _IdentificarInstalacionDialogState
    extends State<_IdentificarInstalacionDialog> {
  late final TextEditingController _controller;
  late String _mensaje;
  var _cargando = false;
  late bool _aceptaLegal;

  bool get _legalYaAceptado =>
      widget.privacidadYaAceptada && widget.condicionesYaAceptadas;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.emailInicial ?? '');
    _aceptaLegal = _legalYaAceptado;
    _mensaje = widget.emailOpcional
        ? 'Para usar TiroAMG debes aceptar la política de privacidad y las condiciones de uso. El email es opcional (recomendado para soporte).'
        : 'Asocia un email para registrar esta instalación. Debes aceptar la política de privacidad y las condiciones de uso.';
    if (widget.salirAlCancelar) {
      _mensaje = '$_mensaje Si sales sin aceptar, la aplicación se cerrará.';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _salirOCerrar() {
    if (widget.salirAlCancelar) {
      exitApp();
      return;
    }
    Navigator.of(context).pop(false);
  }

  Future<void> _continuar() async {
    final email = _controller.text.trim();
    if (!_aceptaLegal) {
      setState(() {
        _mensaje =
            'Debes aceptar la Política de privacidad y las Condiciones de uso para continuar.';
      });
      return;
    }
    if (email.isNotEmpty && !widget.emailRegex.hasMatch(email)) {
      setState(() {
        _mensaje = 'Introduce un email válido o déjalo vacío.';
      });
      return;
    }
    if (!widget.emailOpcional && email.isEmpty) {
      setState(() {
        _mensaje = 'Introduce un email válido.';
      });
      return;
    }

    setState(() => _cargando = true);
    try {
      await widget.licenseService.registrarAceptacionLegal(
        privacyVersion: PrivacyContent.version,
        termsVersion: TermsContent.version,
      );

      if (email.isNotEmpty) {
        try {
          await widget.licenseService.identificarEmail(email: email);
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _mensaje = 'No se pudo guardar. Inténtalo de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.permitirOmitir,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (widget.salirAlCancelar && !_cargando) {
          exitApp();
        }
      },
      child: AppDialog(
        title: widget.emailOpcional
            ? 'Antes de empezar'
            : 'Registrar instalación',
        icon: widget.emailOpcional
            ? Icons.privacy_tip_outlined
            : Icons.email_outlined,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _mensaje,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.35,
                  color: AppColors.subtitle,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                TermsContent.resumenCorto,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: AppColors.subtitle,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                enabled: !_cargando,
                decoration: InputDecoration(
                  labelText:
                      widget.emailOpcional ? 'Email (opcional)' : 'Email',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _aceptaLegal,
                      onChanged: _cargando || _legalYaAceptado
                          ? null
                          : (v) => setState(() => _aceptaLegal = v ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _legalYaAceptado
                              ? 'Privacidad y condiciones ya aceptadas.'
                              : 'He leído y acepto la Política de privacidad y las Condiciones de uso (obligatorio). Entiendo que la app se ofrece sin garantía y bajo mi responsabilidad.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: AppColors.title,
                          ),
                        ),
                        TextButton(
                          onPressed: _cargando
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const PoliticaPrivacidadScreen(),
                                    ),
                                  );
                                },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Ver política de privacidad'),
                        ),
                        TextButton(
                          onPressed: _cargando
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const CondicionesUsoScreen(),
                                    ),
                                  );
                                },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Ver condiciones de uso'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          if (widget.permitirOmitir)
            TextButton(
              onPressed: _cargando
                  ? null
                  : () async {
                      await widget.licenseService.snoozeIdentifyPrompt(days: 7);
                      if (context.mounted) Navigator.of(context).pop(false);
                    },
              child: Text(
                'Ahora no',
                style: TextStyle(color: AppColors.subtitle),
              ),
            ),
          if (widget.permitirOmitir)
            TextButton(
              onPressed: _cargando
                  ? null
                  : () async {
                      await widget.licenseService.neverAskIdentifyPrompt();
                      if (context.mounted) Navigator.of(context).pop(false);
                    },
              child: Text(
                'No volver a preguntar',
                style: TextStyle(color: AppColors.subtitle),
              ),
            ),
          if (!widget.permitirOmitir)
            TextButton(
              onPressed: _cargando ? null : _salirOCerrar,
              child: Text(
                widget.salirAlCancelar ? 'Salir' : 'Cancelar',
                style: TextStyle(color: AppColors.subtitle),
              ),
            ),
          FilledButton(
            onPressed: _cargando ? null : _continuar,
            child: _cargando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(widget.emailOpcional ? 'Continuar' : 'Guardar'),
          ),
        ],
      ),
    );
  }
}

class PoliticaPrivacidadScreen extends StatelessWidget {
  const PoliticaPrivacidadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AyudaDocumentoScreen(doc: PrivacyContent.documento);
  }
}

class CondicionesUsoScreen extends StatelessWidget {
  const CondicionesUsoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AyudaDocumentoScreen(doc: TermsContent.documento);
  }
}
