import '../models/licencia_model.dart';

enum LicenseCapability {
  training,
  competition,
  analytics,
  backup,
  settingsRules,
  settingsCatalogs,
  targetDetection,
}

class LicensePermissionsService {
  const LicensePermissionsService();

  String toServerCapability(LicenseCapability capability) {
    switch (capability) {
      case LicenseCapability.training:
        return 'training';
      case LicenseCapability.competition:
        return 'competition_mode';
      case LicenseCapability.analytics:
        return 'advanced_stats';
      case LicenseCapability.backup:
        return 'backup_export';
      case LicenseCapability.settingsRules:
        return 'training_rules';
      case LicenseCapability.settingsCatalogs:
        return 'catalog_management';
      case LicenseCapability.targetDetection:
        return 'target_shot_detection';
    }
  }

  bool canAccess(LicenciaLocal? licencia, LicenseCapability capability) {
    if (licencia == null) return false;

    final tier = _planTier(licencia.plan);

    // Features remotas: si el backend envía una bandera concreta, prevalece.
    final features = licencia.features;
    switch (capability) {
      case LicenseCapability.competition:
        if (_featureBool(features, 'competition_mode') != null) {
          return _featureBool(features, 'competition_mode')!;
        }
        return tier >= 2; // pro+
      case LicenseCapability.analytics:
        if (_featureBool(features, 'advanced_stats') != null) {
          return _featureBool(features, 'advanced_stats')!;
        }
        return tier >= 1; // medio+
      case LicenseCapability.backup:
        if (_featureBool(features, 'backup_export') != null) {
          return _featureBool(features, 'backup_export')!;
        }
        return tier >= 2; // pro+
      case LicenseCapability.settingsRules:
        if (_featureBool(features, 'training_rules') != null) {
          return _featureBool(features, 'training_rules')!;
        }
        return tier >= 1; // medio+
      case LicenseCapability.settingsCatalogs:
        if (_featureBool(features, 'catalog_management') != null) {
          return _featureBool(features, 'catalog_management')!;
        }
        return tier >= 2; // pro+
      case LicenseCapability.targetDetection:
        if (_featureBool(features, 'target_shot_detection') != null) {
          return _featureBool(features, 'target_shot_detection')!;
        }
        return tier >= 3; // completo
      case LicenseCapability.training:
        return true; // siempre permitido con licencia válida
    }
  }

  String requiredPlanLabel(LicenseCapability capability) {
    switch (capability) {
      case LicenseCapability.training:
        return 'Básico';
      case LicenseCapability.analytics:
      case LicenseCapability.settingsRules:
        return 'Medio';
      case LicenseCapability.competition:
      case LicenseCapability.backup:
      case LicenseCapability.settingsCatalogs:
        return 'Pro';
      case LicenseCapability.targetDetection:
        return 'Completo';
    }
  }

  String currentPlanLabel(String? plan) {
    switch (_planTier(plan)) {
      case 3:
        return 'Completo';
      case 2:
        return 'Pro';
      case 1:
        return 'Medio';
      default:
        return 'Básico';
    }
  }

  int _planTier(String? rawPlan) {
    final plan = (rawPlan ?? '').trim().toLowerCase();
    if (plan.isEmpty) return 0;

    // Nivel 4
    if ([
      'completo',
      'elite_vision',
      'elite vision',
      'elite visión',
      'tactical_vision',
      'enterprise_vision',
    ].contains(plan)) {
      return 3;
    }

    // Nivel 3
    if ([
      'pro',
      'performance',
      'professional',
      'professional_plus',
      'match_pro',
      'rendimiento',
    ].contains(plan)) {
      return 2;
    }

    // Nivel 2
    if ([
      'medio',
      'advanced',
      'avanzado',
      'precision',
    ].contains(plan)) {
      return 1;
    }

    // Nivel 1
    if ([
      'basic',
      'basico',
      'básico',
      'essential',
      'esencial',
      'starter',
      'foundation',
    ].contains(plan)) {
      return 0;
    }

    return 0;
  }

  bool? _featureBool(Map<String, dynamic> features, String key) {
    if (!features.containsKey(key)) return null;
    final value = features[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      if (v == 'true' || v == '1' || v == 'yes' || v == 'si' || v == 'sí') {
        return true;
      }
      if (v == 'false' || v == '0' || v == 'no') {
        return false;
      }
    }
    return null;
  }
}
