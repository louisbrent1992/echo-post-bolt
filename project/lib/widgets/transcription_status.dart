import 'package:flutter/material.dart';

enum TranscriptionContext {
  recording,
  processing,
  completed,
  reviewReady,
  confirmReady,
  addMediaReady,
}

class TranscriptionStatus extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.85,
      constraints: const BoxConstraints(
        minHeight: 60,
        maxHeight: 120,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status indicator
          Row(
            children: [
              if (isRecording) ...[
                // Recording indicator with pulsing animation
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF0080),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (isProcessing) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFFFD700),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (transcription.isNotEmpty ||
                  this.context == TranscriptionContext.reviewReady ||
                  this.context == TranscriptionContext.confirmReady ||
                  this.context == TranscriptionContext.addMediaReady) ...[
                Icon(
                  _getContextIcon(),
                  color: _getContextColor(),
                  size: 12,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _getStatusText(),
                  style: TextStyle(
                    color: _getTextColor(),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Recording timer on the right side
              if (isRecording) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF0080).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFF0080),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${maxRecordingDuration - recordingDuration}s',
                    style: const TextStyle(
                      color: Color(0xFFFF0080),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (transcription.isNotEmpty) ...[
            const SizedBox(height: 8),
            Flexible(
              child: Text(
                transcription,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.3,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getContextIcon() {
    switch (context) {
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

  Color _getContextColor() {
    switch (context) {
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

  Color _getTextColor() {
    if (isRecording) {
      return const Color(0xFFFF0080);
    } else if (isProcessing) {
      return const Color(0xFFFFD700);
    } else {
      return _getContextColor();
    }
  }

  String _getStatusText() {
    // Use custom message if provided
    if (customMessage != null && customMessage!.isNotEmpty) {
      return customMessage!;
    }

    // Default messages based on state and context
    if (isRecording) {
      return 'Recording your voice command...';
    } else if (isProcessing) {
      return 'Processing your voice command...';
    } else if (transcription.isNotEmpty) {
      switch (context) {
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
      switch (context) {
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
}
