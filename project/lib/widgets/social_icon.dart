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
    Key? key,
    required this.platform,
    required this.isSelected,
    required this.onTap,
    this.size = 48.0,
  }) : super(key: key);

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
      case SocialPlatform.instagram:
        return Icons.camera_alt; // Using built-in icon, can replace with custom
      case SocialPlatform.facebook:
        return Icons.facebook;
      case SocialPlatform.twitter:
        return Icons.close; // X icon for Twitter/X
      case SocialPlatform.tiktok:
        return Icons.music_note; // Placeholder for TikTok
    }
  }

  String _getLabel() {
    switch (widget.platform) {
      case SocialPlatform.instagram:
        return 'IG';
      case SocialPlatform.facebook:
        return 'FB';
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Ripple effect when selected
              if (widget.isSelected)
                RippleCircle(
                  color: const Color(0xFFFF0080),
                  size: widget.size,
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
                        color: widget.isSelected
                            ? Colors.transparent
                            : Colors.white,
                        border: widget.isSelected
                            ? Border.all(
                                color: const Color(0xFFFF0080),
                                width: 2,
                              )
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
          const SizedBox(height: 4),
          // Platform label
          Text(
            _getLabel(),
            style: const TextStyle(
              color: Color(0xFFEEEEEE),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class SocialIconsRow extends StatefulWidget {
  final List<String> selectedPlatforms;
  final Function(String) onPlatformToggle;

  const SocialIconsRow({
    Key? key,
    required this.selectedPlatforms,
    required this.onPlatformToggle,
  }) : super(key: key);

  @override
  State<SocialIconsRow> createState() => _SocialIconsRowState();
}

class _SocialIconsRowState extends State<SocialIconsRow>
    with TickerProviderStateMixin {
  late AnimationController _introController;
  late List<Animation<double>> _introAnimations;

  final List<SocialPlatform> _platforms = [
    SocialPlatform.instagram,
    SocialPlatform.facebook,
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
          index * 0.2,
          0.8 + (index * 0.05),
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
      case SocialPlatform.instagram:
        return 'instagram';
      case SocialPlatform.facebook:
        return 'facebook';
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(_platforms.length, (index) {
        final platform = _platforms[index];
        final platformString = _platformToString(platform);

        return AnimatedBuilder(
          animation: _introAnimations[index],
          builder: (context, child) {
            // Clamp the animation value to ensure opacity stays within valid range
            final animationValue =
                _introAnimations[index].value.clamp(0.0, 1.0);

            return Transform.scale(
              scale: animationValue,
              child: Opacity(
                opacity: animationValue,
                child: SocialIcon(
                  platform: platform,
                  isSelected: widget.selectedPlatforms.contains(platformString),
                  onTap: () => _handlePlatformTap(platformString),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
