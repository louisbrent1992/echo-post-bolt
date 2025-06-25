import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/typography.dart';
import '../services/social_action_post_coordinator.dart';

class TranscriptionStatus extends StatelessWidget {
  const TranscriptionStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SocialActionPostCoordinator>(
      builder: (context, coordinator, child) {
        final message = coordinator.getStatusMessage();
        final color = coordinator.getStatusColor();
        final isRecording = coordinator.isRecording;

        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message,
            style: TextStyle(
              color: color,
              fontSize: AppTypography.small,
              fontWeight: isRecording ? FontWeight.bold : FontWeight.normal,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
