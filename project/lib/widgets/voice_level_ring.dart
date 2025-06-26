import 'package:flutter/material.dart';

class VoiceLevelRing extends StatelessWidget {
  final double amplitude;
  final double baseSize;
  final Color color;

  const VoiceLevelRing({
    super.key,
    required this.amplitude,
    required this.baseSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: baseSize,
      height: baseSize,
      child: CustomPaint(
        painter: VoiceLevelRingPainter(
          amplitude: amplitude,
          color: color,
        ),
      ),
    );
  }
}

class VoiceLevelRingPainter extends CustomPainter {
  final double amplitude;
  final Color color;

  VoiceLevelRingPainter({
    required this.amplitude,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Calculate ring thickness based on amplitude
    final thickness = 3.0 + (amplitude * 5.0);

    // Calculate ring radius based on amplitude
    final ringRadius = radius - (amplitude * 10.0);

    final paint = Paint()
      ..color = color.withValues(alpha: 0.6 + (amplitude * 0.4))
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, ringRadius, paint);
  }

  @override
  bool shouldRepaint(VoiceLevelRingPainter oldDelegate) {
    return oldDelegate.amplitude != amplitude || oldDelegate.color != color;
  }
}
