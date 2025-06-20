import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SchedulingStatus extends StatelessWidget {
  final String schedule;
  final VoidCallback onEditSchedule;

  const SchedulingStatus({
    super.key,
    required this.schedule,
    required this.onEditSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final isNow = schedule == 'now';
    final scheduleText = isNow
        ? 'Ready to post immediately'
        : 'Scheduled for ${_formatDateTime(DateTime.parse(schedule))}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      constraints: const BoxConstraints(
        minHeight: 60,
        maxHeight: 120,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status indicator row - mirroring TranscriptionStatus structure
          Row(
            children: [
              // Schedule icon
              Icon(
                isNow ? Icons.send : Icons.schedule,
                color: const Color(0xFFFF0080),
                size: 12,
              ),
              const SizedBox(width: 8),

              // Schedule text
              Expanded(
                child: Text(
                  isNow ? 'Ready to post immediately' : 'Scheduled post',
                  style: const TextStyle(
                    color: Color(0xFFFF0080),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // Edit button - positioned like recording timer
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onEditSchedule,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF0080).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Change',
                      style: TextStyle(
                        color: Color(0xFFFF0080),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Schedule details - mirroring transcription text area
          if (!isNow) ...[
            const SizedBox(height: 8),
            Text(
              scheduleText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final formatter = DateFormat('MMM d, yyyy \'at\' h:mm a');
    return formatter.format(dateTime);
  }
}
