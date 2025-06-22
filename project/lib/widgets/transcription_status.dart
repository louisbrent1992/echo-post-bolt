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

        return Text(
          message,
          style: TextStyle(
            color: color,
            fontSize: AppTypography.small,
            fontWeight: isRecording ? FontWeight.bold : FontWeight.normal,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
