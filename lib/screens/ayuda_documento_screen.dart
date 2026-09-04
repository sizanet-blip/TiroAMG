import 'package:flutter/material.dart';

import '../help/help_content.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

class AyudaDocumentoScreen extends StatelessWidget {
  final HelpDoc doc;

  const AyudaDocumentoScreen({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: doc.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            doc.subtitle,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: AppColors.subtitle,
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < doc.sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            AppSectionCard(
              title: doc.sections[i].title,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in doc.sections[i].paragraphs) ...[
                    Text(
                      p,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: AppColors.title.withValues(alpha: 0.9),
                      ),
                    ),
                    if (doc.sections[i].bullets.isNotEmpty ||
                        p != doc.sections[i].paragraphs.last)
                      const SizedBox(height: 10),
                  ],
                  for (final b in doc.sections[i].bullets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Icon(
                              Icons.circle,
                              size: 6,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              b,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: AppColors.title.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
