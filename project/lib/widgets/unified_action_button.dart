import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/social_action_post_coordinator.dart';
import 'voice_responsive_ripple.dart';

class UnifiedActionButton extends StatelessWidget {
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;
  final VoidCallback? onConfirmPost;
  final VoidCallback? onAddMedia;

  const UnifiedActionButton({
    super.key,
    this.onRecordStart,
    this.onRecordStop,
    this.onConfirmPost,
    this.onAddMedia,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SocialActionPostCoordinator>(
      builder: (context, coordinator, child) {
        final buttonColor = _getButtonColor(coordinator);

        return Stack(
          alignment: Alignment.center,
          children: [
            // Ripple animation layer
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

                if (coordinator.needsMediaSelection) {
                  onAddMedia?.call();
                } else if (coordinator.isReadyForExecution) {
                  onConfirmPost?.call();
                } else if (!coordinator.isRecording) {
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
                      ? buttonColor.withValues(
                          alpha: 0.5) // Dimmed when processing
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
                    _getButtonIcon(coordinator),
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Color _getButtonColor(SocialActionPostCoordinator coordinator) {
    if (coordinator.isProcessing) return Colors.orange;
    if (coordinator.isRecording) return const Color(0xFFFF0080);
    if (coordinator.needsMediaSelection) return Colors.blue;
    if (coordinator.isReadyForExecution) return const Color(0xFFFF0080);
    return const Color(0xFFFF0080);
  }

  IconData _getButtonIcon(SocialActionPostCoordinator coordinator) {
    if (coordinator.isProcessing) return Icons.hourglass_empty;
    if (coordinator.isRecording) return Icons.stop;
    if (coordinator.needsMediaSelection) return Icons.photo_library;
    if (coordinator.isReadyForExecution) return Icons.send;
    return Icons.mic;
  }
}
