import 'package:flutter/material.dart';
import '../constants/social_platforms.dart';
import '../services/social_action_post_coordinator.dart';

class PostStrategyInfo extends StatelessWidget {
  final SocialActionPostCoordinator coordinator;

  const PostStrategyInfo({
    super.key,
    required this.coordinator,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, List<String>>>(
      future: coordinator.computePlatformBuckets(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  'Analyzing posting strategy...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.red.withValues(alpha: 0.3),
              ),
            ),
            child: const Text(
              'Error analyzing posting strategy',
              style: TextStyle(
                fontSize: 14,
                color: Colors.red,
              ),
            ),
          );
        }

        final buckets = snapshot.data ?? {};
        final automatedPlatforms = buckets['automated'] ?? [];
        final manualPlatforms = buckets['manual'] ?? [];

        if (automatedPlatforms.isEmpty && manualPlatforms.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Color(0xFFFF0055),
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Posting Strategy',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (automatedPlatforms.isNotEmpty) ...[
                _buildStrategySection(
                  context,
                  'Automated Posting',
                  automatedPlatforms,
                  Icons.auto_awesome,
                  Colors.green,
                ),
                if (manualPlatforms.isNotEmpty) const SizedBox(height: 12),
              ],
              if (manualPlatforms.isNotEmpty)
                _buildStrategySection(
                  context,
                  'Manual Sharing',
                  manualPlatforms,
                  Icons.share,
                  Colors.orange,
                ),
              const SizedBox(height: 8),
              Text(
                'Automated posting will publish directly. Manual sharing opens native dialogs.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStrategySection(
    BuildContext context,
    String title,
    List<String> platforms,
    IconData icon,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              color: color,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: platforms.map((platform) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color:
                    SocialPlatforms.getColor(platform).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      SocialPlatforms.getColor(platform).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    SocialPlatforms.getIcon(platform),
                    color: SocialPlatforms.getColor(platform),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    SocialPlatforms.getDisplayName(platform),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: SocialPlatforms.getColor(platform),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
