import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../help/privacy_content.dart';
import '../help/terms_content.dart';
import '../services/app_auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tiro_amg_app_bar.dart';
import 'ayuda_documento_screen.dart';

/// Login / registro / recuperación / pendiente de aprobación.
class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key, required this.onAuthenticated});

  final VoidCallback onAuthenticated;

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

enum _AuthTab { login, register, recover, pending }

class _AuthGateScreenState extends State<AuthGateScreen> {
  final _auth = AppAuthService();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();

  var _tab = _AuthTab.login;
  var _busy = false;
  var _acceptLegal = false;
  String? _message;
  String? _recoveryCode;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final status = await _auth.status();
    final user = await _auth.username();
    if (user != null) _userCtrl.text = user;
    if (status == 'pending') {
      setState(() => _tab = _AuthTab.pending);
    }
    if (await _auth.hasSession()) {
      widget.onAuthenticated();
    }
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final r = await _auth.login(
      username: _userCtrl.text,
      password: _passCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = r.message;
      if (r.pending) _tab = _AuthTab.pending;
    });
    if (r.ok) widget.onAuthenticated();
  }

  Future<void> _submitRegister() async {
    setState(() {
      _busy = true;
      _message = null;
      _recoveryCode = null;
    });
    final r = await _auth.register(
      username: _userCtrl.text,
      password: _passCtrl.text,
      email: _emailCtrl.text,
      acceptedLegal: _acceptLegal,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = r.message;
      _recoveryCode = r.recoveryCode;
      if (r.ok) _tab = _AuthTab.pending;
    });
  }

  Future<void> _submitRecover() async {
    setState(() {
      _busy = true;
      _message = null;
      _recoveryCode = null;
    });
    final r = await _auth.recover(
      username: _userCtrl.text,
      recoveryCode: _codeCtrl.text,
      newPassword: _newPassCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = r.message;
      _recoveryCode = r.recoveryCode;
      if (r.ok) _tab = _AuthTab.login;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!AppAuthService.isConfigured) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: const TiroAmgAppBar(section: 'Acceso'),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'API de autenticación no configurada (APP_AUTH_API_URL / LICENSE_API_URL).',
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const TiroAmgAppBar(section: 'Acceso'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          SegmentedButton<_AuthTab>(
            segments: const [
              ButtonSegment(value: _AuthTab.login, label: Text('Entrar')),
              ButtonSegment(value: _AuthTab.register, label: Text('Crear')),
              ButtonSegment(value: _AuthTab.recover, label: Text('Código')),
            ],
            selected: {_tab == _AuthTab.pending ? _AuthTab.login : _tab},
            onSelectionChanged: (s) {
              setState(() {
                _tab = s.first;
                _message = null;
              });
            },
          ),
          const SizedBox(height: 20),
          if (_tab == _AuthTab.pending) ...[
            const Text(
              'Cuenta pendiente de aprobación. Cuando el administrador la active, inicia sesión.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => setState(() => _tab = _AuthTab.login),
              child: const Text('Ir a iniciar sesión'),
            ),
          ],
          if (_tab == _AuthTab.login) ...[
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: 'Usuario',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submitLogin,
              child: Text(_busy ? 'Entrando…' : 'Iniciar sesión'),
            ),
          ],
          if (_tab == _AuthTab.register) ...[
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: 'Usuario',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña (mín. 6)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _acceptLegal,
              onChanged: (v) => setState(() => _acceptLegal = v ?? false),
              title: Text(
                'Acepto la política de privacidad y las condiciones de uso '
                'de TiroAMG (v. ${PrivacyContent.version}).',
                style: const TextStyle(fontSize: 13),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AyudaDocumentoScreen(
                          doc: PrivacyContent.documento,
                        ),
                      ),
                    );
                  },
                  child: const Text('Leer privacidad'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AyudaDocumentoScreen(
                          doc: TermsContent.documento,
                        ),
                      ),
                    );
                  },
                  child: const Text('Leer condiciones'),
                ),
              ],
            ),
            FilledButton(
              onPressed: _busy ? null : _submitRegister,
              child: Text(_busy ? 'Enviando…' : 'Solicitar acceso'),
            ),
          ],
          if (_tab == _AuthTab.recover) ...[
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: 'Usuario',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Código de recuperación',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Nueva contraseña',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submitRecover,
              child: Text(_busy ? 'Guardando…' : 'Cambiar contraseña'),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!, style: TextStyle(color: AppColors.subtitle)),
          ],
          if (_recoveryCode != null) ...[
            const SizedBox(height: 12),
            SelectableText(
              'Código: $_recoveryCode',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _recoveryCode!)),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copiar código'),
            ),
          ],
        ],
      ),
    );
  }
}
