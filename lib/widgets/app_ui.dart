import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Scaffold de página con fondo unificado y contenido centrado.
class AppPageScaffold extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final Widget body;
  final Widget? floatingActionButton;
  final double maxWidth;
  final bool scrollable;
  final EdgeInsetsGeometry padding;

  const AppPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.maxWidth = 560,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 28),
  });

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: scrollable
            ? SingleChildScrollView(padding: padding, child: body)
            : Padding(padding: padding, child: body),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      body: content,
    );
  }
}

/// Bloque blanco con borde suave (como el menú de home).
class AppSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? title;
  final IconData? titleIcon;
  final Color? titleIconColor;

  const AppSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.title,
    this.titleIcon,
    this.titleIconColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  if (titleIcon != null) ...[
                    Icon(
                      titleIcon,
                      size: 20,
                      color: titleIconColor ?? AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      title!,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.title,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Grupo de filas de navegación dentro de una card.
class AppNavGroup extends StatelessWidget {
  final List<Widget> children;
  final String? header;

  const AppNavGroup({
    super.key,
    required this.children,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              header!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppColors.subtitle,
              ),
            ),
          ),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    indent: 68,
                    endIndent: 16,
                    color: AppColors.divider,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Fila de menú tipo home.
class AppNavTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;

  const AppNavTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.iconBox),
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.title,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.subtitleSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  Icon(Icons.chevron_right, color: AppColors.chevron),
            ],
          ),
        ),
      ),
    );
  }
}

/// Diálogo alineado con cards blancas de la app.
class AppDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;
  final IconData? icon;
  final Color? iconColor;

  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      title: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (iconColor ?? AppColors.primary).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.iconBox),
              ),
              child: Icon(
                icon,
                size: 20,
                color: iconColor ?? AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.title,
              ),
            ),
          ),
        ],
      ),
      content: content,
      actions: actions,
    );
  }
}

/// Acciones estándar Cancelar + primario.
List<Widget> appDialogActions({
  required BuildContext context,
  required String confirmLabel,
  required VoidCallback? onConfirm,
  String cancelLabel = 'Cancelar',
  bool danger = false,
}) {
  return [
    TextButton(
      onPressed: () => Navigator.pop(context),
      child: Text(
        cancelLabel,
        style: TextStyle(color: AppColors.subtitle),
      ),
    ),
    FilledButton(
      style: danger
          ? FilledButton.styleFrom(backgroundColor: AppColors.accentDanger)
          : null,
      onPressed: onConfirm,
      child: Text(confirmLabel),
    ),
  ];
}

/// Botón primario a ancho completo.
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (icon != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
        ),
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
