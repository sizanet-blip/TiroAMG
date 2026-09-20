import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Título de AppBar: logo TiroAMG y, opcionalmente, la pantalla actual.
class TiroAmgAppBarTitle extends StatelessWidget {
  const TiroAmgAppBarTitle({
    super.key,
    this.section,
  });

  /// Nombre de la pantalla (p. ej. «Historial», «Configuración»).
  final String? section;

  @override
  Widget build(BuildContext context) {
    final hasSection = section != null && section!.trim().isNotEmpty;
    final logoSize = hasSection ? 28.0 : 40.0;

    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(hasSection ? 7 : 10),
          child: Image.asset(
            'assets/logo.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => Icon(
              Icons.gps_fixed,
              size: logoSize * 0.75,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(width: hasSection ? 8 : 10),
        Text(
          'TiroAMG',
          style: TextStyle(
            color: Colors.white,
            fontSize: hasSection ? 16 : 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            height: 1,
          ),
        ),
      ],
    );

    if (!hasSection) {
      return Align(alignment: Alignment.centerLeft, child: brand);
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        brand,
        const SizedBox(height: 2),
        Text(
          section!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.appBarSection,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.1,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
