import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ripple_circle.dart';
import '../services/auth_service.dart';

enum SocialPlatform {
  instagram,
  facebook,
  twitter,
  tiktok,
}

class SocialIcon extends StatefulWidget {
  final SocialPlatform platform;
  final bool isSelected;
  final VoidCallback onTap;
  final double size;

  const SocialIcon({
    super.key,
    required this.platform,
    required this.isSelected,
    required this.onTap,
    this.size = 48.0,
  });

  @override
  State<SocialIcon> createState() => _SocialIconState();
}

class _SocialIconState extends State<SocialIcon> with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutQuad,
    ));
  }

  @override
  void didUpdateWidget(SocialIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _scaleController.forward().then((_) {
        _scaleController.reverse();
      });
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  IconData _getIconData() {
    switch (widget.platform) {
      case SocialPlatform.facebook:
        return Icons.facebook; // Facebook icon
      case SocialPlatform.instagram:
        return Icons
            .photo_camera; // Instagram camera icon - more representative
      case SocialPlatform.twitter:
        return Icons
            .tag; // X/Twitter icon - hashtag represents social media/Twitter
      case SocialPlatform.tiktok:
        return Icons
            .play_circle_fill; // TikTok play icon - represents video content
    }
  }

  String _getLabel() {
    switch (widget.platform) {
      case SocialPlatform.facebook:
        return 'FB';
      case SocialPlatform.instagram:
        return 'IG';
      case SocialPlatform.twitter:
        return 'X';
      case SocialPlatform.tiktok:
        return 'TT';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ripple effect when selected
          if (widget.isSelected)
            RippleCircle(
              color: const Color(0xFFFF0080),
              size: widget.size *
                  1.2, // Slightly larger ripple for better visual effect
              duration: const Duration(milliseconds: 1200),
            ),

          // Icon container
          AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        widget.isSelected ? Colors.transparent : Colors.white,
                    border: widget.isSelected
                        ? Border.all(
                            color: const Color(0xFFFF0080),
                            width: 2,
                          )
                        : null,
                    boxShadow: widget.isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFFFF0080)
                                  .withAlpha((0.3 * 255).round()),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    _getIconData(),
                    color: widget.isSelected
                        ? const Color(0xFFFF0080)
                        : Colors.black,
                    size: widget.size * 0.5,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class SocialIconsRow extends StatefulWidget {
  final List<String> selectedPlatforms;
  final Function(String) onPlatformToggle;
  final double? maxHeight; // Add height constraint parameter

  const SocialIconsRow({
    super.key,
    required this.selectedPlatforms,
    required this.onPlatformToggle,
    this.maxHeight,
  });

  @override
  State<SocialIconsRow> createState() => _SocialIconsRowState();
}

class _SocialIconsRowState extends State<SocialIconsRow>
    with TickerProviderStateMixin {
  late AnimationController _introController;
  late List<Animation<double>> _introAnimations;

  final List<SocialPlatform> _platforms = [
    SocialPlatform.facebook,
    SocialPlatform.instagram,
    SocialPlatform.twitter,
    SocialPlatform.tiktok,
  ];

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _introAnimations = List.generate(_platforms.length, (index) {
      return Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _introController,
        curve: Interval(
          index * 0.15, // Reduced overlap for more staggered effect
          0.7 + (index * 0.075), // Adjusted timing
          curve: Curves.easeOutBack,
        ),
      ));
    });

    // Start intro animation
    _introController.forward();
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  String _platformToString(SocialPlatform platform) {
    switch (platform) {
      case SocialPlatform.facebook:
        return 'facebook';
      case SocialPlatform.instagram:
        return 'instagram';
      case SocialPlatform.twitter:
        return 'twitter';
      case SocialPlatform.tiktok:
        return 'tiktok';
    }
  }

  Future<void> _handlePlatformTap(String platformString) async {
    // First toggle the platform selection
    widget.onPlatformToggle(platformString);

    // Check if user is authenticated and platform is connected
    final authService = context.read<AuthService>();
    if (authService.currentUser == null) {
      // User not signed in, show sign-in screen
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to connect social media accounts'),
        ),
      );
      return;
    }

    try {
      // Check if platform is already connected
      final isConnected = await authService.isPlatformConnected(platformString);

      if (!isConnected) {
        // Platform not connected, initiate auth flow
        switch (platformString) {
          case 'facebook':
            await authService.signInWithFacebook();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Facebook account connected successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
            break;
          case 'instagram':
            // Instagram auth is usually done through Facebook
            await authService.signInWithFacebook();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Instagram account connected via Facebook!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
            break;
          case 'twitter':
            await authService.signInWithTwitter();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('X (Twitter) account connected successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
            break;
          case 'tiktok':
            await authService.signInWithTikTok();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('TikTok account connected successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
            break;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to connect ${platformString.toUpperCase()}: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate responsive sizing based on screen dimensions
    final screenSize = MediaQuery.of(context).size;
    final maxAllowedHeight = widget.maxHeight ??
        (screenSize.height * 0.1); // 1/10th of screen height

    // Calculate optimal icon size that fits within height constraint
    // Account for icon + label + spacing
    final availableHeight =
        maxAllowedHeight - 32; // Reserve space for padding and spacing
    final iconSize = (availableHeight * 0.7)
        .clamp(32.0, 48.0); // Icon takes 70% of available height

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxAllowedHeight,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
            vertical: 12), // Minimized vertical padding
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment:
              CrossAxisAlignment.center, // Ensure consistent vertical alignment
          children: List.generate(_platforms.length, (index) {
            final platform = _platforms[index];
            final platformString = _platformToString(platform);

            return Expanded(
              child: AnimatedBuilder(
                animation: _introAnimations[index],
                builder: (context, child) {
                  // Ensure animation value stays within valid range
                  final animationValue =
                      _introAnimations[index].value.clamp(0.0, 1.0);

                  // Use consistent positioning - no transform during animation to maintain layout
                  return Opacity(
                    opacity: animationValue,
                    child: Transform.scale(
                      scale: 0.8 +
                          (0.2 *
                              animationValue), // Subtle scale from 80% to 100%
                      child: SocialIcon(
                        platform: platform,
                        isSelected:
                            widget.selectedPlatforms.contains(platformString),
                        onTap: () => _handlePlatformTap(platformString),
                        size: iconSize,
                      ),
                    ),
                  );
                },
              ),
            );
          }),
        ),
      ),
    );
  }
}
