import 'package:flutter/material.dart';
import '../config/community_config.dart';

Future<void> showCommunityInfoDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const CommunityInfoDialog(),
  );
}

class CommunityInfoButton extends StatelessWidget {
  const CommunityInfoButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: () => showCommunityInfoDialog(context),
        icon: const Icon(Icons.menu_book_outlined),
        label: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Conoce más sobre la comunidad'),
        ),
      ),
    );
  }
}

class CommunityInfoDialog extends StatelessWidget {
  const CommunityInfoDialog({super.key});

  static final _historyParagraphs = CommunityConfig.history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: screenSize.height * .86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.location_city_outlined,
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nuestra comunidad',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          CommunityConfig.legalName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AnniversaryBanner(theme: theme),
                    const SizedBox(height: 22),
                    Text(
                      'Nuestra historia',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final paragraph in _historyParagraphs) ...[
                      Text(
                        paragraph,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                      ),
                      const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Nuestra comunidad en imágenes',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _CommunityImage(
                      assetPath: CommunityConfig.communityImages[0],
                      semanticLabel: 'Vista de la comunidad',
                    ),
                    const SizedBox(height: 14),
                    _CommunityImage(
                      assetPath: CommunityConfig.communityImages[1],
                      semanticLabel: 'Familias de la comunidad reunidas',
                    ),
                    const SizedBox(height: 14),
                    _CommunityImage(
                      assetPath: CommunityConfig.communityImages[2],
                      semanticLabel: 'Vecinos trabajando por la comunidad',
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Entendido'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnniversaryBanner extends StatelessWidget {
  const _AnniversaryBanner({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            Icons.celebration_outlined,
            size: 36,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  CommunityConfig.anniversaryTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  CommunityConfig.anniversaryDates,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityImage extends StatelessWidget {
  const _CommunityImage({
    required this.assetPath,
    required this.semanticLabel,
  });

  final String assetPath;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}
