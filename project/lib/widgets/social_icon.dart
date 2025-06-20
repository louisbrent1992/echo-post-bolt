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

class SocialIconsRow extends StatelessWidget {
  final List<String> selectedPlatforms;
  final Function(String)? onPlatformToggle;
  final double maxHeight;
  final bool showLabels;
  final bool enableInteraction;

  const SocialIconsRow({
    super.key,
    required this.selectedPlatforms,
    this.onPlatformToggle,
    this.maxHeight = 40,
    this.showLabels = false,
    this.enableInteraction = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildSocialIcon('facebook', Icons.facebook, Colors.blue.shade700),
        _buildSocialIcon('instagram', Icons.camera_alt, Colors.pink.shade400),
        _buildSocialIcon(
            'twitter', Icons.alternate_email, Colors.lightBlue.shade400),
        _buildSocialIcon('tiktok', Icons.music_note, const Color(0xFFFF0050)),
      ],
    );
  }

  Widget _buildSocialIcon(String platform, IconData icon, Color color) {
    final isSelected = selectedPlatforms.contains(platform);

    return Expanded(
      child: Container(
        height: maxHeight,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Radiating ripple effect when selected - the "echo" animation
            if (isSelected)
              RippleCircle(
                color: color,
                size: maxHeight *
                    0.9, // Slightly smaller than container for proper fit
                duration: const Duration(milliseconds: 1200),
              ),

            // Circular icon container
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enableInteraction && onPlatformToggle != null
                    ? () => onPlatformToggle!(platform)
                    : null,
                borderRadius:
                    BorderRadius.circular(maxHeight / 2), // Circular touch area
                child: Container(
                  width: maxHeight * 0.8, // Circular container size
                  height: maxHeight * 0.8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, // Circular shape restored
                    color: isSelected
                        ? color.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.1),
                    border: Border.all(
                      color: isSelected
                          ? color
                          : Colors.white.withValues(alpha: 0.3),
                      width: isSelected ? 2.0 : 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        color: isSelected
                            ? color
                            : Colors.white.withValues(alpha: 0.8),
                        size: maxHeight * 0.35, // Proportional icon size
                      ),
                      if (showLabels) ...[
                        const SizedBox(height: 2),
                        Text(
                          _getPlatformLabel(platform),
                          style: TextStyle(
                            color: isSelected
                                ? color
                                : Colors.white.withValues(alpha: 0.7),
                            fontSize: 6, // Smaller text for circular layout
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getPlatformLabel(String platform) {
    switch (platform) {
      case 'facebook':
        return 'FB';
      case 'instagram':
        return 'IG';
      case 'twitter':
        return 'X';
      case 'tiktok':
        return 'TT';
      default:
        return platform.substring(0, 2).toUpperCase();
    }
  }
}

/// Six-slot header grid component for consistent layout across screens
class SixSlotHeader extends StatelessWidget {
  final Widget? slot1; // Far left - typically navigation
  final Widget? slot2to5; // Center slots 2-5 - typically social icons or title
  final Widget? slot6; // Far right - typically settings/profile
  final double height;
  final EdgeInsets padding;

  const SixSlotHeader({
    super.key,
    this.slot1,
    this.slot2to5,
    this.slot6,
    this.height = 60,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      child: Row(
        children: [
          // Slot 1 - Navigation (fixed width)
          SizedBox(
            width: 40,
            child: slot1 ?? const SizedBox.shrink(),
          ),

          // Slots 2-5 - Center content (flexible)
          Expanded(
            child: slot2to5 ?? const SizedBox.shrink(),
          ),

          // Slot 6 - Right action (fixed width)
          SizedBox(
            width: 40,
            child: slot6 ?? const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Header with social media icons for Command Screen
class CommandHeader extends StatelessWidget {
  final List<String> selectedPlatforms;
  final Function(String)? onPlatformToggle;
  final Widget? leftAction;
  final Widget? rightAction;

  const CommandHeader({
    super.key,
    required this.selectedPlatforms,
    this.onPlatformToggle,
    this.leftAction,
    this.rightAction,
  });

  @override
  Widget build(BuildContext context) {
    return SixSlotHeader(
      slot1: leftAction,
      slot2to5: SocialIconsRow(
        selectedPlatforms: selectedPlatforms,
        onPlatformToggle: onPlatformToggle,
        maxHeight: 44, // Slightly larger for better presence
        enableInteraction: onPlatformToggle != null,
      ),
      slot6: rightAction,
    );
  }
}

/// Header with title for other screens
class TitleHeader extends StatelessWidget {
  final String title;
  final Widget? leftAction;
  final Widget? rightAction;
  final TextStyle? titleStyle;

  const TitleHeader({
    super.key,
    required this.title,
    this.leftAction,
    this.rightAction,
    this.titleStyle,
  });

  @override
  Widget build(BuildContext context) {
    return SixSlotHeader(
      slot1: leftAction,
      slot2to5: Center(
        child: Text(
          title,
          style: titleStyle ??
              const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
      slot6: rightAction,
    );
  }
}
