import 'package:flutter/material.dart';
import '../constants/typography.dart';

enum TranscriptionContext {
  recording,
  processing,
  completed,
  reviewReady,
  confirmReady,
  addMediaReady,
}

class TranscriptionStatus extends StatefulWidget {
  final String transcription;
  final bool isProcessing;
  final bool isRecording;
  final int recordingDuration;
  final int maxRecordingDuration;
  final TranscriptionContext context;
  final String? customMessage;

  const TranscriptionStatus({
    super.key,
    required this.transcription,
    this.isProcessing = false,
    this.isRecording = false,
    this.recordingDuration = 0,
    this.maxRecordingDuration = 30,
    this.context = TranscriptionContext.recording,
    this.customMessage,
  });

  @override
  State<TranscriptionStatus> createState() => _TranscriptionStatusState();
}

class _TranscriptionStatusState extends State<TranscriptionStatus>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    if (widget.isRecording || widget.isProcessing) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(TranscriptionStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.isRecording || widget.isProcessing) &&
        !(oldWidget.isRecording || oldWidget.isProcessing)) {
      _pulseController.repeat(reverse: true);
    } else if (!(widget.isRecording || widget.isProcessing) &&
        (oldWidget.isRecording || oldWidget.isProcessing)) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      constraints: const BoxConstraints(
        minHeight: 106,
        maxHeight: 166,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(0),
          topRight: Radius.circular(0),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status indicator
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: (widget.isRecording || widget.isProcessing)
                        ? _pulseAnimation.value
                        : 1.0,
                    child: Icon(
                      _getStatusIcon(),
                      color: _getStatusColor(),
                      size: 16,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Text(
                _getStatusText(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: AppTypography.small,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (widget.isRecording) ...[
                const Spacer(),
                Text(
                  '${widget.recordingDuration}s / ${widget.maxRecordingDuration}s',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: AppTypography.small,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Content
          Flexible(
            child: Text(
              _getDisplayText(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: AppTypography.body,
                height: 1.3,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon() {
    switch (widget.context) {
      case TranscriptionContext.recording:
        return Icons.mic;
      case TranscriptionContext.processing:
        return Icons.hourglass_empty;
      case TranscriptionContext.completed:
        return Icons.check_circle;
      case TranscriptionContext.reviewReady:
        return Icons.arrow_forward;
      case TranscriptionContext.confirmReady:
        return Icons.send;
      case TranscriptionContext.addMediaReady:
        return Icons.photo_library;
    }
  }

  Color _getStatusColor() {
    switch (widget.context) {
      case TranscriptionContext.recording:
        return const Color(0xFFFF0080);
      case TranscriptionContext.processing:
        return const Color(0xFFFFD700);
      case TranscriptionContext.completed:
      case TranscriptionContext.reviewReady:
      case TranscriptionContext.confirmReady:
        return const Color(0xFFFF0080);
      case TranscriptionContext.addMediaReady:
        return const Color(0xFF4CAF50);
    }
  }

  String _getStatusText() {
    // Use custom message if provided
    if (widget.customMessage != null && widget.customMessage!.isNotEmpty) {
      return widget.customMessage!;
    }

    // Default messages based on state and context
    if (widget.isRecording) {
      return 'Recording your voice command...';
    } else if (widget.isProcessing) {
      return 'Processing your voice command...';
    } else if (widget.transcription.isNotEmpty) {
      switch (widget.context) {
        case TranscriptionContext.completed:
          return 'What you said:';
        case TranscriptionContext.reviewReady:
          return 'Ready to review your post:';
        case TranscriptionContext.confirmReady:
          return 'Ready to confirm and post:';
        case TranscriptionContext.addMediaReady:
          return 'Ready to add media:';
        default:
          return 'What you said:';
      }
    } else {
      switch (widget.context) {
        case TranscriptionContext.reviewReady:
          return 'Tap the button below to review your post';
        case TranscriptionContext.confirmReady:
          return 'Tap the button below to confirm and post';
        case TranscriptionContext.addMediaReady:
          return 'Tap the button below to add media';
        default:
          return 'Tap and hold the button below to start recording';
      }
    }
  }

  String _getDisplayText() {
    if (widget.transcription.isNotEmpty) {
      return widget.transcription;
    } else {
      return _getStatusText();
    }
  }
}
