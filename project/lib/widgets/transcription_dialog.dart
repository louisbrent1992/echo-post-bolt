import 'package:flutter/material.dart';

class TranscriptionDialog extends StatelessWidget {
  final String transcription;
  final bool isJsonReady;
  final bool hasMedia;
  final VoidCallback? onReviewMedia;
  final VoidCallback? onPostNow;

  const TranscriptionDialog({
    Key? key,
    required this.transcription,
    required this.isJsonReady,
    required this.hasMedia,
    this.onReviewMedia,
    this.onPostNow,
  }) : super(key: key);

  String _getStatusMessage() {
    if (transcription.isEmpty) {
      return 'Tap and hold the mic to start recording...';
    } else if (isJsonReady && hasMedia) {
      return 'Ready to review and post! ✨';
    } else if (isJsonReady) {
      return 'JSON created - ready to add media';
    } else {
      return 'Processing your voice command...';
    }
  }

  Color _getStatusColor() {
    if (transcription.isEmpty) {
      return const Color(0xFFEEEEEE);
    } else if (isJsonReady) {
      return const Color(0xFFFF0080);
    } else {
      return const Color(0xFFFFD700);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: screenWidth * 0.85,
      constraints: const BoxConstraints(
        maxHeight: 400,
        minHeight: 150,
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: isJsonReady && transcription.isNotEmpty
            ? Border.all(
                color: const Color(0xFFFFD700),
                width: 2,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status message
          Center(
            child: Text(
              _getStatusMessage(),
              style: TextStyle(
                color: _getStatusColor(),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          if (transcription.isNotEmpty) ...[
            const SizedBox(height: 16),

            // Transcription text
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  transcription,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),

            if (isJsonReady) ...[
              const SizedBox(height: 20),

              // Action buttons
              Row(
                children: [
                  if (!hasMedia)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onReviewMedia,
                        icon: const Icon(
                          Icons.photo_library,
                          size: 18,
                          color: Color(0xFFFF0080),
                        ),
                        label: const Text(
                          'Add Media',
                          style: TextStyle(
                            color: Color(0xFFFF0080),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Color(0xFFFF0080),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  if (!hasMedia) const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onPostNow,
                      icon: const Icon(
                        Icons.send,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: Text(
                        hasMedia ? 'Review Post' : 'Post Now',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF0080),
                        elevation: 4,
                        shadowColor:
                            const Color(0xFFFF0080).withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class PulsingContainer extends StatefulWidget {
  final Widget child;
  final bool shouldPulse;

  const PulsingContainer({
    Key? key,
    required this.child,
    this.shouldPulse = false,
  }) : super(key: key);

  @override
  State<PulsingContainer> createState() => _PulsingContainerState();
}

class _PulsingContainerState extends State<PulsingContainer>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    if (widget.shouldPulse) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PulsingContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldPulse && !oldWidget.shouldPulse) {
      _controller.repeat(reverse: true);
    } else if (!widget.shouldPulse && oldWidget.shouldPulse) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.shouldPulse) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: widget.child,
        );
      },
    );
  }
}
