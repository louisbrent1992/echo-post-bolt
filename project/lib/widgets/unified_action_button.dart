import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'ripple_circle.dart';
import '../constants/typography.dart';

enum UnifiedButtonState {
  // Recording states
  idle,
  recording,
  processing,

  // Navigation states
  reviewPost,
  confirmPost,
  addMedia,
}

class UnifiedActionButton extends StatefulWidget {
  final UnifiedButtonState state;
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;
  final VoidCallback? onReviewPost;
  final VoidCallback? onConfirmPost;
  final VoidCallback? onAddMedia;
  final double amplitude; // Voice amplitude for responsive animation
  final String? customLabel; // Optional custom label for navigation states

  const UnifiedActionButton({
    super.key,
    required this.state,
    this.onRecordStart,
    this.onRecordStop,
    this.onReviewPost,
    this.onConfirmPost,
    this.onAddMedia,
    this.amplitude = 0.0,
    this.customLabel,
  });

  @override
  State<UnifiedActionButton> createState() => _UnifiedActionButtonState();
}

class _UnifiedActionButtonState extends State<UnifiedActionButton>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _glowController;
  late AnimationController _transitionController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _transitionAnimation;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _transitionController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutQuad),
    );

    _glowAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _transitionAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _transitionController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(UnifiedActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle state transitions
    if (widget.state != oldWidget.state) {
      _handleStateTransition(oldWidget.state, widget.state);
    }

    // Handle recording-specific animations
    if (widget.state == UnifiedButtonState.recording &&
        oldWidget.state != UnifiedButtonState.recording) {
      _scaleController.forward();
      _glowController.repeat(reverse: true);
    } else if (widget.state != UnifiedButtonState.recording &&
        oldWidget.state == UnifiedButtonState.recording) {
      _scaleController.reverse();
      _glowController.stop();
      _glowController.reset();
    }
  }

  void _handleStateTransition(
      UnifiedButtonState oldState, UnifiedButtonState newState) {
    // Animate state transitions for visual continuity
    if (_isRecordingState(oldState) != _isRecordingState(newState)) {
      _transitionController.forward().then((_) {
        if (mounted) {
          _transitionController.reverse();
        }
      });
    }
  }

  bool _isRecordingState(UnifiedButtonState state) {
    return state == UnifiedButtonState.idle ||
        state == UnifiedButtonState.recording ||
        state == UnifiedButtonState.processing;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _glowController.dispose();
    _transitionController.dispose();
    super.dispose();
  }

  Color _getButtonColor() {
    switch (widget.state) {
      case UnifiedButtonState.idle:
        return const Color(0xFFFF0080);
      case UnifiedButtonState.recording:
        return const Color(0xFFFF0080);
      case UnifiedButtonState.processing:
        return const Color(0xFFFFD700);
      case UnifiedButtonState.reviewPost:
      case UnifiedButtonState.confirmPost:
        return const Color(0xFFFF0080);
      case UnifiedButtonState.addMedia:
        return const Color(0xFF4CAF50);
    }
  }

  IconData _getIcon() {
    switch (widget.state) {
      case UnifiedButtonState.idle:
        return Icons.mic;
      case UnifiedButtonState.recording:
        return Icons.mic;
      case UnifiedButtonState.processing:
        return Icons.hourglass_empty;
      case UnifiedButtonState.reviewPost:
        return Icons.arrow_forward;
      case UnifiedButtonState.confirmPost:
        return Icons.send;
      case UnifiedButtonState.addMedia:
        return Icons.photo_library;
    }
  }

  String _getLabel() {
    if (widget.customLabel != null) {
      return widget.customLabel!;
    }

    switch (widget.state) {
      case UnifiedButtonState.idle:
        return 'Hold to Record';
      case UnifiedButtonState.recording:
        return 'Recording...';
      case UnifiedButtonState.processing:
        return 'Processing...';
      case UnifiedButtonState.reviewPost:
        return 'Review Post';
      case UnifiedButtonState.confirmPost:
        return 'Confirm Post';
      case UnifiedButtonState.addMedia:
        return 'Add Media';
    }
  }

  List<BoxShadow> _getShadows() {
    if (widget.state == UnifiedButtonState.recording) {
      // During recording, glow intensity based on voice amplitude
      final intensity = (widget.amplitude * 0.8 + 0.2).clamp(0.2, 1.0);
      return [
        BoxShadow(
          color: const Color(0xFFFF0080).withValues(alpha: 0.6 * intensity),
          blurRadius: 20 * intensity,
          spreadRadius: 4 * intensity,
        ),
        BoxShadow(
          color: const Color(0xFFFF0080).withValues(alpha: 0.3 * intensity),
          blurRadius: 40 * intensity,
          spreadRadius: 8 * intensity,
        ),
      ];
    }
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.3),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ];
  }

  bool get _shouldShowRipples {
    // Only show ripples when recording AND user is speaking
    return widget.state == UnifiedButtonState.recording &&
        widget.amplitude > 0.1;
  }

  VoidCallback? _getOnTapCallback() {
    switch (widget.state) {
      case UnifiedButtonState.idle:
        return widget.onRecordStart;
      case UnifiedButtonState.reviewPost:
        return widget.onReviewPost;
      case UnifiedButtonState.confirmPost:
        return widget.onConfirmPost;
      case UnifiedButtonState.addMedia:
        return widget.onAddMedia;
      case UnifiedButtonState.recording:
      case UnifiedButtonState.processing:
        return null; // No tap action during these states
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isRecording = widget.state == UnifiedButtonState.recording;
    final bool isProcessing = widget.state == UnifiedButtonState.processing;
    final bool isNavigationState = !_isRecordingState(widget.state);

    return GestureDetector(
      onTapDown: widget.state == UnifiedButtonState.idle
          ? (_) {
              if (kDebugMode) {
                print('UnifiedActionButton: onTapDown - starting recording');
              }
              widget.onRecordStart?.call();
            }
          : null,
      onTapUp: isRecording
          ? (_) {
              if (kDebugMode) {
                print('UnifiedActionButton: onTapUp - stopping recording');
              }
              widget.onRecordStop?.call();
            }
          : null,
      onTapCancel: isRecording
          ? () {
              if (kDebugMode) {
                print('UnifiedActionButton: onTapCancel - stopping recording');
              }
              widget.onRecordStop?.call();
            }
          : null,
      onTap: isNavigationState ? _getOnTapCallback() : null,
      child: SizedBox(
        // Constrain all states to the same overall size
        width: 120,
        height: 120,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Voice-responsive ripple effect (only when speaking) - constrained to fit
            if (_shouldShowRipples)
              Positioned.fill(
                child: VoiceResponsiveRipple(
                  color: const Color(0xFFFF0080),
                  size: 50, // Reduced from 60 to fit within 120px bounds
                  amplitude: widget.amplitude,
                  rippleCount: 3,
                ),
              ),

            // Main button with voice-responsive glow - constrained scaling
            AnimatedBuilder(
              animation: Listenable.merge(
                  [_scaleAnimation, _glowAnimation, _transitionAnimation]),
              builder: (context, child) {
                double scale = _scaleAnimation.value;
                if (isRecording) {
                  // Reduced amplitude effect to maintain consistent bounds
                  final voicePulse =
                      1.0 + (widget.amplitude * 0.05); // Reduced from 0.1
                  scale *= _glowAnimation.value * voicePulse;
                }

                // Add transition scaling for state changes
                if (_transitionAnimation.value > 0) {
                  scale *= (1.0 + _transitionAnimation.value * 0.1);
                }

                // Ensure scale never exceeds bounds that would break the 120px container
                scale = scale.clamp(0.8, 1.2);

                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _getButtonColor(),
                      boxShadow: _getShadows(),
                    ),
                    child: isProcessing
                        ? const Center(
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            ),
                          )
                        : Icon(_getIcon(), color: Colors.white, size: 36),
                  ),
                );
              },
            ),

            // Voice level indicator ring (only when recording) - constrained size
            if (isRecording)
              VoiceLevelRing(
                amplitude: widget.amplitude,
                baseSize: 90, // Reduced from 100 to fit within 120px bounds
                color: const Color(0xFFFF0080),
              ),

            // Label for navigation states (positioned below button)
            if (isNavigationState)
              Positioned(
                bottom: -10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppTypography.small,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
