import 'package:flutter/material.dart';

enum StatusMessageType { info, warning, error, recording, processing, success }

class StatusMessage {
  final String message;
  final StatusMessageType type;
  final DateTime timestamp;

  StatusMessage({
    required this.message,
    required this.type,
  }) : timestamp = DateTime.now();

  Color getColor() {
    switch (type) {
      case StatusMessageType.error:
        return Colors.red;
      case StatusMessageType.warning:
        return Colors.orange;
      case StatusMessageType.success:
        return const Color(0xFF4CAF50);
      case StatusMessageType.recording:
        return const Color(0xFFFF0080);
      case StatusMessageType.processing:
        return Colors.orange;
      case StatusMessageType.info:
      // ignore: unreachable_switch_default
      default:
        return Colors.white.withValues(alpha: 179);
    }
  }
}
