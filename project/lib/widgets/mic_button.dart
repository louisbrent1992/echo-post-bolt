import 'package:flutter/material.dart';
import 'ripple_circle.dart';

enum RecordingState {
  idle,
  recording,
  processing,
  ready,
}

class MicButton extends StatefulWidget {
  final RecordingState state;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordStop;

  const MicButton({
    super.key,
    required this.state,
    required this.onRecordStart,
    required this.onRecordStop,
  });

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutQuad,
    ));

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.state == RecordingState.recording &&
        oldWidget.state != RecordingState.recording) {
      _scaleController.forward();
      _pulseController.repeat(reverse: true);
    } else if (widget.state != RecordingState.recording &&
        oldWidget.state == RecordingState.recording) {
      _scaleController.reverse();
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _pulseController.dispose();
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
      return [
        BoxShadow(
          color: const Color(0xFFFF0080).withValues(alpha: 0.6),
          blurRadius: 20,
          spreadRadius: 4,
        ),
        BoxShadow(
          color: const Color(0xFFFF0080).withValues(alpha: 0.3),
          blurRadius: 40,
          spreadRadius: 8,
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

  @override
  Widget build(BuildContext context) {
    final bool isRecording = widget.state == RecordingState.recording;
    final bool isProcessing = widget.state == RecordingState.processing;

    return SizedBox(
      width: 140, // Fixed container size to contain ripples
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none, // Allow ripple to extend but stay contained
        children: [
          // Multi-ripple effect when recording (positioned behind)
          if (isRecording)
            Positioned.fill(
              child: MultiRippleCircle(
                color: const Color(0xFFFF0080),
                size: 60, // Reduced size to fit within container
                rippleCount: 3,
                duration: const Duration(milliseconds: 1500),
              ),
            ),

          // Main button (fixed position) with tap detection
          GestureDetector(
            onTapDown: widget.state == RecordingState.idle
                ? (_) => widget.onRecordStart()
                : null,
            onTapUp: isRecording ? (_) => widget.onRecordStop() : null,
            onTapCancel: isRecording ? () => widget.onRecordStop() : null,
            child: AnimatedBuilder(
              animation: Listenable.merge([_scaleAnimation, _pulseAnimation]),
              builder: (context, child) {
                double scale = _scaleAnimation.value;
                if (isRecording) {
                  scale *= _pulseAnimation.value;
                }

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
                        : Icon(
                            _getIcon(),
                            color: Colors.white,
                            size: 36,
                          ),
                  ),
                );
              },
            ),
          ),

          // Outer glow ring for recording state (fixed position)
          if (isRecording)
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFF0080).withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
