import 'package:flutter/material.dart';

class RippleCircle extends StatefulWidget {
  final Color color;
  final double amplitude;

  const RippleCircle({
    super.key,
    required this.color,
    required this.amplitude,
  });

  @override
  State<RippleCircle> createState() => _RippleCircleState();
}

class _RippleCircleState extends State<RippleCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _animation = Tween<double>(begin: 0.5, end: 1.5).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 120 * _animation.value,
          height: 120 * _animation.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.color.withValues(alpha: 0.3 * widget.amplitude),
              width: 2,
            ),
          ),
        );
      },
    );
  }
}

class MultiRippleCircle extends StatefulWidget {
  final Color color;
  final double size;
  final int rippleCount;
  final Duration duration;

  const MultiRippleCircle({
    super.key,
    this.color = const Color(0xFFFF0080),
    this.size = 80.0,
    this.rippleCount = 3,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<MultiRippleCircle> createState() => _MultiRippleCircleState();
}

class _MultiRippleCircleState extends State<MultiRippleCircle>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _radiusAnimations;
  late List<Animation<double>> _opacityAnimations;

  @override
  void initState() {
    super.initState();

    _controllers = [];
    _radiusAnimations = [];
    _opacityAnimations = [];

    for (int i = 0; i < widget.rippleCount; i++) {
      final controller = AnimationController(
        duration: widget.duration,
        vsync: this,
      );

      final radiusAnimation = Tween<double>(
        begin: widget.size * 0.4,
        end: widget.size * 1.4,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutQuad,
      ));

      final opacityAnimation = Tween<double>(
        begin: 0.8,
        end: 0.0,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutQuad,
      ));

      _controllers.add(controller);
      _radiusAnimations.add(radiusAnimation);
      _opacityAnimations.add(opacityAnimation);

      // Stagger the animations
      Future.delayed(Duration(milliseconds: (i * 300)), () {
        if (mounted) {
          controller.repeat();
        }
      });
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
    return Stack(
      alignment: Alignment.center,
      children: List.generate(widget.rippleCount, (index) {
        return AnimatedBuilder(
          animation: _controllers[index],
          builder: (context, child) {
            return CustomPaint(
              size: Size(widget.size * 2.8, widget.size * 2.8),
              painter: RipplePainter(
                radius: _radiusAnimations[index].value,
                opacity: _opacityAnimations[index].value,
                color: widget.color,
                strokeWidth: 1.5,
              ),
            );
          },
        );
      }),
    );
  }
}

class VoiceResponsiveRipple extends StatefulWidget {
  final Color color;
  final double size;
  final double amplitude; // 0.0 to 1.0
  final int rippleCount;

  const VoiceResponsiveRipple({
    super.key,
    this.color = const Color(0xFFFF0080),
    this.size = 80.0,
    required this.amplitude,
    this.rippleCount = 3,
  });

  @override
  State<VoiceResponsiveRipple> createState() => _VoiceResponsiveRippleState();
}

class _VoiceResponsiveRippleState extends State<VoiceResponsiveRipple>
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
        duration: Duration(milliseconds: 800 + (i * 200)), // Vary duration
        vsync: this,
      );

      final radiusAnimation = Tween<double>(
        begin: widget.size * 0.4,
        end: widget.size *
            (1.2 + widget.amplitude * 0.5), // Amplitude affects size
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutQuad,
      ));

      final opacityAnimation = Tween<double>(
        begin: 0.6 +
            (widget.amplitude * 0.3), // Amplitude affects starting opacity
        end: 0.0,
      ).animate(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutQuad,
      ));

      _controllers.add(controller);
      _radiusAnimations.add(radiusAnimation);
      _opacityAnimations.add(opacityAnimation);

      // Start immediately with staggered timing
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted && widget.amplitude > 0.1) {
          controller.repeat();
        }
      });
    }
  }

  @override
  void didUpdateWidget(VoiceResponsiveRipple oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Restart animations if amplitude changes significantly
    if ((widget.amplitude > 0.1) != (oldWidget.amplitude > 0.1)) {
      if (widget.amplitude > 0.1) {
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
    // Don't show anything if amplitude is too low
    if (widget.amplitude <= 0.1) {
      return const SizedBox.shrink();
    }

    // Constrain the maximum size to respect parent bounds
    final maxSize =
        widget.size * 2.0; // Reduced from 2.8 to better fit in 120px container

    return Stack(
      alignment: Alignment.center,
      children: List.generate(widget.rippleCount, (index) {
        return AnimatedBuilder(
          animation: _controllers[index],
          builder: (context, child) {
            return CustomPaint(
              size: Size(maxSize, maxSize),
              painter: VoiceRipplePainter(
                radius: _radiusAnimations[index].value,
                opacity: _opacityAnimations[index].value,
                color: widget.color,
                amplitude: widget.amplitude,
              ),
            );
          },
        );
      }),
    );
  }
}

class VoiceRipplePainter extends CustomPainter {
  final double radius;
  final double opacity;
  final Color color;
  final double amplitude;

  VoiceRipplePainter({
    required this.radius,
    required this.opacity,
    required this.color,
    required this.amplitude,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Adjust stroke width based on amplitude
    final strokeWidth = 1.0 + (amplitude * 3.0);

    final paint = Paint()
      ..color = color.withAlpha((opacity * 255).round())
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Create amplitude-responsive gradient
    final gradient = RadialGradient(
      colors: [
        color.withAlpha(((opacity * amplitude) * 255).round()),
        color.withAlpha(((opacity * amplitude * 0.7) * 255).round()),
        color.withAlpha(0),
      ],
      stops: const [0.0, 0.6, 1.0],
    );

    final gradientPaint = Paint()
      ..shader =
          gradient.createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2;

    // Draw voice-responsive rings
    canvas.drawCircle(center, radius, gradientPaint);
    canvas.drawCircle(center, radius * 0.7, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class VoiceLevelRing extends StatelessWidget {
  final double amplitude; // 0.0 to 1.0
  final double baseSize;
  final Color color;

  const VoiceLevelRing({
    super.key,
    required this.amplitude,
    this.baseSize = 100.0,
    this.color = const Color(0xFFFF0080),
  });

  @override
  Widget build(BuildContext context) {
    // Scale ring size based on amplitude but constrain to reasonable bounds
    final ringSize = (baseSize + (amplitude * 15)).clamp(
        baseSize * 0.9, baseSize * 1.1); // Reduced scaling and added bounds
    final opacity = (amplitude * 0.6 + 0.1).clamp(0.1, 0.7);
    final strokeWidth = 1.0 + (amplitude * 2.0);

    return Container(
      width: ringSize,
      height: ringSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: opacity),
          width: strokeWidth,
        ),
      ),
    );
  }
}

class RipplePainter extends CustomPainter {
  final double radius;
  final double opacity;
  final Color color;
  final double strokeWidth;

  RipplePainter({
    required this.radius,
    required this.opacity,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color.withAlpha((opacity * 255).round())
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
