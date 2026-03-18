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
        // El plan comercial manda para visibilidad; features solo amplían.
        return tier >= 1 || _featureBool(features, 'competition_mode') == true;
      case LicenseCapability.analytics:
        // Analítica solo en Competición Plus o superior.
        return tier >= 2;
      case LicenseCapability.backup:
        return tier >= 2 || _featureBool(features, 'backup_export') == true;
      case LicenseCapability.settingsRules:
        return tier >= 0 || _featureBool(features, 'training_rules') == true;
      case LicenseCapability.settingsCatalogs:
        return tier >= 2 || _featureBool(features, 'catalog_management') == true;
      case LicenseCapability.targetDetection:
        return tier >= 3 || _featureBool(features, 'target_shot_detection') == true;
      case LicenseCapability.training:
        return true; // siempre permitido con licencia válida
    }
  }

  String requiredPlanLabel(LicenseCapability capability) {
    switch (capability) {
      case LicenseCapability.training:
        return 'Básico';
      case LicenseCapability.analytics:
        return 'Pro';
      case LicenseCapability.settingsRules:
        return 'Entrenamiento';
      case LicenseCapability.competition:
        return 'Competición';
      case LicenseCapability.backup:
      case LicenseCapability.settingsCatalogs:
        return 'Competición Plus';
      case LicenseCapability.targetDetection:
        return 'Completo';
    }
  }

  String currentPlanLabel(String? plan) {
    switch (_planTier(plan)) {
      case 3:
        return 'Completo';
      case 2:
        return 'Competición Plus';
      case 1:
        return 'Competición';
      default:
        return 'Entrenamiento';
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
      'competition_plus',
      'competicion_plus',
      'competición_plus',
      'competicion plus',
      'competición plus',
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
      'competition',
      'competicion',
      'competición',
      'advanced',
      'avanzado',
      'precision',
    ].contains(plan)) {
      return 1;
    }

    // Nivel 1
    if ([
      'basic',
      'training',
      'entrenamiento',
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
