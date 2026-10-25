import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Título de AppBar: wordmark TiroAMG y, opcionalmente, la pantalla actual.
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
    final logoHeight = hasSection ? 54.0 : 68.0;

    final logo = SizedBox(
      height: logoHeight,
      width: double.infinity,
      child: FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.contain,
        child: Image.asset(
          'assets/tiroamg_wordmark.png',
          width: 933,
          height: 269,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Text(
            'TiroAMG',
            style: TextStyle(
              color: AppColors.title,
              fontSize: hasSection ? 18 : 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );

    if (!hasSection) return logo;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        logo,
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

/// Wordmark completo (con eslogan) para cabeceras de página como la home.
class TiroAmgWordmark extends StatelessWidget {
  const TiroAmgWordmark({
    super.key,
    this.height = 88,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/tiroamg_wordmark.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Text(
        'TiroAMG',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: height * 0.35,
          fontWeight: FontWeight.w700,
          color: AppColors.title,
        ),
      ),
    );
  }
}
