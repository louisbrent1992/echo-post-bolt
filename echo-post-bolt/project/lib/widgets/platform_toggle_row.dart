import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class PlatformToggleRow extends StatelessWidget {
  final List<String> selectedPlatforms;
  final Function(List<String>) onPlatformsChanged;

  const PlatformToggleRow({
    super.key,
    required this.selectedPlatforms,
    required this.onPlatformsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildPlatformToggle(
            context,
            'facebook',
            'Facebook',
            Icons.facebook,
            Colors.blue.shade800,
          ),
          _buildPlatformToggle(
            context,
            'instagram',
            'Instagram',
            Icons.camera_alt,
            Colors.pink.shade400,
          ),
          _buildPlatformToggle(
            context,
            'twitter',
            'Twitter',
            Icons.flutter_dash,
            Colors.lightBlue.shade400,
          ),
          _buildPlatformToggle(
            context,
            'tiktok',
            'TikTok',
            Icons.music_note,
            Colors.black87,
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformToggle(
    BuildContext context,
    String platform,
    String label,
    IconData icon,
    Color color,
  ) {
    final isSelected = selectedPlatforms.contains(platform);
    final authService = Provider.of<AuthService>(context);

    return FutureBuilder<bool>(
      future: authService.isPlatformConnected(platform),
      builder: (context, snapshot) {
        final isConnected = snapshot.data ?? false;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () async {
                if (!isConnected) {
                  // If not connected, initiate the login flow
                  try {
                    switch (platform) {
                      case 'facebook':
                        await authService.signInWithFacebook();
                        break;
                      case 'twitter':
                        await authService.signInWithTwitter();
                        break;
                      case 'tiktok':
                        await authService.signInWithTikTok();
                        break;
                    }

                    // After successful connection, add to selected platforms
                    if (!selectedPlatforms.contains(platform)) {
                      final newPlatforms = List<String>.from(selectedPlatforms)
                        ..add(platform);
                      onPlatformsChanged(newPlatforms);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'Failed to connect to $label: ${e.toString()}')),
                      );
                    }
                  }
                } else {
                  // If already connected, toggle selection
                  final newPlatforms = List<String>.from(selectedPlatforms);
                  if (isSelected) {
                    newPlatforms.remove(platform);
                  } else {
                    newPlatforms.add(platform);
                  }
                  onPlatformsChanged(newPlatforms);
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? color
                        : Theme.of(context).colorScheme.outline,
                    width: 2,
                  ),
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? color
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (!isConnected)
                  Icon(
                    Icons.link_off,
                    size: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
