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

  /// Capacidad que entiende el servidor Yii2 (módulos).
  String toServerCapability(LicenseCapability capability) {
    switch (capability) {
      case LicenseCapability.targetDetection:
        return 'target_shot_detection';
      case LicenseCapability.training:
      case LicenseCapability.competition:
      case LicenseCapability.analytics:
      case LicenseCapability.backup:
      case LicenseCapability.settingsRules:
      case LicenseCapability.settingsCatalogs:
        return 'inicio';
    }
  }

  bool canAccess(LicenciaLocal? licencia, LicenseCapability capability) {
    // Sin ficha local: default B+C = Inicio ON, Detección OFF.
    if (capability == LicenseCapability.targetDetection) {
      return licencia?.hasDeteccionAutomatica ?? false;
    }
    return licencia?.hasInicioModule ?? true;
  }

  String requiredModuleLabel(LicenseCapability capability) {
    switch (capability) {
      case LicenseCapability.targetDetection:
        return 'Detección automática';
      default:
        return 'Inicio';
    }
  }

  /// @deprecated usar [requiredModuleLabel]
  String requiredPlanLabel(LicenseCapability capability) =>
      requiredModuleLabel(capability);

  String currentModulesLabel(LicenciaLocal? licencia) {
    if (licencia == null) return 'Inicio';
    if (licencia.hasDeteccionAutomatica && licencia.hasInicioModule) {
      return 'Inicio + Detección automática';
    }
    if (licencia.hasDeteccionAutomatica) return 'Detección automática';
    if (licencia.hasInicioModule) return 'Inicio';
    return 'Sin módulos';
  }

  /// @deprecated usar [currentModulesLabel]
  String currentPlanLabel(String? plan) {
    // Compat para pantallas que aún pasan plan.
    return 'Inicio';
  }
}
