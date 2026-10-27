import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../help/privacy_content.dart';
import '../help/terms_content.dart';
import '../services/app_auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tiro_amg_app_bar_title.dart';
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
  final _biometric = BiometricAuthService();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();

  var _tab = _AuthTab.login;
  var _busy = false;
  var _checkingStatus = false;
  var _acceptLegal = false;
  var _needsLegal = false;
  var _biometricAvailable = false;
  var _biometricEnabled = false;
  String? _message;
  String? _recoveryCode;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final status = await _auth.status();
    final user = await _auth.username();
    final recovery = await _auth.lastRecoveryCode();
    final bioOk = await _biometric.isSupported;
    final bioOn = await _biometric.isEnabled;
    final bioUser = await _biometric.savedUsername();
    if (user != null) _userCtrl.text = user;
    if ((user == null || user.isEmpty) && bioUser != null) {
      _userCtrl.text = bioUser;
    }
    if (!mounted) return;
    setState(() {
      _biometricAvailable = bioOk;
      _biometricEnabled = bioOn;
      if (status == 'pending') {
        _tab = _AuthTab.pending;
        _recoveryCode = recovery;
      }
    });
    if (status == 'pending') {
      _startStatusPolling();
    } else if (bioOk && bioOn && status != 'pending') {
      // Intento automático de huella al abrir la pantalla de acceso.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tab == _AuthTab.login) _loginWithBiometric();
      });
    }
    if (await _auth.hasSession()) {
      widget.onAuthenticated();
    }
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkApprovalStatus(silent: true);
    });
    // Primera comprobación inmediata.
    _checkApprovalStatus(silent: true);
  }

  void _stopStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  Future<void> _checkApprovalStatus({bool silent = false}) async {
    final user = _userCtrl.text.trim();
    if (user.isEmpty || _checkingStatus) return;

    if (!silent) {
      setState(() {
        _checkingStatus = true;
        _message = null;
      });
    } else {
      _checkingStatus = true;
    }

    final r = await _auth.checkStatus(username: user);
    if (!mounted) return;
    _checkingStatus = false;

    final status = r.status;
    if (status == 'active') {
      _stopStatusPolling();
      setState(() {
        _tab = _AuthTab.login;
        _busy = false;
        _message =
            '¡Cuenta aprobada! Introduce tu contraseña e inicia sesión.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tu cuenta ya está aprobada.')),
      );
      return;
    }

    if (status == 'rejected' || status == 'blocked') {
      _stopStatusPolling();
      setState(() {
        _message = r.message ?? 'Tu solicitud no está disponible.';
      });
      return;
    }

    if (!silent) {
      setState(() {
        _message = r.message ?? 'Sigue pendiente de aprobación.';
      });
    }
  }

  @override
  void dispose() {
    _stopStatusPolling();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    if (_needsLegal && !_acceptLegal) {
      setState(() {
        _message =
            'Marca la casilla para aceptar la política de privacidad y las condiciones.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final password = _passCtrl.text;
    final r = await _auth.login(
      username: _userCtrl.text,
      password: password,
      acceptedLegal: _acceptLegal,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = r.message;
      if (r.needsLegal) {
        _needsLegal = true;
      } else if (r.ok) {
        _needsLegal = false;
      }
      if (r.pending) {
        _tab = _AuthTab.pending;
        _startStatusPolling();
      }
    });
    if (r.ok) {
      _stopStatusPolling();
      await _maybeOfferBiometric(
        username: _userCtrl.text.trim(),
        password: password,
      );
      if (!mounted) return;
      widget.onAuthenticated();
    }
  }

  Future<void> _loginWithBiometric() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await _biometric.authenticateAndLoadCredentials();
    if (!mounted) return;
    if (!result.ok || result.credentials == null) {
      setState(() {
        _busy = false;
        _message = result.errorMessage ??
            'No se ha podido usar la huella. Entra con tu contraseña.';
      });
      return;
    }
    final creds = result.credentials!;
    _userCtrl.text = creds.username;
    _passCtrl.text = creds.password;
    final r = await _auth.login(
      username: creds.username,
      password: creds.password,
      acceptedLegal: _acceptLegal,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = r.message;
      if (r.needsLegal) {
        _needsLegal = true;
      } else if (r.ok) {
        _needsLegal = false;
      }
      if (r.pending) {
        _tab = _AuthTab.pending;
        _startStatusPolling();
      }
    });
    if (r.ok) {
      _stopStatusPolling();
      widget.onAuthenticated();
    }
  }

  Future<void> _maybeOfferBiometric({
    required String username,
    required String password,
  }) async {
    if (!_biometricAvailable || username.isEmpty || password.isEmpty) return;
    if (await _biometric.isEnabled) {
      // Renueva credenciales guardadas tras login con contraseña.
      await _biometric.enable(username: username, password: password);
      return;
    }
    if (!mounted) return;
    final enable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Entrar con huella'),
        content: const Text(
          '¿Quieres usar la huella o el desbloqueo del dispositivo '
          'para entrar la próxima vez sin escribir la contraseña?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Activar'),
          ),
        ],
      ),
    );
    if (enable == true) {
      final enrolled = await _biometric.hasEnrolledBiometrics;
      if (!enrolled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Primero configura una huella en Ajustes del teléfono y vuelve a intentarlo.',
            ),
          ),
        );
        return;
      }
      final ok = await _biometric.enable(
        username: username,
        password: password,
      );
      if (!mounted) return;
      setState(() => _biometricEnabled = ok);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Huella activada para el acceso.'
                : 'No se pudo activar la huella en este dispositivo.',
          ),
        ),
      );
    }
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
      if (r.ok) {
        _tab = _AuthTab.pending;
        _startStatusPolling();
      }
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
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: const [
              TiroAmgWordmark(height: 96),
              SizedBox(height: 28),
              Text(
                'API de autenticación no configurada (APP_AUTH_API_URL / LICENSE_API_URL).',
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          const TiroAmgWordmark(height: 96),
          const SizedBox(height: 28),
          SegmentedButton<_AuthTab>(
            segments: const [
              ButtonSegment(value: _AuthTab.login, label: Text('Entrar')),
              ButtonSegment(value: _AuthTab.register, label: Text('Crear')),
              ButtonSegment(value: _AuthTab.recover, label: Text('Código')),
            ],
            selected: {_tab == _AuthTab.pending ? _AuthTab.login : _tab},
            onSelectionChanged: (s) {
              final next = s.first;
              setState(() {
                _tab = next;
                _message = null;
              });
              if (next == _AuthTab.pending) {
                _startStatusPolling();
              } else {
                _stopStatusPolling();
              }
            },
          ),
          const SizedBox(height: 20),
          if (_tab == _AuthTab.pending) ...[
            Text(
              'Solicitud enviada para «${_userCtrl.text.trim()}».',
              style: TextStyle(
                color: AppColors.title,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Está pendiente de aprobación. Esta pantalla comprueba sola cada 5 segundos; cuando te activen, te avisará para iniciar sesión.',
              style: TextStyle(color: AppColors.subtitle),
            ),
            const SizedBox(height: 16),
            if (_checkingStatus)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            FilledButton(
              onPressed: _checkingStatus
                  ? null
                  : () => _checkApprovalStatus(silent: false),
              child: Text(
                _checkingStatus ? 'Comprobando…' : 'Comprobar ahora',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                _stopStatusPolling();
                setState(() => _tab = _AuthTab.login);
              },
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
            if (_needsLegal) ...[
              const SizedBox(height: 8),
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
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submitLogin,
              child: Text(_busy ? 'Entrando…' : 'Iniciar sesión'),
            ),
            if (_biometricAvailable && _biometricEnabled) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _loginWithBiometric,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Entrar con huella'),
              ),
            ],
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
          ),
        ),
      ),
    );
  }
}
