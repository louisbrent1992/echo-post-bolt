import 'package:echo_post/widgets/voice_responsive_ripple.dart';
import 'package:echo_post/widgets/voice_level_ring.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum RecordingState { idle, recording, processing, ready }

class MicButton extends StatefulWidget {
  final RecordingState state;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordStop;
  final double amplitude; // Voice amplitude for responsive animation

  const MicButton({
    super.key,
    required this.state,
    required this.onRecordStart,
    required this.onRecordStop,
    this.amplitude = 0.0, // Default no voice
  });

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _glowController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

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

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutQuad),
    );

    _glowAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle state changes
    if (widget.state == RecordingState.recording &&
        oldWidget.state != RecordingState.recording) {
      _scaleController.forward();
      _glowController.repeat(reverse: true);
    } else if (widget.state != RecordingState.recording &&
        oldWidget.state == RecordingState.recording) {
      _scaleController.reverse();
      _glowController.stop();
      _glowController.reset();
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  Color _getButtonColor() {
    switch (widget.state) {
      case RecordingState.idle:
        return const Color(0xFFFF0080);
      case RecordingState.recording:
        return const Color(0xFFFF0080);
      case RecordingState.processing:
        return const Color(0xFFFFD700);
      case RecordingState.ready:
        return const Color(0xFFFF0080);
    }
  }

  IconData _getIcon() {
    switch (widget.state) {
      case RecordingState.idle:
        return Icons.mic;
      case RecordingState.recording:
        return Icons.mic;
      case RecordingState.processing:
        return Icons.hourglass_empty;
      case RecordingState.ready:
        return Icons.check;
    }
  }

  List<BoxShadow> _getShadows() {
    if (widget.state == RecordingState.recording) {
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
    return widget.state == RecordingState.recording && widget.amplitude > 0.1;
  }

  @override
  Widget build(BuildContext context) {
    final bool isRecording = widget.state == RecordingState.recording;
    final bool isProcessing = widget.state == RecordingState.processing;

    return GestureDetector(
      onTapDown: widget.state == RecordingState.idle
          ? (_) {
              if (kDebugMode) {
                print('MicButton: onTapDown - starting recording');
              }
              widget.onRecordStart();
            }
          : null,
      onTapUp: isRecording
          ? (_) {
              if (kDebugMode) {
                print('MicButton: onTapUp - stopping recording');
              }
              widget.onRecordStop();
            }
          : null,
      onTapCancel: isRecording
          ? () {
              if (kDebugMode) {
                print('MicButton: onTapCancel - stopping recording');
              }
              widget.onRecordStop();
            }
          : null,
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
              animation: Listenable.merge([_scaleAnimation, _glowAnimation]),
              builder: (context, child) {
                double scale = _scaleAnimation.value;
                if (isRecording) {
                  // Reduced amplitude effect to maintain consistent bounds
                  final voicePulse =
                      1.0 + (widget.amplitude * 0.05); // Reduced from 0.1
                  scale *= _glowAnimation.value * voicePulse;
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
          ],
        ),
      ),
    );
  }
}
