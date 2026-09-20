import 'package:flutter/material.dart';

/// Tokens visuales TiroAMG (alineados con la home).
abstract final class AppColors {
  static const Color background = Color(0xFFF4F6F8);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE2E8EE);
  static const Color divider = Color(0xFFE8EEF2);
  static const Color appBar = Color(0xFF546E7A); // blueGrey.shade600-ish
  /// Subtítulo de sección bajo el logo en el AppBar.
  static const Color appBarSection = Color(0xFFFFCC80);
  static final Color title = Colors.blueGrey.shade900;
  static final Color subtitle = Colors.blueGrey.shade500;
  static final Color subtitleSoft = Colors.blueGrey.shade400;
  static final Color chevron = Colors.blueGrey.shade300;
  static final Color primary = Colors.blueGrey.shade700;

  static const Color accentTraining = Color(0xFF00796B);
  static const Color accentCompetition = Color(0xFFC79100);
  static const Color accentAnalytics = Color(0xFF3949AB);
  static const Color accentDanger = Color(0xFFC62828);
}

abstract final class AppRadii {
  static const double card = 16;
  static const double iconBox = 12;
}

ThemeData buildTiroAmgTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: Colors.blueGrey,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: base.copyWith(
      primary: AppColors.primary,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.appBar,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 68,
      titleSpacing: 12,
      iconTheme: IconThemeData(color: Colors.white),
      actionsIconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: const BorderSide(color: AppColors.border),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      space: 1,
      thickness: 1,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.primary,
      textColor: AppColors.title,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white60,
      indicatorColor: Colors.white,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: const BorderSide(color: AppColors.border),
      ),
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.title,
      ),
      contentTextStyle: TextStyle(
        fontSize: 14,
        height: 1.35,
        color: AppColors.subtitle,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
    ),
  );
}
