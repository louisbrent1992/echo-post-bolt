import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/social_action_post_coordinator.dart';
import 'voice_responsive_ripple.dart';

/// Triple Action Button System - A three-button layout that replaces the single Unified Action Button
///
/// This widget distributes the functionality of the original Unified Action Button across three buttons:
/// - Center: Recording functionality (always visible)
/// - Right: Media selection and confirmation (animated visibility)
/// - Left: Save to Firestore (animated visibility)
///
/// All state logic remains in SocialActionPostCoordinator - this is purely a UI redistribution.
class TripleActionButtonSystem extends StatelessWidget {
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;
  final VoidCallback? onConfirmPost;
  final VoidCallback? onAddMedia;
  final VoidCallback? onSavePost;
  final AnimationController leftButtonController;
  final AnimationController rightButtonController;

  const TripleActionButtonSystem({
    super.key,
    this.onRecordStart,
    this.onRecordStop,
    this.onConfirmPost,
    this.onAddMedia,
    this.onSavePost,
    required this.leftButtonController,
    required this.rightButtonController,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SocialActionPostCoordinator>(
      builder: (context, coordinator, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Left Save Button (animated visibility) - Fixed width container
            SizedBox(
              width: 72, // Fixed width to prevent shifting
              height: 72,
              child: AnimatedBuilder(
                animation: leftButtonController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: leftButtonController.value,
                    child: Opacity(
                      opacity: leftButtonController.value,
                      child: _LeftSaveButton(
                        coordinator: coordinator,
                        onSavePost: onSavePost,
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(width: 20),

            // Center Recording Button (always visible)
            _CenterRecordButton(
              coordinator: coordinator,
              onRecordStart: onRecordStart,
              onRecordStop: onRecordStop,
            ),

            const SizedBox(width: 20),

            // Right Action Button (animated visibility) - Fixed width container
            SizedBox(
              width: 72, // Fixed width to prevent shifting
              height: 72,
              child: AnimatedBuilder(
                animation: rightButtonController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: rightButtonController.value,
                    child: Opacity(
                      opacity: rightButtonController.value,
                      child: _RightActionButton(
                        coordinator: coordinator,
                        onConfirmPost: onConfirmPost,
                        onAddMedia: onAddMedia,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Center Recording Button - Handles recording states (always visible)
class _CenterRecordButton extends StatelessWidget {
  final SocialActionPostCoordinator coordinator;
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;

  const _CenterRecordButton({
    required this.coordinator,
    this.onRecordStart,
    this.onRecordStop,
  });

  @override
  Widget build(BuildContext context) {
    final buttonColor = _getButtonColor();

    return Stack(
      alignment: Alignment.center,
      children: [
        // Ripple animation layer (only when recording)
        if (coordinator.isRecording)
          VoiceResponsiveRipple(
            color: buttonColor,
            size: 96,
            amplitude: coordinator.normalizedAmplitude,
            rippleCount: 3,
          ),

        // Main button
        GestureDetector(
          onTapDown: (_) {
            if (coordinator.isProcessing) return;
            if (!coordinator.isRecording) {
              onRecordStart?.call();
            }
          },
          onTapUp: (_) {
            if (coordinator.isRecording) {
              onRecordStop?.call();
            }
          },
          onTapCancel: () {
            if (coordinator.isRecording) {
              onRecordStop?.call();
            }
          },
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: coordinator.isProcessing
                  ? buttonColor.withValues(alpha: 0.5)
                  : buttonColor,
              boxShadow: [
                BoxShadow(
                  color: buttonColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: Icon(
                _getButtonIcon(),
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _getButtonColor() {
    if (coordinator.isProcessing) return Colors.orange;
    if (coordinator.isRecording) return const Color(0xFFFF0055);
    return const Color(0xFFFF0055); // Always pink when ready
  }

  IconData _getButtonIcon() {
    if (coordinator.isProcessing) return Icons.hourglass_empty;
    if (coordinator.isRecording) return Icons.stop;
    return Icons.mic; // Always microphone when ready
  }
}

/// Right Action Button - Handles media selection and confirmation (animated visibility)
class _RightActionButton extends StatelessWidget {
  final SocialActionPostCoordinator coordinator;
  final VoidCallback? onConfirmPost;
  final VoidCallback? onAddMedia;

  const _RightActionButton({
    required this.coordinator,
    this.onConfirmPost,
    this.onAddMedia,
  });

  @override
  Widget build(BuildContext context) {
    // Only show if needed
    if (!coordinator.needsMediaSelection && !coordinator.isReadyForExecution) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () {
        if (coordinator.isProcessing) return;

        if (coordinator.needsMediaSelection) {
          onAddMedia?.call();
        } else if (coordinator.isReadyForExecution) {
          onConfirmPost?.call();
        }
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFF0055)
              .withValues(alpha: 0.1), // Translucent pink
          border: Border.all(
            color:
                const Color(0xFFFF0055).withValues(alpha: 0.3), // Pink border
            width: 2.0,
          ),
        ),
        child: Center(
          child: Icon(
            _getButtonIcon(),
            color: const Color(0xFFFF0055), // Pink icon
            size: 24,
          ),
        ),
      ),
    );
  }

  IconData _getButtonIcon() {
    if (coordinator.needsMediaSelection) return Icons.photo_library;
    if (coordinator.isReadyForExecution) return Icons.send;
    return Icons.circle;
  }
}

/// Left Save Button - Handles saving to Firestore (animated visibility)
class _LeftSaveButton extends StatelessWidget {
  final SocialActionPostCoordinator coordinator;
  final VoidCallback? onSavePost;

  const _LeftSaveButton({
    required this.coordinator,
    this.onSavePost,
  });

  @override
  Widget build(BuildContext context) {
    // Only show if there's content to save
    if (!_canSavePost()) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () {
        if (coordinator.isProcessing) return;
        onSavePost?.call();
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFF0055)
              .withValues(alpha: 0.1), // Translucent pink
          border: Border.all(
            color:
                const Color(0xFFFF0055).withValues(alpha: 0.3), // Pink border
            width: 2.0,
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.save,
            color: Color(0xFFFF0055), // Pink icon
            size: 24,
          ),
        ),
      ),
    );
  }

  bool _canSavePost() {
    return coordinator.hasContent || coordinator.hasMedia;
  }
}
