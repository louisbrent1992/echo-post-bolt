import 'package:flutter/material.dart';

class TranscriptionStatus extends StatelessWidget {
  final String transcription;
  final bool isProcessing;

  const TranscriptionStatus({
    super.key,
    required this.transcription,
    this.isProcessing = false,
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
              if (isProcessing) ...[
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
              Text(
                _getStatusText(),
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
    if (isProcessing) {
      return 'Processing your voice command...';
    } else if (transcription.isNotEmpty) {
      return 'What you said:';
    } else {
      return 'Tap and hold the mic to start recording';
    }
  }
}
