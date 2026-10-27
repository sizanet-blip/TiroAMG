import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../services/app_auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

/// Cuenta AMG: usuario, estado, cambio de contraseña y cierre de sesión.
class CuentaAmgScreen extends StatefulWidget {
  const CuentaAmgScreen({super.key, this.onSignedOut});

  final VoidCallback? onSignedOut;

  @override
  State<CuentaAmgScreen> createState() => _CuentaAmgScreenState();
}

class _CuentaAmgScreenState extends State<CuentaAmgScreen> {
  final _auth = AppAuthService();
  final _biometric = BiometricAuthService();
  final _codeCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();

  String _username = '—';
  String _status = '—';
  String? _recovery;
  var _busy = false;
  var _bioSupported = false;
  var _bioEnabled = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = await _auth.username();
    final status = await _auth.status();
    final recovery = await _auth.lastRecoveryCode();
    final bioOk = await _biometric.isSupported;
    final bioOn = await _biometric.isEnabled;
    if (!mounted) return;
    setState(() {
      _username = user?.trim().isNotEmpty == true ? user!.trim() : '—';
      _status = _statusLabel(status);
      _recovery = recovery;
      _bioSupported = bioOk;
      _bioEnabled = bioOn;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    if (!_bioSupported) return;
    if (!value) {
      await _biometric.disable();
      if (!mounted) return;
      setState(() => _bioEnabled = false);
      return;
    }

    final passCtrl = TextEditingController();
    final pass = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Activar huella'),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Confirma tu contraseña',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, passCtrl.text),
            child: const Text('Activar'),
          ),
        ],
      ),
    );
    if (pass == null || pass.isEmpty || !mounted) return;

    // Valida con login silencioso / re-login.
    final r = await _auth.login(username: _username, password: pass);
    if (!mounted) return;
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.message ?? 'Contraseña incorrecta.')),
      );
      return;
    }
    final ok = await _biometric.enable(username: _username, password: pass);
    if (!mounted) return;
    setState(() => _bioEnabled = ok);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Huella activada. Podrás entrar con ella al cerrar sesión.'
              : 'No se pudo activar la huella en este dispositivo.',
        ),
      ),
    );
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'active':
        return 'Activa';
      case 'pending':
        return 'Pendiente de aprobación';
      case 'rejected':
        return 'Rechazada';
      default:
        return status?.trim().isNotEmpty == true ? status! : '—';
    }
  }

  Future<void> _changePassword() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final newPass = _newPassCtrl.text;
    final r = await _auth.recover(
      username: _username == '—' ? '' : _username,
      recoveryCode: _codeCtrl.text,
      newPassword: newPass,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = r.message;
      if (r.ok) {
        _recovery = r.recoveryCode ?? _recovery;
        _codeCtrl.clear();
        _newPassCtrl.clear();
      }
    });
    if (r.ok && _bioEnabled && _username != '—' && newPass.isNotEmpty) {
      await _biometric.enable(username: _username, password: newPass);
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          '¿Cerrar la sesión de la cuenta AMG en este dispositivo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // UI primero: salir de esta pantalla y volver al login.
    TiroTrackerApp.signOut(context);
    // Red / prefs en segundo plano (no bloquear la UI).
    // ignore: unawaited_futures
    _auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Cuenta AMG',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionCard(
            title: 'Sesión',
            titleIcon: Icons.badge_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _row('Usuario', _username),
                const SizedBox(height: 8),
                _row('Estado', _status),
                if (_recovery != null && _recovery!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Código de recuperación (guárdalo):',
                    style: TextStyle(color: AppColors.subtitle, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    _recovery!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: _recovery!),
                      ),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
          if (_bioSupported) ...[
            const SizedBox(height: 16),
            AppSectionCard(
              title: 'Huella / biometría',
              titleIcon: Icons.fingerprint,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Entrar con huella'),
                subtitle: Text(
                  _bioEnabled
                      ? 'Activada en este dispositivo'
                      : 'Usa la huella en la pantalla de acceso',
                  style: TextStyle(color: AppColors.subtitleSoft, fontSize: 13),
                ),
                value: _bioEnabled,
                onChanged: _busy ? null : _toggleBiometric,
              ),
            ),
          ],
          const SizedBox(height: 16),
          AppSectionCard(
            title: 'Cambiar contraseña',
            titleIcon: Icons.lock_reset,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Usa el código de recuperación que te dimos al crear la cuenta.',
                  style: TextStyle(color: AppColors.subtitleSoft, fontSize: 13),
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
                    labelText: 'Nueva contraseña (mín. 6)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _changePassword,
                  child: Text(_busy ? 'Guardando…' : 'Guardar contraseña'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 10),
                  Text(_message!, style: TextStyle(color: AppColors.subtitle)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '«Mis Datos (Perfil)» en Configuración es el perfil de tirador '
            '(nombre, licencia, club), no la cuenta AMG.',
            style: TextStyle(color: AppColors.subtitleSoft, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: TextStyle(color: AppColors.subtitle)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: AppColors.title,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
