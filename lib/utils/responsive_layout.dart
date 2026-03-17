import 'package:flutter/material.dart';

class ResponsiveLayout {
  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;

  static bool isTablet(BuildContext context) => width(context) >= 600;

  static bool isDesktopLike(BuildContext context) => width(context) >= 1024;

  static double maxContentWidth(BuildContext context) {
    final w = width(context);
    if (w >= 1400) return 1200;
    if (w >= 1024) return 980;
    if (w >= 600) return 840;
    return w;
  }

  static double pagePadding(BuildContext context) {
    final w = width(context);
    if (w >= 1200) return 32;
    if (w >= 900) return 24;
    return 16;
  }

  static int actionGridColumns(BuildContext context, {bool landscape = false}) {
    final w = width(context);
    if (landscape) {
      if (w >= 1200) return 3;
      if (w >= 760) return 2;
      return 1;
    }
    if (w >= 1000) return 3;
    if (w >= 700) return 2;
    return 1;
  }

  static bool isCompactLandscape(
    BuildContext context, {
    double maxWidth = 1000,
  }) {
    final media = MediaQuery.of(context);
    return media.orientation == Orientation.landscape && media.size.width < maxWidth;
  }
}
