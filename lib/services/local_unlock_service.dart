import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum LocalUnlockVerdict { ok, missing, mismatch, expired }

/// Comprobante local tras un login online correcto.
/// Permite entrar sin red con la misma contraseña, como máximo [grace].
class LocalUnlockService {
  LocalUnlockService();

  static const Duration grace = Duration(days: 14);

  static const _kUser = 'local_unlock_user';
  static const _kSalt = 'local_unlock_salt';
  static const _kHash = 'local_unlock_hash';
  static const _kAt = 'local_unlock_at';

  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> save({
    required String username,
    required String password,
  }) async {
    final user = username.trim();
    if (user.isEmpty || password.isEmpty) return;
    final salt = _randomSalt();
    await _secure.write(key: _kUser, value: user);
    await _secure.write(key: _kSalt, value: salt);
    await _secure.write(key: _kHash, value: _hash(salt, password));
    await _secure.write(key: _kAt, value: DateTime.now().toUtc().toIso8601String());
  }

  /// Actualiza el verificador si ya había un acceso local de este usuario.
  Future<void> updatePasswordIfPresent({
    required String username,
    required String password,
  }) async {
    final current = await _secure.read(key: _kUser);
    if (current == null || current != username.trim()) return;
    await save(username: username, password: password);
  }

  /// Renueva el plazo tras comprobar la cuenta con el panel.
  Future<void> touch() async {
    final user = await _secure.read(key: _kUser);
    if (user == null || user.isEmpty) return;
    await _secure.write(key: _kAt, value: DateTime.now().toUtc().toIso8601String());
  }

  Future<void> clear() async {
    await _secure.delete(key: _kUser);
    await _secure.delete(key: _kSalt);
    await _secure.delete(key: _kHash);
    await _secure.delete(key: _kAt);
  }

  Future<LocalUnlockVerdict> verify({
    required String username,
    required String password,
  }) async {
    final matches = await matchesPassword(username: username, password: password);
    if (matches == null) return LocalUnlockVerdict.missing;
    if (!matches) return LocalUnlockVerdict.mismatch;
    if (await _isExpired()) return LocalUnlockVerdict.expired;
    return LocalUnlockVerdict.ok;
  }

  /// `null` si no hay comprobante. No mira la caducidad.
  Future<bool?> matchesPassword({
    required String username,
    required String password,
  }) async {
    final user = await _secure.read(key: _kUser);
    final salt = await _secure.read(key: _kSalt);
    final hash = await _secure.read(key: _kHash);
    if (user == null || salt == null || hash == null || user.isEmpty) {
      return null;
    }
    if (user != username.trim()) return null;
    return hash == _hash(salt, password);
  }

  Future<bool> _isExpired() async {
    final raw = await _secure.read(key: _kAt);
    final at = DateTime.tryParse(raw ?? '');
    if (at == null) return true;
    return DateTime.now().toUtc().difference(at.toUtc()) > grace;
  }

  String _hash(String salt, String password) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }

  String _randomSalt() {
    final rnd = Random.secure();
    return List.generate(16, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
