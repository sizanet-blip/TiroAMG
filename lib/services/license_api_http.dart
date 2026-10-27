import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// HTTP hacia panel / metadata de desarrollo.
/// En Android + host `*.desarrollo`, conecta a [androidDevHost] (10.0.2.2) con
/// Host/SNI del dominio real, porque el emulador no usa el hosts de Windows.
class LicenseApiHttp {
  LicenseApiHttp._();

  static const String _devHostFromEnv = String.fromEnvironment(
    'LICENSE_DEV_HOST',
    defaultValue: '',
  );

  static String get androidDevHost =>
      _devHostFromEnv.trim().isNotEmpty ? _devHostFromEnv.trim() : '10.0.2.2';

  /// GET genérico. En Android + host `*.desarrollo` usa el puente a [androidDevHost].
  static Future<http.Response> get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_needsAndroidDevBridgeFor(uri)) {
      return _requestViaDevBridge(
        logical: uri,
        method: 'GET',
        body: null,
        contentType: null,
        timeout: timeout,
        logTag: 'DevHttp',
      );
    }
    return http.get(uri).timeout(timeout);
  }

  static Future<http.Response> postJson({
    required String baseUrl,
    required String path,
    required String body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final logical = Uri.parse('$base$path');
    final merged = <String, String>{
      'Content-Type': 'application/json',
      ...?headers,
    };

    if (_needsAndroidDevBridgeFor(logical)) {
      return _requestViaDevBridge(
        logical: logical,
        method: 'POST',
        body: body,
        contentType: merged['Content-Type'] ?? 'application/json',
        extraHeaders: merged,
        timeout: timeout,
        logTag: 'License',
      );
    }

    return http.post(logical, headers: merged, body: body).timeout(timeout);
  }

  static bool _needsAndroidDevBridgeFor(Uri uri) {
    if (!Platform.isAndroid) return false;
    return uri.host.endsWith('.desarrollo');
  }

  /// TCP → 10.0.2.2 (HTTP o HTTPS). Host/SNI = dominio lógico del vhost.
  static Future<http.Response> _requestViaDevBridge({
    required Uri logical,
    required String method,
    required String? body,
    required String? contentType,
    Map<String, String>? extraHeaders,
    required Duration timeout,
    required String logTag,
  }) async {
    final port = logical.hasPort
        ? logical.port
        : (logical.scheme == 'https' ? 443 : 80);
    final path = logical.hasQuery
        ? '${logical.path}?${logical.query}'
        : (logical.path.isEmpty ? '/' : logical.path);
    final payload = body == null ? <int>[] : utf8.encode(body);
    final useTls = logical.scheme == 'https';

    debugPrint(
      '[$logTag] bridge ${logical.host} → $androidDevHost:$port$path',
    );

    final raw = await Socket.connect(androidDevHost, port).timeout(timeout);
    late final Socket socket;
    try {
      if (useTls) {
        socket = await SecureSocket.secure(
          raw,
          host: logical.host,
          onBadCertificate: (_) => true,
        ).timeout(timeout);
      } else {
        socket = raw;
      }
    } catch (e) {
      await raw.close();
      rethrow;
    }

    try {
      final headers = StringBuffer()
        ..write('$method $path HTTP/1.1\r\n')
        ..write('Host: ${logical.host}\r\n');
      final skip = {'host', 'content-length', 'connection'};
      if (extraHeaders != null) {
        for (final e in extraHeaders.entries) {
          if (skip.contains(e.key.toLowerCase())) continue;
          headers.write('${e.key}: ${e.value}\r\n');
        }
      } else if (contentType != null) {
        headers.write('Content-Type: $contentType\r\n');
      }
      if (payload.isNotEmpty) {
        headers.write('Content-Length: ${payload.length}\r\n');
      }
      if (extraHeaders == null ||
          !extraHeaders.keys.any((k) => k.toLowerCase() == 'accept')) {
        headers.write('Accept: application/json,*/*\r\n');
      }
      headers
        ..write('Connection: close\r\n')
        ..write('\r\n');

      socket.add(utf8.encode(headers.toString()));
      if (payload.isNotEmpty) {
        socket.add(payload);
      }
      await socket.flush().timeout(timeout);

      final chunks = <int>[];
      await for (final chunk in socket.timeout(timeout)) {
        chunks.addAll(chunk);
      }

      return _parseHttpResponse(chunks, logical);
    } finally {
      await socket.close();
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
