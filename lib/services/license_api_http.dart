import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// HTTP para el panel de licencias.
/// En Android + `*.desarrollo`, conecta a [androidDevHost] (10.0.2.2) con SNI/Host
/// del dominio real, porque el emulador no usa el hosts de Windows.
class LicenseApiHttp {
  LicenseApiHttp._();

  static const String _devHostFromEnv = String.fromEnvironment(
    'LICENSE_DEV_HOST',
    defaultValue: '',
  );

  static String get androidDevHost =>
      _devHostFromEnv.trim().isNotEmpty ? _devHostFromEnv.trim() : '10.0.2.2';

  static bool get _needsAndroidDevBridge {
    if (!Platform.isAndroid) return false;
    const api = String.fromEnvironment('LICENSE_API_URL', defaultValue: '');
    return api.contains('.desarrollo');
  }

  static Future<http.Response> postJson({
    required String baseUrl,
    required String path,
    required String body,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final logical = Uri.parse('$base$path');

    if (_needsAndroidDevBridge && logical.host.endsWith('.desarrollo')) {
      return _postViaDevBridge(logical, body, timeout);
    }

    return http
        .post(
          logical,
          headers: const {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(timeout);
  }

  /// TCP → 10.0.2.2, TLS con SNI = panel.amg.desarrollo, Host header correcto.
  static Future<http.Response> _postViaDevBridge(
    Uri logical,
    String body,
    Duration timeout,
  ) async {
    final port = logical.hasPort
        ? logical.port
        : (logical.scheme == 'https' ? 443 : 80);
    final path = logical.hasQuery
        ? '${logical.path}?${logical.query}'
        : (logical.path.isEmpty ? '/' : logical.path);
    final payload = utf8.encode(body);

    debugPrint(
      '[License] bridge ${logical.host} → $androidDevHost:$port$path',
    );

    final raw = await Socket.connect(androidDevHost, port).timeout(timeout);
    final SecureSocket secure;
    try {
      secure = await SecureSocket.secure(
        raw,
        host: logical.host,
        onBadCertificate: (_) => true,
      ).timeout(timeout);
    } catch (e) {
      await raw.close();
      rethrow;
    }

    try {
      final headers = StringBuffer()
        ..write('POST $path HTTP/1.1\r\n')
        ..write('Host: ${logical.host}\r\n')
        ..write('Content-Type: application/json\r\n')
        ..write('Content-Length: ${payload.length}\r\n')
        ..write('Accept: application/json\r\n')
        ..write('Connection: close\r\n')
        ..write('\r\n');

      secure.add(utf8.encode(headers.toString()));
      secure.add(payload);
      await secure.flush().timeout(timeout);

      final chunks = <int>[];
      await for (final chunk in secure.timeout(timeout)) {
        chunks.addAll(chunk);
      }

      return _parseHttpResponse(chunks, logical);
    } finally {
      await secure.close();
    }
  }

  static http.Response _parseHttpResponse(List<int> raw, Uri requestUrl) {
    final sep = _indexOfHeaderBodySeparator(raw);
    if (sep < 0) {
      throw const HttpException('Respuesta HTTP incompleta del panel.');
    }

    final head = utf8.decode(raw.sublist(0, sep), allowMalformed: true);
    final bodyBytes = raw.sublist(sep + 4);
    final lines = const LineSplitter().convert(head);
    if (lines.isEmpty) {
      throw const HttpException('Respuesta HTTP vacía del panel.');
    }

    final statusMatch =
        RegExp(r'^HTTP/\d\.\d\s+(\d{3})').firstMatch(lines.first);
    if (statusMatch == null) {
      throw HttpException(
        'Respuesta HTTP inválida: ${lines.first}',
        uri: requestUrl,
      );
    }
    final statusCode = int.parse(statusMatch.group(1)!);

    final headers = <String, String>{};
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final name = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      headers[name] = value;
    }

    var body = utf8.decode(bodyBytes, allowMalformed: true);
    if (headers['transfer-encoding']?.toLowerCase() == 'chunked') {
      body = _decodeChunked(bodyBytes);
    }

    return http.Response(body, statusCode, headers: headers);
  }

  static int _indexOfHeaderBodySeparator(List<int> raw) {
    for (var i = 0; i < raw.length - 3; i++) {
      if (raw[i] == 13 &&
          raw[i + 1] == 10 &&
          raw[i + 2] == 13 &&
          raw[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  static String _decodeChunked(List<int> bodyBytes) {
    final out = <int>[];
    var i = 0;
    while (i < bodyBytes.length) {
      final lineEnd = _indexOfCrlf(bodyBytes, i);
      if (lineEnd < 0) break;
      final sizeHex = utf8.decode(bodyBytes.sublist(i, lineEnd)).trim();
      final size = int.tryParse(sizeHex, radix: 16) ?? 0;
      i = lineEnd + 2;
      if (size == 0) break;
      if (i + size > bodyBytes.length) break;
      out.addAll(bodyBytes.sublist(i, i + size));
      i += size + 2; // data + CRLF
    }
    return utf8.decode(out, allowMalformed: true);
  }

  static int _indexOfCrlf(List<int> bytes, int start) {
    for (var i = start; i < bytes.length - 1; i++) {
      if (bytes[i] == 13 && bytes[i + 1] == 10) return i;
    }
    return -1;
  }
}
