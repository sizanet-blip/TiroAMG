import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../help/help_content.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import 'ayuda_documento_screen.dart';
import 'ayuda_faq_screen.dart';
import '../widgets/identificar_instalacion_dialog.dart';
import '../widgets/tiro_amg_app_bar_title.dart';

class AyudaScreen extends StatelessWidget {
  const AyudaScreen({super.key});

  Future<void> _abrirEmail(BuildContext context) async {
    final uri = Uri.parse(
      'mailto:${HelpContent.supportEmail}?subject=${Uri.encodeComponent('Soporte TiroAMG')}',
    );
    final ok = await launchUrl(uri);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo abrir el correo. Escribe a ${HelpContent.supportEmail}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const TiroAmgAppBarTitle(section: 'Ayuda')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Text(
                'Documentación para usuarios',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.title,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Elige el formato que necesites: un resumen rápido, el manual completo o las preguntas más habituales.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppColors.subtitle,
                ),
              ),
              const SizedBox(height: 20),
              AppNavGroup(
                children: [
                  AppNavTile(
                    title: HelpContent.guiaRapida.title,
                    subtitle: HelpContent.guiaRapida.subtitle,
                    icon: Icons.bolt_outlined,
                    color: AppColors.accentCompetition,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AyudaDocumentoScreen(
                          doc: HelpContent.guiaRapida,
                        ),
                      ),
                    ),
                  ),
                  AppNavTile(
                    title: HelpContent.manualCompleto.title,
                    subtitle: HelpContent.manualCompleto.subtitle,
                    icon: Icons.menu_book_outlined,
                    color: AppColors.accentAnalytics,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AyudaDocumentoScreen(
                          doc: HelpContent.manualCompleto,
                        ),
                      ),
                    ),
                  ),
                  AppNavTile(
                    title: 'Preguntas y respuestas',
                    subtitle: 'Dudas frecuentes, con respuestas claras',
                    icon: Icons.help_outline,
                    color: AppColors.accentTraining,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AyudaFaqScreen(),
                      ),
                    ),
                  ),
                  AppNavTile(
                    title: 'Política de privacidad',
                    subtitle: 'Datos personales y derechos (RGPD)',
                    icon: Icons.privacy_tip_outlined,
                    color: AppColors.primary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PoliticaPrivacidadScreen(),
                      ),
                    ),
                  ),
                  AppNavTile(
                    title: 'Condiciones de uso',
                    subtitle: 'Sin garantía; uso bajo tu responsabilidad',
                    icon: Icons.gavel_outlined,
                    color: AppColors.accentCompetition,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CondicionesUsoScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AppSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '¿Necesitas ayuda personalizada?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.title,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Si no encuentras la respuesta en la documentación, escríbenos y te atendemos.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: AppColors.subtitle,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _abrirEmail(context),
                      icon: const Icon(Icons.email_outlined),
                      label: const Text(HelpContent.supportEmail),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentTraining,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
