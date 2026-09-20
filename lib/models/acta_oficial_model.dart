import 'dart:convert';

/// Acta / puntuación oficial del árbitro para un torneo (día + modalidad).
class ActaOficialTorneo {
  final int idModalidad;
  final String fechaDia; // yyyy-MM-dd
  final double? totalOficial;
  final int? moscasOficiales;
  final String? nota;
  /// Conteos por valor: claves "X","10","9",…,"0" → cantidad.
  final Map<String, int> conteos;

  const ActaOficialTorneo({
    required this.idModalidad,
    required this.fechaDia,
    this.totalOficial,
    this.moscasOficiales,
    this.nota,
    this.conteos = const {},
  });

  static const List<String> clavesOrden = [
    'X', '10', '9', '8', '7', '6', '5', '4', '3', '2', '1', '0',
  ];

  factory ActaOficialTorneo.fromMap(Map<String, dynamic> map) {
    return ActaOficialTorneo(
      idModalidad: (map['id_modalidad'] as num).toInt(),
      fechaDia: map['fecha_dia'] as String,
      totalOficial: (map['total_oficial'] as num?)?.toDouble(),
      moscasOficiales: (map['moscas_oficiales'] as num?)?.toInt(),
      nota: map['nota'] as String?,
      conteos: parseConteosJson(map['conteos_json']?.toString()),
    );
  }

  Map<String, dynamic> toMap() => {
        'id_modalidad': idModalidad,
        'fecha_dia': fechaDia,
        'total_oficial': totalOficial,
        'moscas_oficiales': moscasOficiales ?? conteos['X'],
        'nota': nota,
        'conteos_json': encodeConteos(conteos),
      };

  bool get tieneConteos => conteos.values.any((c) => c > 0);

  int get totalDisparosConteo =>
      conteos.values.fold<int>(0, (a, b) => a + b);

  /// Suma de puntos del desglose (X = 10).
  double? get totalDesdeConteos {
    if (!tieneConteos) return null;
    double sum = 0;
    conteos.forEach((k, qty) {
      if (qty <= 0) return;
      if (k == 'X') {
        sum += 10 * qty;
      } else {
        final v = double.tryParse(k);
        if (v != null) sum += v * qty;
      }
    });
    return sum;
  }

  String get resumenConteos {
    final parts = <String>[];
    for (final k in clavesOrden) {
      final n = conteos[k] ?? 0;
      if (n > 0) parts.add('$n-$k');
    }
    return parts.join(', ');
  }

  static Map<String, int> parseConteosJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, int>{};
      decoded.forEach((k, v) {
        final key = k.toString().toUpperCase();
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
        if (n > 0) out[key == 'x' ? 'X' : key] = n;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static String? encodeConteos(Map<String, int> conteos) {
    final clean = <String, int>{};
    for (final k in clavesOrden) {
      final n = conteos[k] ?? 0;
      if (n > 0) clean[k] = n;
    }
    if (clean.isEmpty) return null;
    return jsonEncode(clean);
  }

  /// Parsea textos tipo: `3-X, 2-10, 6-8` o `3X 2x10 6×8`.
  static Map<String, int>? parseDesgloseTexto(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final re = RegExp(
      r'(\d+)\s*[-x×*]?\s*(X|10|9|8|7|6|5|4|3|2|1|0)\b',
      caseSensitive: false,
    );
    final out = <String, int>{};
    var found = false;
    for (final m in re.allMatches(t)) {
      found = true;
      final qty = int.parse(m.group(1)!);
      var key = m.group(2)!.toUpperCase();
      if (key == 'X') {
        out['X'] = (out['X'] ?? 0) + qty;
      } else {
        out[key] = (out[key] ?? 0) + qty;
      }
    }
    return found ? out : null;
  }
}

/// Comparación app vs oficial resuelta con prioridad:
/// 1) total de torneo  2) desglose conteos  3) series  4) tiros
class ComparacionActaOficial {
  final double totalApp;
  final double? totalOficial;
  final String fuenteOficial; // torneo | conteos | series | tiros | ninguna
  final int seriesConOficial;
  final int tirosConOficial;
  final String? resumenConteos;

  const ComparacionActaOficial({
    required this.totalApp,
    required this.totalOficial,
    required this.fuenteOficial,
    required this.seriesConOficial,
    required this.tirosConOficial,
    this.resumenConteos,
  });

  double? get delta =>
      totalOficial == null ? null : totalOficial! - totalApp;

  bool get tieneOficial => totalOficial != null;
}
