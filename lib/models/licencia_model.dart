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
  bool get esDemo {
    final planValue = (plan ?? '').trim().toLowerCase();
    if (planValue == 'demo') return true;
    return _asBool(features['is_demo']) ||
        _asBool(features['demo']) ||
        _asBool(features['modo_demo']);
  }
  bool get tienePlan {
    final planValue = (plan ?? '').trim().toLowerCase();
    if (planValue.isEmpty) return false;
    // Compatibilidad: antiguamente "demo" podía venir en plan.
    return planValue != 'demo';
  }
  bool get esDemoSinPlan => esDemo && !tienePlan;
  bool get esPlanConDemo => esDemo && tienePlan;

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

  static DateTime? _parseDate(dynamic raw) {
    final text = raw?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  static bool _asBool(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      return normalized == '1' ||
          normalized == 'true' ||
          normalized == 'yes' ||
          normalized == 'si' ||
          normalized == 'sí';
    }
    return false;
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
