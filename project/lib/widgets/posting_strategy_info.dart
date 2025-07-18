import 'package:flutter/material.dart';
import '../constants/social_platforms.dart';
import '../services/social_action_post_coordinator.dart';

class PostingStrategyInfo extends StatelessWidget {
  final SocialActionPostCoordinator coordinator;

  const PostingStrategyInfo({
    super.key,
    required this.coordinator,
  });

  @override
  Widget build(BuildContext context) {
    final automatedPlatforms = coordinator.getAutomatedPostingPlatforms();
    final manualPlatforms = coordinator.getManualSharingPlatforms();

    if (automatedPlatforms.isEmpty && manualPlatforms.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blue.shade200,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Colors.blue.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Posting Strategy',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade700,
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
            'Manual sharing will open the native share dialog for you to confirm.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
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
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: color.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    SocialPlatforms.getIcon(platform),
                    color: color,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    SocialPlatforms.getDisplayName(platform),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: color,
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

class BusinessAccountWarning extends StatelessWidget {
  final List<String> platformsRequiringBusiness;

  const BusinessAccountWarning({
    super.key,
    required this.platformsRequiringBusiness,
  });

  @override
  Widget build(BuildContext context) {
    if (platformsRequiringBusiness.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.shade200,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Business Account Required',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The following platforms require a Business or Creator account for automated posting:',
            style: TextStyle(
              fontSize: 14,
              color: Colors.orange.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: platformsRequiringBusiness.map((platform) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.shade300,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      SocialPlatforms.getIcon(platform),
                      color: Colors.orange.shade700,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      SocialPlatforms.getDisplayName(platform),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            'Personal accounts will use manual sharing instead.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
