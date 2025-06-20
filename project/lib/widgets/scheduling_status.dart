import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants/typography.dart';

class SchedulingStatus extends StatelessWidget {
  final String schedule;
  final VoidCallback? onEditSchedule;

  const SchedulingStatus({
    super.key,
    required this.schedule,
    this.onEditSchedule,
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
              Icon(
                isNow ? Icons.send : Icons.schedule,
                color: const Color(0xFFFF0080),
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'Schedule',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: AppTypography.small, // Small font for label
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (onEditSchedule != null)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onEditSchedule,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.edit,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 16,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Schedule content
          Flexible(
            child: Text(
              scheduleText,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: AppTypography.body, // Body font for main content
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final formatter = DateFormat('MMM d, yyyy \'at\' h:mm a');
    return formatter.format(dateTime);
  }
}
