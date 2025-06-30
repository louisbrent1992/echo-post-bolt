import 'package:flutter/material.dart';
import '../services/social_action_post_coordinator.dart';
import '../services/manual_share_service.dart';
import '../constants/social_platforms.dart';

class ManualShareButton extends StatelessWidget {
  final SocialActionPostCoordinator coordinator;

  const ManualShareButton({
    super.key,
    required this.coordinator,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, List<String>>>(
      future: coordinator.computePlatformBuckets(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final buckets = snapshot.data ?? {};
        final manualPlatforms = buckets['manual'] ?? [];

        // Filter out platforms that can't be shared manually
        final shareablePlatforms = manualPlatforms.where((platform) {
          final capabilities = SocialPlatforms.getCapabilities(platform);
          return capabilities?.canManualShare == true;
        }).toList();

        if (shareablePlatforms.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ElevatedButton.icon(
            onPressed: () =>
                _showPlatformSelectionSheet(context, shareablePlatforms),
            icon: const Icon(Icons.share, color: Colors.white),
            label: const Text(
              'Manual Share',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.withValues(alpha: 0.8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPlatformSelectionSheet(
    BuildContext context,
    List<String> availablePlatforms,
  ) async {
    final selectedPlatforms = <String>{};

    await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.share,
                    color: Colors.orange,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Select Platforms to Share',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose which platforms to share to via native dialogs:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 16),
              ...availablePlatforms.map((platform) => _buildPlatformCheckbox(
                    platform,
                    selectedPlatforms,
                    setState,
                  )),
              // Add "Other" option for general sharing
              _buildPlatformCheckbox(
                'other',
                selectedPlatforms,
                setState,
                isOther: true,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: selectedPlatforms.isEmpty
                          ? null
                          : () => Navigator.pop(
                              context, selectedPlatforms.toList()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Share'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((selectedPlatforms) async {
      if (selectedPlatforms != null && selectedPlatforms.isNotEmpty) {
        await _performManualShare(selectedPlatforms);
      }
    });
  }

  Widget _buildPlatformCheckbox(
    String platform,
    Set<String> selectedPlatforms,
    StateSetter setState, {
    bool isOther = false,
  }) {
    final isSelected = selectedPlatforms.contains(platform);

    return CheckboxListTile(
      value: isSelected,
      onChanged: (bool? value) {
        setState(() {
          if (value == true) {
            selectedPlatforms.add(platform);
          } else {
            selectedPlatforms.remove(platform);
          }
        });
      },
      title: Row(
        children: [
          if (isOther)
            const Icon(
              Icons.more_horiz,
              color: Colors.grey,
              size: 20,
            )
          else
            Icon(
              SocialPlatforms.getIcon(platform),
              color: SocialPlatforms.getColor(platform),
              size: 20,
            ),
          const SizedBox(width: 8),
          Text(
            isOther ? 'Other Apps' : SocialPlatforms.getDisplayName(platform),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
        ],
      ),
      activeColor: isOther ? Colors.grey : SocialPlatforms.getColor(platform),
      checkColor: Colors.white,
      contentPadding: EdgeInsets.zero,
    );
  }

  Future<void> _performManualShare(List<String> platforms) async {
    try {
      await ManualShareService().shareToPlatforms(
        platforms: platforms,
        action: coordinator.currentPost,
      );
    } catch (e) {
      // Handle error - could show a snackbar or status message
      print('Manual share failed: $e');
    }
  }
}
