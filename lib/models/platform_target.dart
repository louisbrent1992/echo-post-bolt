/// Represents a platform target for automated posting
/// Contains the platform, access token, and target ID (page, user, etc.)
class PlatformTarget {
  final String platform;
  final String accessToken;
  final String targetId;
  final String? targetName; // Optional display name

  const PlatformTarget({
    required this.platform,
    required this.accessToken,
    required this.targetId,
    this.targetName,
  });

  @override
  String toString() {
    return 'PlatformTarget(platform: $platform, targetId: $targetId, targetName: $targetName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlatformTarget &&
        other.platform == platform &&
        other.accessToken == accessToken &&
        other.targetId == targetId &&
        other.targetName == targetName;
  }

  @override
  int get hashCode {
    return platform.hashCode ^
        accessToken.hashCode ^
        targetId.hashCode ^
        targetName.hashCode;
  }
}

/// Represents a sub-account (Facebook Page, Instagram Business Account, etc.)
class SubAccount {
  final String targetId;
  final String name;
  final String accessToken;
  final String?
      igUserId; // For Instagram Business Accounts linked to Facebook Pages

  const SubAccount({
    required this.targetId,
    required this.name,
    required this.accessToken,
    this.igUserId,
  });

  @override
  String toString() {
    return 'SubAccount(targetId: $targetId, name: $name, igUserId: $igUserId)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SubAccount &&
        other.targetId == targetId &&
        other.name == name &&
        other.accessToken == accessToken &&
        other.igUserId == igUserId;
  }

  @override
  int get hashCode {
    return targetId.hashCode ^
        name.hashCode ^
        accessToken.hashCode ^
        igUserId.hashCode;
  }
}
