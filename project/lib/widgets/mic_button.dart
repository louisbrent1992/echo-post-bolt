import 'package:flutter/material.dart';
import 'dart:async';

enum RecordingState {
  idle,
  recording,
  processing,
  ready,
}

class MicButton extends StatefulWidget {
  final Function() onRecordStart;
  final Function() onRecordStop;
  final RecordingState state;

  const MicButton({
    super.key,
    required this.onRecordStart,
    required this.onRecordStop,
    required this.state,
  });

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;
  
  Timer? _recordingTimer;
  int _recordingDuration = 0;
  final int _maxRecordingDuration = 10; // 10 seconds max

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  void _startRecordingTimer() {
    _recordingDuration = 0;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration++;
      });
      
      if (_recordingDuration >= _maxRecordingDuration) {
        _stopRecording();
      }
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  void _toggleRecording() {
    if (widget.state == RecordingState.idle) {
      _startRecording();
    } else if (widget.state == RecordingState.recording) {
      _stopRecording();
    }
  }

  void _startRecording() {
    widget.onRecordStart();
    _startRecordingTimer();
  }

  void _stopRecording() {
    _stopRecordingTimer();
    widget.onRecordStop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Remaining time indicator (only shown when recording)
        if (widget.state == RecordingState.recording)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              '${_maxRecordingDuration - _recordingDuration}s',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        
        // Mic button with animations
        GestureDetector(
          onTap: widget.state == RecordingState.processing || widget.state == RecordingState.ready
              ? null
              : _toggleRecording,
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Pulse animation (only when recording)
                  if (widget.state == RecordingState.recording)
                    Opacity(
                      opacity: 0.5 * (1 - _pulseAnimation.value),
                      child: Container(
                        width: 100 + (20 * _pulseAnimation.value),
                        height: 100 + (20 * _pulseAnimation.value),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.error.withOpacity(0.3),
                        ),
                      ),
                    ),
                  
                  // Main button
                  Transform.scale(
                    scale: widget.state == RecordingState.recording
                        ? _scaleAnimation.value
                        : 1.0,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getButtonColor(),
                        boxShadow: [
                          BoxShadow(
                            color: _getButtonColor().withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: _buildButtonContent(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        
        // Status text
        const SizedBox(height: 16),
        Text(
          _getStatusText(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onBackground,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Color _getButtonColor() {
    switch (widget.state) {
      case RecordingState.idle:
        return Theme.of(context).colorScheme.primary;
      case RecordingState.recording:
        return Theme.of(context).colorScheme.error;
      case RecordingState.processing:
        return Theme.of(context).colorScheme.tertiary;
      case RecordingState.ready:
        return Theme.of(context).colorScheme.secondary;
    }
  }

  Widget _buildButtonContent() {
    switch (widget.state) {
      case RecordingState.idle:
        return Icon(
          Icons.mic,
          color: Theme.of(context).colorScheme.onPrimary,
          size: 36,
        );
      case RecordingState.recording:
        return Icon(
          Icons.stop,
          color: Theme.of(context).colorScheme.onError,
          size: 36,
        );
      case RecordingState.processing:
        return SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.onTertiary,
            strokeWidth: 3,
          ),
        );
      case RecordingState.ready:
        return Icon(
          Icons.check,
          color: Theme.of(context).colorScheme.onSecondary,
          size: 36,
        );
    }
  }

  String _getStatusText() {
    switch (widget.state) {
      case RecordingState.idle:
        return 'Tap to record';
      case RecordingState.recording:
        return 'Recording... Tap to stop';
      case RecordingState.processing:
        return 'Processing...';
      case RecordingState.ready:
        return 'Ready to post';
    }
  }
}