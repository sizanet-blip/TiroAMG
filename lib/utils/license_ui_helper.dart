import 'package:flutter/material.dart';

import '../models/licencia_model.dart';
import '../services/license_permissions_service.dart';

class LicenseUiHelper {
  const LicenseUiHelper._();

  static Color lockColorForPlan(String? planLabel) {
    final plan = (planLabel ?? '').trim().toLowerCase();
    switch (plan) {
      case 'medio':
        return Colors.blue;
      case 'pro':
        return Colors.purple;
      case 'completo':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  static String blockedTooltip({
    required LicensePermissionsService permissions,
    required LicenseCapability capability,
  }) {
    final requiredPlan = permissions.requiredPlanLabel(capability);
    return 'Bloqueado (requiere $requiredPlan)';
  }

  static void showBlockedSnackBar({
    required BuildContext context,
    required LicensePermissionsService permissions,
    required LicenciaLocal? licencia,
    required LicenseCapability capability,
  }) {
    final planActual = permissions.currentPlanLabel(licencia?.plan);
    final planNecesario = permissions.requiredPlanLabel(capability);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Función bloqueada por licencia. Plan actual: $planActual. Requiere: $planNecesario.',
        ),
      ),
    );
  }
}

