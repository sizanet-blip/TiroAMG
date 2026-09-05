import 'package:flutter/material.dart';

import '../help/help_content.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

class AyudaFaqScreen extends StatelessWidget {
  const AyudaFaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Preguntas y respuestas',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Dudas frecuentes sobre TiroAMG, con respuestas claras.',
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: AppColors.subtitle,
            ),
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < HelpContent.faq.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: AppColors.divider,
                    ),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      iconColor: AppColors.primary,
                      collapsedIconColor: AppColors.chevron,
                      title: Text(
                        HelpContent.faq[i].question,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.title,
                        ),
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            HelpContent.faq[i].answer,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: AppColors.subtitle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
