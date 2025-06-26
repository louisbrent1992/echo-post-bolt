import 'package:flutter/material.dart';

class SocialIconRipple extends StatefulWidget {
  final Color color;
  final double size;
  final int rippleCount;
  final bool isActive;

  const SocialIconRipple({
    super.key,
    required this.color,
    this.size = 48.0,
    this.rippleCount = 3,
    this.isActive = true,
  });

  @override
  State<SocialIconRipple> createState() => _SocialIconRippleState();
}

class _SocialIconRippleState extends State<SocialIconRipple>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _radiusAnimations;
  late List<Animation<double>> _opacityAnimations;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    _controllers = [];
    _radiusAnimations = [];
    _opacityAnimations = [];

    for (int i = 0; i < widget.rippleCount; i++) {
      final controller = AnimationController(
        duration: Duration(
            milliseconds:
                1000 + (i * 200)), // Vary duration like VoiceResponsiveRipple
        vsync: this,
      );

      final radiusAnimation = Tween<double>(
        begin: widget.size * 0.4,
        end: widget.size *
            1.3, // Similar to VoiceResponsiveRipple but without amplitude scaling
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutQuad,
      ));

      final opacityAnimation = Tween<double>(
        begin:
            0.6, // Fixed opacity like VoiceResponsiveRipple without amplitude
        end: 0.0,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutQuad,
      ));

      _controllers.add(controller);
      _radiusAnimations.add(radiusAnimation);
      _opacityAnimations.add(opacityAnimation);

      // Stagger the animations like VoiceResponsiveRipple
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted && widget.isActive) {
          controller.repeat();
        }
      });
    }
  }

  @override
  void didUpdateWidget(SocialIconRipple oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Start/stop animations based on isActive state
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        for (int i = 0; i < _controllers.length; i++) {
          Future.delayed(Duration(milliseconds: i * 150), () {
            if (mounted) {
              _controllers[i].repeat();
            }
          });
        }
      } else {
        for (final controller in _controllers) {
          controller.stop();
          controller.reset();
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything if not active
    if (!widget.isActive) {
      return const SizedBox.shrink();
    }

    // Use similar sizing constraints as VoiceResponsiveRipple
    final maxSize = widget.size * 2.0;

    return Stack(
      alignment: Alignment.center,
      children: List.generate(widget.rippleCount, (index) {
        return AnimatedBuilder(
          animation: _controllers[index],
          builder: (context, child) {
            return CustomPaint(
              size: Size(maxSize, maxSize),
              painter: SocialRipplePainter(
                radius: _radiusAnimations[index].value,
                opacity: _opacityAnimations[index].value,
                color: widget.color,
              ),
            );
          },
        );
      }),
    );
  }
}

class SocialRipplePainter extends CustomPainter {
  final double radius;
  final double opacity;
  final Color color;

  SocialRipplePainter({
    required this.radius,
    required this.opacity,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Fixed stroke width for consistent social icon appearance
    const strokeWidth = 1.5;

    final paint = Paint()
      ..color = color.withAlpha((opacity * 255).round())
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Create gradient similar to VoiceResponsiveRipple but simpler
    final gradient = RadialGradient(
      colors: [
        color.withAlpha((opacity * 255).round()),
        color.withAlpha((opacity * 0.7 * 255).round()),
        color.withAlpha(0),
      ],
      stops: const [0.0, 0.6, 1.0],
    );

    final gradientPaint = Paint()
      ..shader =
          gradient.createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2;

    // Draw ripple rings similar to VoiceResponsiveRipple
    canvas.drawCircle(center, radius, gradientPaint);
    canvas.drawCircle(center, radius * 0.7, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
