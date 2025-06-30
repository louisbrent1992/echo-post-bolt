/// Represents the progress of a single platform posting operation
enum PostState {
  pending,
  inFlight,
  success,
  error,
}

/// Progress update for automated posting operations
class PostProgress {
  final String platform;
  final PostState state;
  final String? error;
  final String? targetName; // Optional display name for the target
  final double? progress; // 0.0 - 1.0 inclusive for granular updates

  const PostProgress({
    required this.platform,
    required this.state,
    this.error,
    this.targetName,
    this.progress,
  });

  @override
  String toString() {
    return 'PostProgress(platform: $platform, state: $state, progress: $progress, error: $error, targetName: $targetName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PostProgress &&
        other.platform == platform &&
        other.state == state &&
        other.error == error &&
        other.targetName == targetName &&
        other.progress == progress;
  }

  @override
  int get hashCode {
    return platform.hashCode ^
        state.hashCode ^
        error.hashCode ^
        targetName.hashCode ^
        (progress?.hashCode ?? 0);
  }
}
