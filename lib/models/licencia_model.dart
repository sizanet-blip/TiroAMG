import 'dart:convert';

class LicenciaLocal {
  final int id;
  final String licenciaKey;
  final String estado;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final String? plan;
  final Map<String, dynamic> features;
  final String? deviceId;
  final DateTime? ultimaValidacion;
  final DateTime? proximaValidacion;
  final int diasGraciaOffline;
  final int? maxDispositivos;
  final String? firma;

  const LicenciaLocal({
    required this.id,
    required this.licenciaKey,
    required this.estado,
    required this.fechaInicio,
    required this.fechaFin,
    required this.plan,
    required this.features,
    required this.deviceId,
    required this.ultimaValidacion,
    required this.proximaValidacion,
    required this.diasGraciaOffline,
    required this.maxDispositivos,
    required this.firma,
  });

  bool get estaActiva => estado.toLowerCase() == 'active';

  /// Módulos del servidor/local (inicio, target_shot_detection, …).
  Map<String, dynamic> get modules {
    final raw = features['modules'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    // Compat: los flags van planos en features_json.
    return features;
  }

  String? get contactEmail {
    final v = features['contact_email']?.toString().trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  bool get identifyNeverAsk => features['identify_never'] == true;

  DateTime? get identifySnoozeUntil {
    return DateTime.tryParse(features['identify_snooze_until']?.toString() ?? '')
        ?.toUtc();
  }

  bool get hasInicioModule {
    final v = _boolOf(modules, 'inicio');
    // Sin dato = Inicio activo (default B+C).
    return v ?? true;
  }

  bool get hasDeteccionAutomatica {
    return _boolOf(modules, 'target_shot_detection') ?? false;
  }

  bool get isIdentified =>
      contactEmail != null && contactEmail!.isNotEmpty;

  bool get privacyAccepted => features['privacy_accepted'] == true;

  /// Acceso a la app: basta con aceptar la política de privacidad.
  /// El email de identificación es opcional.
  bool get puedeUsarApp => privacyAccepted;

  factory LicenciaLocal.fromMap(Map<String, dynamic> map) {
    final rawFeatures = map['features_json']?.toString();
    Map<String, dynamic> parsedFeatures = const {};
    if (rawFeatures != null && rawFeatures.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawFeatures);
        if (decoded is Map<String, dynamic>) {
          parsedFeatures = decoded;
        }
      } catch (_) {}
    }

    return LicenciaLocal(
      id: (map['id'] as num?)?.toInt() ?? 1,
      licenciaKey: map['license_key']?.toString() ?? '',
      estado: map['estado']?.toString() ?? 'inactive',
      fechaInicio: _parseDate(map['fecha_inicio']),
      fechaFin: _parseDate(map['fecha_fin']),
      plan: map['plan']?.toString(),
      features: parsedFeatures,
      deviceId: map['device_id']?.toString(),
      ultimaValidacion: _parseDate(map['ultima_validacion']),
      proximaValidacion: _parseDate(map['proxima_validacion']),
      diasGraciaOffline: (map['dias_gracia_offline'] as num?)?.toInt() ?? 3,
      maxDispositivos: (map['max_dispositivos'] as num?)?.toInt(),
      firma: map['firma']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'license_key': licenciaKey,
      'estado': estado,
      'fecha_inicio': fechaInicio?.toUtc().toIso8601String(),
      'fecha_fin': fechaFin?.toUtc().toIso8601String(),
      'plan': plan,
      'features_json': jsonEncode(features),
      'device_id': deviceId,
      'ultima_validacion': ultimaValidacion?.toUtc().toIso8601String(),
      'proxima_validacion': proximaValidacion?.toUtc().toIso8601String(),
      'dias_gracia_offline': diasGraciaOffline,
      'max_dispositivos': maxDispositivos,
      'firma': firma,
    };
  }

  LicenciaLocal copyWithFeatures(Map<String, dynamic> nextFeatures) {
    return LicenciaLocal(
      id: id,
      licenciaKey: licenciaKey,
      estado: estado,
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      plan: plan,
      features: nextFeatures,
      deviceId: deviceId,
      ultimaValidacion: ultimaValidacion,
      proximaValidacion: proximaValidacion,
      diasGraciaOffline: diasGraciaOffline,
      maxDispositivos: maxDispositivos,
      firma: firma,
    );
  }

  static Map<String, dynamic> defaultModulesFeatures() => {
        'inicio': true,
        'target_shot_detection': false,
      };

  static bool? _boolOf(Map<String, dynamic> map, String key) {
    if (!map.containsKey(key)) return null;
    final value = map[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      if (v == 'true' || v == '1' || v == 'yes' || v == 'si' || v == 'sí') {
        return true;
      }
      if (v == 'false' || v == '0' || v == 'no') return false;
    }
    return null;
  }

  static DateTime? _parseDate(dynamic raw) {
    final text = raw?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }
}

class LicenciaCheckResult {
  final bool esValida;
  final bool enGraciaOffline;
  final bool requiereActivacion;
  final String mensaje;
  final LicenciaLocal? licencia;

  const LicenciaCheckResult({
    required this.esValida,
    required this.enGraciaOffline,
    required this.requiereActivacion,
    required this.mensaje,
    required this.licencia,
  });
}
