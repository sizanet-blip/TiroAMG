import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'tiro_amg_app_bar_title.dart';

/// AppBar de marca sin el recorte del `title` de Material AppBar.
class TiroAmgAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TiroAmgAppBar({
    super.key,
    this.section,
    this.title,
    this.actions,
    this.bottom,
    this.backgroundColor,
    this.foregroundColor,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  final String? section;
  final Widget? title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  static const double toolbarHeight = 100;
  static const double _borderHeight = 1;

  @override
  Size get preferredSize => Size.fromHeight(
        toolbarHeight +
            _borderHeight +
            (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.appBar;
    final fg = foregroundColor ?? AppColors.title;
    final theme = Theme.of(context);
    final canPop = ModalRoute.of(context)?.canPop ?? false;

    Widget? leadingWidget = leading;
    if (leadingWidget == null && automaticallyImplyLeading && canPop) {
      leadingWidget = BackButton(color: fg);
    }

    Widget? trailing;
    if (actions != null && actions!.isNotEmpty) {
      trailing = IconTheme(
        data: IconThemeData(color: fg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: actions!,
        ),
      );
    }

    return Material(
      color: bg,
      elevation: 0,
      child: IconTheme(
        data: IconThemeData(color: fg),
        child: DefaultTextStyle(
          style: theme.textTheme.titleLarge?.copyWith(color: fg) ??
              TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w600),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: toolbarHeight,
                  child: NavigationToolbar(
                    leading: leadingWidget,
                    middle: Padding(
                      padding: EdgeInsets.only(
                        left: leadingWidget == null ? 16 : 0,
                        right: 8,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: title ?? TiroAmgAppBarTitle(section: section),
                      ),
                    ),
                    trailing: trailing,
                    centerMiddle: false,
                    middleSpacing: 8,
                  ),
                ),
                if (bottom != null) bottom!,
                if (bottom == null)
                  const SizedBox(
                    height: _borderHeight,
                    width: double.infinity,
                    child: ColoredBox(color: AppColors.border),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
