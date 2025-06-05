import 'package:flutter/material.dart';

class RippleCircle extends StatefulWidget {
  final Color color;
  final double size;
  final double strokeWidth;
  final Duration duration;

  const RippleCircle({
    Key? key,
    this.color = const Color(0xFFFF0080),
    this.size = 80.0,
    this.strokeWidth = 2.0,
    this.duration = const Duration(milliseconds: 1000),
  }) : super(key: key);

  @override
  State<RippleCircle> createState() => _RippleCircleState();
}

class _RippleCircleState extends State<RippleCircle>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _radiusAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _radiusAnimation = Tween<double>(
      begin: widget.size * 0.5,
      end: widget.size * 1.2,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuad,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.8,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuad,
    ));

    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size * 2.4, widget.size * 2.4),
          painter: RipplePainter(
            radius: _radiusAnimation.value,
            opacity: _opacityAnimation.value,
            color: widget.color,
            strokeWidth: widget.strokeWidth,
          ),
        );
      },
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
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Create gradient effect
    final gradient = RadialGradient(
      colors: [
        color.withOpacity(opacity),
        color.withOpacity(opacity * 0.5),
        color.withOpacity(0),
      ],
      stops: const [0.0, 0.7, 1.0],
    );

    final gradientPaint = Paint()
      ..shader =
          gradient.createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2;

    // Draw multiple rings for more dramatic effect
    canvas.drawCircle(center, radius, gradientPaint);
    canvas.drawCircle(center, radius * 0.8, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class MultiRippleCircle extends StatefulWidget {
  final Color color;
  final double size;
  final int rippleCount;
  final Duration duration;

  const MultiRippleCircle({
    Key? key,
    this.color = const Color(0xFFFF0080),
    this.size = 80.0,
    this.rippleCount = 3,
    this.duration = const Duration(milliseconds: 1500),
  }) : super(key: key);

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
