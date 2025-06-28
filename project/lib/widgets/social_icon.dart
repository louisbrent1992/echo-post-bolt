import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ripple_circle.dart';
import '../constants/typography.dart';
import '../constants/social_platforms.dart';
import '../services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';

class SocialIcon extends StatefulWidget {
  final SocialPlatform platform;
  final bool isSelected;
  final VoidCallback onTap;
  final double size;
  final bool enableAuthFlow;

  const SocialIcon({
    super.key,
    required this.platform,
    required this.isSelected,
    required this.onTap,
    this.size = 48.0,
    this.enableAuthFlow = true,
  });

  @override
  State<SocialIcon> createState() => _SocialIconState();
}

class _SocialIconState extends State<SocialIcon> with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _colorController;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _colorAnimation;
  bool _isAuthorized = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _colorController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutQuad,
    ));

    _colorAnimation = ColorTween(
      begin: Colors.white,
      end: widget.platform.color,
    ).animate(CurvedAnimation(
      parent: _colorController,
      curve: Curves.easeInOut,
    ));

    _checkAuthorizationStatus();
  }

  @override
  void didUpdateWidget(SocialIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _scaleController.forward().then((_) {
        _scaleController.reverse();
      });
    }

    if (widget.platform != oldWidget.platform) {
      _colorAnimation = ColorTween(
        begin: Colors.white,
        end: widget.platform.color,
      ).animate(CurvedAnimation(
        parent: _colorController,
        curve: Curves.easeInOut,
      ));
      _checkAuthorizationStatus();
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthorizationStatus() async {
    if (!mounted) return;

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final isAuthorized =
          await authService.isPlatformConnected(widget.platform.name);

      if (mounted) {
        setState(() {
          _isAuthorized = isAuthorized;
        });

        if (isAuthorized) {
          _colorController.forward();
        } else {
          _colorController.reverse();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAuthorized = false;
        });
        _colorController.reverse();
      }
    }
  }

  Future<void> _handleTap() async {
    if (_isLoading) return;

    if (!_isAuthorized && widget.enableAuthFlow) {
      setState(() {
        _isLoading = true;
      });

      try {
        final authService = Provider.of<AuthService>(context, listen: false);

        if (kDebugMode) {
          print(
              'Starting authentication for platform: ${widget.platform.name}');
        }

        switch (widget.platform.name) {
          case 'facebook':
            await authService.signInWithFacebook();
            break;
          case 'twitter':
            await authService.signInWithTwitter();
            break;
          case 'tiktok':
            await authService.signInWithTikTok();
            break;
          case 'instagram':
            await authService.signInWithInstagramBusiness(context);
            break;
          case 'youtube':
            final result = await authService.signInWithGoogle();
            if (result != null) {
              await _saveYouTubeTokenDirectly(context, authService);
            }
            break;
        }

        if (kDebugMode) {
          print('Authentication completed, checking authorization status...');
        }
        await _checkAuthorizationStatus();

        if (_isAuthorized) {
          if (kDebugMode) {
            print('Platform is now authorized, triggering onTap');
          }
          widget.onTap();
        } else {
          if (kDebugMode) {
            print('Platform is still not authorized after authentication');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Authentication error for ${widget.platform.name}: $e');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Failed to authenticate with ${widget.platform.displayName}: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      if (kDebugMode) {
        print(
            'Platform is already authorized or auth flow disabled, triggering onTap');
      }
      widget.onTap();
    }
  }

  // Helper method to save YouTube token directly
  Future<void> _saveYouTubeTokenDirectly(
      BuildContext context, AuthService authService) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Get Google user info
      final googleUser = await GoogleSignIn().signInSilently();
      if (googleUser != null) {
        final googleAuth = await googleUser.authentication;

        // Save YouTube token using Google credentials
        await firestore
            .collection('users')
            .doc(authService.currentUser!.uid)
            .collection('tokens')
            .doc('youtube')
            .set({
          'access_token': googleAuth.accessToken,
          'id_token': googleAuth.idToken,
          'user_id': googleUser.id,
          'email': googleUser.email,
          'display_name': googleUser.displayName,
          'platform': 'youtube',
          'created_at': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      throw Exception('Failed to save YouTube token: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.isSelected && _isAuthorized)
            SocialIconRipple(
              color: widget.platform.color,
              size: widget.size,
              rippleCount: 3,
              isActive: widget.isSelected,
            ),
          AnimatedBuilder(
            animation: Listenable.merge([_scaleAnimation, _colorAnimation]),
            builder: (context, child) {
              final currentColor = _colorAnimation.value ?? Colors.white;

              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isSelected && _isAuthorized
                        ? Colors.transparent
                        : Colors.white.withOpacity(0.1),
                    border: widget.isSelected && _isAuthorized
                        ? Border.all(
                            color: widget.platform.color,
                            width: 2,
                          )
                        : Border.all(
                            color: currentColor.withOpacity(0.3),
                            width: 1.5,
                          ),
                    boxShadow: widget.isSelected && _isAuthorized
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
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        widget.platform.icon,
                        color: _isAuthorized
                            ? (widget.isSelected
                                ? widget.platform.color
                                : currentColor)
                            : Colors.white.withOpacity(0.8),
                        size: widget.size * 0.5,
                      ),
                      if (_isLoading)
                        Container(
                          width: widget.size * 0.3,
                          height: widget.size * 0.3,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              widget.platform.color,
                            ),
                          ),
                        ),
                    ],
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
              context,
              platform,
              SocialPlatforms.getIcon(platform),
              SocialPlatforms.getColor(platform)))
          .toList(),
    );
  }

  Widget _buildSocialIcon(
      BuildContext context, String platform, IconData icon, Color color) {
    final isSelected = selectedPlatforms.contains(platform);

    return FutureBuilder<bool>(
      future: Provider.of<AuthService>(context, listen: false)
          .isPlatformConnected(platform),
      builder: (context, snapshot) {
        final isAuthorized = snapshot.data ?? false;

        return Expanded(
          child: Container(
            height: maxHeight,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isSelected && isAuthorized)
                  SocialIconRipple(
                    color: color,
                    size: maxHeight * 0.8,
                    rippleCount: 3,
                    isActive: isSelected,
                  ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      if (!isAuthorized) {
                        try {
                          final authService =
                              Provider.of<AuthService>(context, listen: false);
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
                            case 'instagram':
                              await authService.signInWithInstagramBusiness();
                              break;
                            case 'youtube':
                              final result =
                                  await authService.signInWithGoogle();
                              if (result != null) {
                                await _saveYouTubeTokenDirectly(
                                    context, authService);
                              }
                              break;
                          }
                          onPlatformToggle?.call(platform);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Failed to authenticate with ${SocialPlatforms.getDisplayName(platform)}: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } else {
                        onPlatformToggle?.call(platform);
                      }
                    },
                    borderRadius: BorderRadius.circular(maxHeight / 2),
                    child: Container(
                      width: maxHeight * 0.8,
                      height: maxHeight * 0.8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected && isAuthorized
                            ? color.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.1),
                        border: Border.all(
                          color: isSelected && isAuthorized
                              ? color
                              : (isAuthorized
                                  ? color.withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.3)),
                          width: isSelected && isAuthorized ? 2.0 : 1.5,
                        ),
                        boxShadow: isSelected && isAuthorized
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
                            color: isAuthorized
                                ? (isSelected
                                    ? color
                                    : color.withValues(alpha: 0.8))
                                : Colors.white.withValues(alpha: 0.8),
                            size: maxHeight * 0.35,
                          ),
                          if (showLabels) ...[
                            const SizedBox(height: 2),
                            Text(
                              _getPlatformLabel(platform),
                              style: TextStyle(
                                color: isAuthorized
                                    ? (isSelected
                                        ? color
                                        : color.withValues(alpha: 0.7))
                                    : Colors.white.withValues(alpha: 0.7),
                                fontSize: AppTypography.small,
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
      },
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

  // Helper method to save YouTube token directly
  Future<void> _saveYouTubeTokenDirectly(
      BuildContext context, AuthService authService) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Get Google user info
      final googleUser = await GoogleSignIn().signInSilently();
      if (googleUser != null) {
        final googleAuth = await googleUser.authentication;

        // Save YouTube token using Google credentials
        await firestore
            .collection('users')
            .doc(authService.currentUser!.uid)
            .collection('tokens')
            .doc('youtube')
            .set({
          'access_token': googleAuth.accessToken,
          'id_token': googleAuth.idToken,
          'user_id': googleUser.id,
          'email': googleUser.email,
          'display_name': googleUser.displayName,
          'platform': 'youtube',
          'created_at': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      throw Exception('Failed to save YouTube token: $e');
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
          SizedBox(
            width: 40,
            child: slot1 ?? const SizedBox.shrink(),
          ),
          Expanded(
            child: slot2to5 ?? const SizedBox.shrink(),
          ),
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
        maxHeight: 52,
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
                fontSize: AppTypography.large,
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
  final List<String>? incompatiblePlatforms;

  const SevenIconHeader({
    super.key,
    required this.selectedPlatforms,
    this.onPlatformToggle,
    this.leftAction,
    this.rightAction,
    this.height = 54,
    this.enableInteraction = true,
    this.incompatiblePlatforms,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: _buildEquallySpacedActionIcon(
                leftAction,
                height * 0.8,
              ),
            ),
          ),
          ...SocialPlatforms.all.map((platform) {
            final isSelected = selectedPlatforms.contains(platform);
            final isIncompatible =
                incompatiblePlatforms?.contains(platform) ?? false;
            final color = SocialPlatforms.getColor(platform);
            final icon = SocialPlatforms.getIcon(platform);

            return Expanded(
              child: Center(
                child: _buildEvenlySpacedSocialIcon(
                  context,
                  platform,
                  icon,
                  color,
                  isSelected,
                  isIncompatible,
                  height * 0.8,
                ),
              ),
            );
          }).toList(),
          Expanded(
            child: Center(
              child: _buildEquallySpacedActionIcon(
                rightAction,
                height * 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEquallySpacedActionIcon(Widget? actionWidget, double size) {
    if (actionWidget == null) {
      return const SizedBox.shrink();
    }

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
              child: actionWidget.icon != null
                  ? Icon(
                      (actionWidget.icon as Icon).icon,
                      color: Colors.white.withValues(alpha: 0.8),
                      size: size * 0.35,
                    )
                  : actionWidget.icon,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: actionWidget,
    );
  }

  Widget _buildEvenlySpacedSocialIcon(
    BuildContext context,
    String platform,
    IconData icon,
    Color color,
    bool isSelected,
    bool isIncompatible,
    double size,
  ) {
    return FutureBuilder<bool>(
      future: Provider.of<AuthService>(context, listen: false)
          .isPlatformConnected(platform),
      builder: (context, snapshot) {
        final isAuthorized = snapshot.data ?? false;
        return Stack(
          alignment: Alignment.center,
          children: [
            if (isSelected && isAuthorized)
              SocialIconRipple(
                color: color,
                size: size,
                rippleCount: 3,
                isActive: isSelected,
              ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  if (!isAuthorized) {
                    try {
                      final authService =
                          Provider.of<AuthService>(context, listen: false);
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
                        case 'instagram':
                          await authService
                              .signInWithInstagramBusiness(context);
                          break;
                        case 'youtube':
                          final result = await authService.signInWithGoogle();
                          if (result != null) {
                            await _saveYouTubeTokenDirectly(
                                context, authService);
                          }
                          break;
                      }
                      onPlatformToggle?.call(platform);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Failed to authenticate with ${SocialPlatforms.getDisplayName(platform)}: ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } else {
                    onPlatformToggle?.call(platform);
                  }
                },
                borderRadius: BorderRadius.circular(size / 2),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected && isAuthorized
                        ? color.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.1),
                    border: Border.all(
                      color: isSelected && isAuthorized
                          ? color
                          : (isAuthorized
                              ? color.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.3)),
                      width: isSelected && isAuthorized ? 2.0 : 1.5,
                    ),
                    boxShadow: isSelected && isAuthorized
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
                    color: isAuthorized
                        ? (isSelected ? color : color.withValues(alpha: 0.8))
                        : Colors.white.withValues(alpha: 0.8),
                    size: size * 0.5,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Helper method to save YouTube token directly
  Future<void> _saveYouTubeTokenDirectly(
      BuildContext context, AuthService authService) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Get Google user info
      final googleUser = await GoogleSignIn().signInSilently();
      if (googleUser != null) {
        final googleAuth = await googleUser.authentication;

        // Save YouTube token using Google credentials
        await firestore
            .collection('users')
            .doc(authService.currentUser!.uid)
            .collection('tokens')
            .doc('youtube')
            .set({
          'access_token': googleAuth.accessToken,
          'id_token': googleAuth.idToken,
          'user_id': googleUser.id,
          'email': googleUser.email,
          'display_name': googleUser.displayName,
          'platform': 'youtube',
          'created_at': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      throw Exception('Failed to save YouTube token: $e');
    }
  }
}
