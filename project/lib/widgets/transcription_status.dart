import 'package:flutter/material.dart';

class TranscriptionStatus extends StatelessWidget {
  final String transcription;
  final bool isProcessing;
  final bool isRecording;
  final int recordingDuration;
  final int maxRecordingDuration;

  const TranscriptionStatus({
    super.key,
    required this.transcription,
    this.isProcessing = false,
    this.isRecording = false,
    this.recordingDuration = 0,
    this.maxRecordingDuration = 30,
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
              ] else if (transcription.isNotEmpty) ...[
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFFFFD700),
                  size: 12,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _getStatusText(),
                  style: TextStyle(
                    color: isRecording
                        ? const Color(0xFFFF0080)
                        : const Color(0xFFFFD700),
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

  String _getStatusText() {
    if (isRecording) {
      return 'Recording your voice command...';
    } else if (isProcessing) {
      return 'Processing your voice command...';
    } else if (transcription.isNotEmpty) {
      return 'What you said:';
    } else {
      return 'Tap and hold the mic to start recording';
    }
  }
}
