import 'package:flutter/material.dart';
import 'ripple_circle.dart';
import '../constants/typography.dart';
import '../constants/social_platforms.dart';

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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Beautiful ripple effect when selected - reusing Unified Action Button animation
          if (widget.isSelected)
            SocialIconRipple(
              color: widget.platform.color,
              size: widget.size,
              rippleCount: 3,
              isActive: widget.isSelected,
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
                            color: widget.platform.color,
                            width: 2,
                          )
                        : null,
                    boxShadow: widget.isSelected
                        ? [
                            BoxShadow(
                              color: widget.platform.color
                                  .withAlpha((0.3 * 255).round()),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    widget.platform.icon,
                    color: widget.isSelected
                        ? widget.platform.color
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
      children: SocialPlatforms.all
          .map((platform) => _buildSocialIcon(
              platform,
              SocialPlatforms.getIcon(platform),
              SocialPlatforms.getColor(platform)))
          .toList(),
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
            // Beautiful ripple effect when selected - reusing Unified Action Button animation
            if (isSelected)
              SocialIconRipple(
                color: color,
                size: maxHeight * 0.8,
                rippleCount: 3,
                isActive: isSelected,
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
                            fontSize:
                                AppTypography.small, // Small font for labels
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
      case 'youtube':
        return 'YT';
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
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
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
        maxHeight: 52, // Increased from 44 to 52 for more presence
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
                fontSize: AppTypography.large, // Large font for titles
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
      slot6: rightAction,
    );
  }
}

/// Seven-icon header for Command Screen with evenly distributed icons
class SevenIconHeader extends StatelessWidget {
  final List<String> selectedPlatforms;
  final Function(String)? onPlatformToggle;
  final Widget? leftAction;
  final Widget? rightAction;
  final double height;
  final bool enableInteraction;
  final List<String>?
      incompatiblePlatforms; // NEW: List of incompatible platforms
  final Map<String, bool>?
      platformAuthenticationState; // NEW: Authentication state

  const SevenIconHeader({
    super.key,
    required this.selectedPlatforms,
    this.onPlatformToggle,
    this.leftAction,
    this.rightAction,
    this.height = 54,
    this.enableInteraction = true,
    this.incompatiblePlatforms, // NEW: Optional incompatible platforms list
    this.platformAuthenticationState, // NEW: Optional authentication state
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Icon 1: Reset button (exactly 1/7 width, no extra padding)
          Expanded(
            child: Center(
              child: _buildEquallySpacedActionIcon(
                leftAction,
                height * 0.8, // Match social media icon size exactly
              ),
            ),
          ),

          // Icons 2-6: Social media platforms (exactly 1/7 width each)
          ...SocialPlatforms.all.map((platform) {
            final isSelected = selectedPlatforms.contains(platform);
            final isIncompatible =
                incompatiblePlatforms?.contains(platform) ?? false;
            final isAuthenticated =
                platformAuthenticationState?[platform] ?? false;
            final color = SocialPlatforms.getColor(platform);
            final icon = SocialPlatforms.getIcon(platform);

            return Expanded(
              child: Center(
                child: _buildEvenlySpacedSocialIcon(
                  platform,
                  icon,
                  color,
                  isSelected,
                  isIncompatible, // NEW: Pass incompatible state
                  isAuthenticated, // NEW: Pass authentication state
                  height * 0.8, // Consistent sizing
                ),
              ),
            );
          }).toList(),

          // Icon 7: History button (exactly 1/7 width, no extra padding)
          Expanded(
            child: Center(
              child: _buildEquallySpacedActionIcon(
                rightAction,
                height * 0.8, // Match social media icon size exactly
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Wraps action widgets (reset/history) to match social media icon sizing exactly
  Widget _buildEquallySpacedActionIcon(Widget? actionWidget, double size) {
    if (actionWidget == null) {
      return const SizedBox.shrink();
    }

    // Extract the actual icon and onPressed from IconButton if that's what we have
    if (actionWidget is IconButton) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: actionWidget.onPressed,
          borderRadius: BorderRadius.circular(size / 2),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.1),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Icon(
                (actionWidget.icon as Icon).icon,
                color: Colors.white.withValues(alpha: 0.8),
                size: size * 0.35, // Match social media icon proportions
              ),
            ),
          ),
        ),
      );
    }

    // For non-IconButton widgets, wrap in a sized container
    return SizedBox(
      width: size,
      height: size,
      child: actionWidget,
    );
  }

  Widget _buildEvenlySpacedSocialIcon(
    String platform,
    IconData icon,
    Color color,
    bool isSelected,
    bool isIncompatible, // NEW: Incompatible state parameter
    bool isAuthenticated, // NEW: Authentication state parameter
    double size,
  ) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Beautiful ripple effect when selected (but not if incompatible or unauthenticated)
        if (isSelected && !isIncompatible && isAuthenticated)
          SocialIconRipple(
            color: color,
            size: size,
            rippleCount: 3,
            isActive: isSelected,
          ),

        // Circular icon container
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap:
                enableInteraction && onPlatformToggle != null && !isIncompatible
                    ? () => onPlatformToggle!(platform)
                    : null,
            borderRadius: BorderRadius.circular(size / 2),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: !isAuthenticated
                    ? Colors.grey.withValues(
                        alpha: 0.1) // Grayed out for unauthenticated
                    : isIncompatible
                        ? Colors.grey.withValues(
                            alpha: 0.1) // Grayed out for incompatible
                        : isSelected
                            ? color.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.1),
                border: Border.all(
                  color: !isAuthenticated
                      ? Colors.grey.withValues(
                          alpha: 0.3) // Gray border for unauthenticated
                      : isIncompatible
                          ? Colors.grey.withValues(
                              alpha: 0.3) // Gray border for incompatible
                          : isSelected
                              ? color
                              : Colors.white.withValues(alpha: 0.3),
                  width: isSelected ? 2.0 : 1.5,
                ),
                boxShadow: isSelected && !isIncompatible && isAuthenticated
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: !isAuthenticated
                    ? Colors.grey.withValues(
                        alpha: 0.5) // Grayed out icon for unauthenticated
                    : isIncompatible
                        ? Colors.grey.withValues(
                            alpha: 0.5) // Grayed out icon for incompatible
                        : isSelected
                            ? color
                            : Colors.white.withValues(alpha: 0.8),
                size: size * 0.5, // Increase icon size to make it larger
              ),
            ),
          ),
        ),
      ],
    );
  }
}
