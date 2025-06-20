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
      child: Row(
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
              scheduleText,
              style: const TextStyle(
                color: Color(0xFFFF0080),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // Edit button
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
                  color: const Color(0xFFFF0080).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFF0080),
                    width: 1,
                  ),
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
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final formatter = DateFormat('MMM d, yyyy \'at\' h:mm a');
    return formatter.format(dateTime);
  }
}
