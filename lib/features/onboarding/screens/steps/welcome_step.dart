import 'package:flutter/material.dart';
import 'package:parachute_daily/core/theme/design_tokens.dart';

/// Welcome step - introduces Parachute Daily with brand styling
///
/// "Speak naturally" - A calm, spacious welcome experience
class WelcomeStep extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const WelcomeStep({super.key, required this.onNext, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: Spacing.xl),

            // App icon with brand styling
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    isDark
                        ? BrandColors.nightForest.withValues(alpha: 0.3)
                        : BrandColors.forestMist,
                    isDark
                        ? BrandColors.nightTurquoise.withValues(alpha: 0.2)
                        : BrandColors.turquoiseMist,
                  ],
                ),
                borderRadius: BorderRadius.circular(Radii.xl),
                boxShadow: isDark ? null : Elevation.cardShadow,
              ),
              child: Icon(
                Icons.mic_rounded,
                size: 56,
                color: isDark ? BrandColors.nightForest : BrandColors.forest,
              ),
            ),

            SizedBox(height: Spacing.xxl),

            // Welcome heading
            Text(
              'Welcome to Parachute Daily',
              style: TextStyle(
                fontSize: TypographyTokens.displaySmall,
                fontWeight: FontWeight.bold,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: Spacing.md),

            // Tagline
            Text(
              'Voice-first journaling',
              style: TextStyle(
                fontSize: TypographyTokens.titleLarge,
                fontStyle: FontStyle.italic,
                color: isDark
                    ? BrandColors.nightForest.withValues(alpha: 0.9)
                    : BrandColors.forest,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: Spacing.lg),

            // Subtitle
            Text(
              'Speak your thoughts, capture moments, and reflect naturally',
              style: TextStyle(
                fontSize: TypographyTokens.bodyLarge,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: Spacing.lg),

            // Local-first badge with brand styling
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.md,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightTurquoise.withValues(alpha: 0.1)
                    : BrandColors.turquoiseMist,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(
                  color: isDark
                      ? BrandColors.nightTurquoise.withValues(alpha: 0.3)
                      : BrandColors.turquoise.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.offline_bolt,
                    size: 18,
                    color: isDark
                        ? BrandColors.nightTurquoise
                        : BrandColors.turquoiseDeep,
                  ),
                  SizedBox(width: Spacing.sm),
                  Flexible(
                    child: Text(
                      'Works completely offline - your data never leaves your device',
                      style: TextStyle(
                        fontSize: TypographyTokens.bodySmall,
                        color: isDark
                            ? BrandColors.nightTurquoise
                            : BrandColors.turquoiseDeep,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: Spacing.xxxl),

            // Feature highlights
            _buildFeature(
              context,
              icon: Icons.mic,
              title: 'Voice Recording',
              description:
                  'Record your thoughts naturally with voice',
              isDark: isDark,
            ),

            SizedBox(height: Spacing.lg),

            _buildFeature(
              context,
              icon: Icons.offline_bolt,
              title: 'On-Device AI',
              description: 'Local transcription and semantic search - no cloud needed',
              isDark: isDark,
            ),

            SizedBox(height: Spacing.lg),

            _buildFeature(
              context,
              icon: Icons.folder_open,
              title: 'Markdown Journals',
              description: 'Entries saved as markdown - portable and yours forever',
              isDark: isDark,
            ),

            SizedBox(height: Spacing.lg),

            _buildFeature(
              context,
              icon: Icons.bluetooth,
              title: 'Omi Device Support',
              description:
                  'Optional wearable pendant for hands-free capture',
              isDark: isDark,
            ),

            SizedBox(height: Spacing.xxxl),

            // Continue button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      isDark ? BrandColors.nightForest : BrandColors.forest,
                  foregroundColor: BrandColors.softWhite,
                  padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
                child: Text(
                  'Get Started',
                  style: TextStyle(
                    fontSize: TypographyTokens.bodyLarge,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            SizedBox(height: Spacing.md),

            // Skip button
            TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
              child: const Text('Skip setup'),
            ),

            SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildFeature(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: isDark
                ? BrandColors.nightForest.withValues(alpha: 0.2)
                : BrandColors.forestMist.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Icon(
            icon,
            size: 22,
            color: isDark ? BrandColors.nightForest : BrandColors.forest,
          ),
        ),
        SizedBox(width: Spacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: TypographyTokens.bodyLarge,
                  fontWeight: FontWeight.bold,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
              SizedBox(height: Spacing.xs),
              Text(
                description,
                style: TextStyle(
                  fontSize: TypographyTokens.bodyMedium,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
