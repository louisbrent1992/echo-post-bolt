import 'package:flutter/material.dart';

/// Centralized registry for all supported social media platforms
/// This serves as the single source of truth for platform definitions,
/// capabilities, and configuration throughout the app.
class SocialPlatforms {
  // Private constructor to prevent instantiation
  SocialPlatforms._();

  /// All supported platform identifiers (canonical names)
  static const List<String> all = [
    'facebook',
    'instagram',
    'youtube',
    'twitter',
    'tiktok',
  ];

  /// Platforms that require media content
  static const List<String> mediaRequired = [
    'instagram',
    'youtube',
    'tiktok',
  ];

  /// Platforms that support text-only posts
  static const List<String> textSupported = [
    'facebook',
    'twitter',
  ];

  /// Platform aliases and alternative names for natural language processing
  static const Map<String, List<String>> aliases = {
    'facebook': ['facebook', 'fb'],
    'instagram': ['instagram', 'insta', 'ig'],
    'youtube': ['youtube', 'yt'],
    'twitter': ['twitter', 'x'],
    'tiktok': ['tiktok', 'tik tok', 'tiktak'],
  };

  /// Platform display names for UI
  static const Map<String, String> displayNames = {
    'facebook': 'Facebook',
    'instagram': 'Instagram',
    'youtube': 'YouTube',
    'twitter': 'Twitter',
    'tiktok': 'TikTok',
  };

  /// Platform colors for UI theming
  static const Map<String, Color> colors = {
    'facebook': Color(0xFF1877F2),
    'instagram': Color(0xFFE4405F),
    'youtube': Color(0xFFFF0000),
    'twitter': Color(0xFF1DA1F2),
    'tiktok': Color(0xFFFF0050),
  };

  /// Platform icons
  static const Map<String, IconData> icons = {
    'facebook': Icons.facebook,
    'instagram': Icons.photo_camera,
    'youtube': Icons.play_circle_fill,
    'twitter': Icons.tag,
    'tiktok': Icons.music_video,
  };

  /// Platform capabilities
  static const Map<String, PlatformCapabilities> capabilities = {
    'facebook': PlatformCapabilities(
      supportsText: true,
      supportsImages: true,
      supportsVideos: true,
      requiresMedia: false,
      maxTextLength: 63206,
      maxHashtags: 30,
    ),
    'instagram': PlatformCapabilities(
      supportsText: true,
      supportsImages: true,
      supportsVideos: true,
      requiresMedia: true,
      maxTextLength: 2200,
      maxHashtags: 30,
    ),
    'youtube': PlatformCapabilities(
      supportsText: true,
      supportsImages: false,
      supportsVideos: true,
      requiresMedia: true,
      maxTextLength: 5000,
      maxHashtags: 15,
    ),
    'twitter': PlatformCapabilities(
      supportsText: true,
      supportsImages: true,
      supportsVideos: true,
      requiresMedia: false,
      maxTextLength: 280,
      maxHashtags: 10,
    ),
    'tiktok': PlatformCapabilities(
      supportsText: true,
      supportsImages: false,
      supportsVideos: true,
      requiresMedia: true,
      maxTextLength: 2200,
      maxHashtags: 20,
    ),
  };

  /// Hashtag formatting rules for each platform
  static const Map<String, HashtagFormat> hashtagFormats = {
    'facebook': HashtagFormat(
      position: HashtagPosition.end,
      separator: ' ',
      maxLength: 100,
      prefix: '\n\n',
    ),
    'instagram': HashtagFormat(
      position: HashtagPosition.end,
      separator: ' ',
      maxLength: 100,
      prefix: '\n\n',
    ),
    'youtube': HashtagFormat(
      position: HashtagPosition.end,
      separator: ' ',
      maxLength: 100,
      prefix: '\n\n',
    ),
    'twitter': HashtagFormat(
      position: HashtagPosition.inline,
      separator: ' ',
      maxLength: 100,
      prefix: ' ',
    ),
    'tiktok': HashtagFormat(
      position: HashtagPosition.end,
      separator: ' ',
      maxLength: 100,
      prefix: '\n\n',
    ),
  };

  // Utility methods

  /// Check if a platform requires media
  static bool requiresMedia(String platform) {
    return mediaRequired.contains(platform.toLowerCase());
  }

  /// Check if a platform supports text-only posts
  static bool supportsTextOnly(String platform) {
    return textSupported.contains(platform.toLowerCase());
  }

  /// Check if a platform is valid/supported
  static bool isSupported(String platform) {
    return all.contains(platform.toLowerCase());
  }

  /// Get canonical platform name from alias
  static String? getCanonicalName(String platformAlias) {
    final lowerAlias = platformAlias.toLowerCase();

    for (final entry in aliases.entries) {
      if (entry.value.contains(lowerAlias)) {
        return entry.key;
      }
    }

    return isSupported(lowerAlias) ? lowerAlias : null;
  }

  /// Get all aliases for a platform
  static List<String> getAliases(String platform) {
    return aliases[platform.toLowerCase()] ?? [];
  }

  /// Get display name for a platform
  static String getDisplayName(String platform) {
    return displayNames[platform.toLowerCase()] ?? platform;
  }

  /// Get color for a platform
  static Color getColor(String platform) {
    return colors[platform.toLowerCase()] ?? Colors.grey;
  }

  /// Get icon for a platform
  static IconData getIcon(String platform) {
    return icons[platform.toLowerCase()] ?? Icons.public;
  }

  /// Get capabilities for a platform
  static PlatformCapabilities? getCapabilities(String platform) {
    return capabilities[platform.toLowerCase()];
  }

  /// Get hashtag format for a platform
  static HashtagFormat? getHashtagFormat(String platform) {
    return hashtagFormats[platform.toLowerCase()];
  }

  /// Get platforms that support a specific media type
  static List<String> getPlatformsForMediaType(String mediaType) {
    switch (mediaType.toLowerCase()) {
      case 'image':
        return all
            .where((platform) => capabilities[platform]?.supportsImages == true)
            .toList();
      case 'video':
        return all
            .where((platform) => capabilities[platform]?.supportsVideos == true)
            .toList();
      default:
        return [];
    }
  }

  /// Get default platforms based on content type
  static List<String> getDefaultPlatforms({
    bool hasMedia = false,
    String? mediaType,
  }) {
    if (!hasMedia) {
      // Text-only content
      return textSupported;
    }

    if (mediaType != null) {
      // Specific media type
      return getPlatformsForMediaType(mediaType);
    }

    // General media content
    return all;
  }
}

/// Platform capabilities definition
class PlatformCapabilities {
  final bool supportsText;
  final bool supportsImages;
  final bool supportsVideos;
  final bool requiresMedia;
  final int maxTextLength;
  final int maxHashtags;

  const PlatformCapabilities({
    required this.supportsText,
    required this.supportsImages,
    required this.supportsVideos,
    required this.requiresMedia,
    required this.maxTextLength,
    required this.maxHashtags,
  });
}

/// Hashtag formatting configuration
class HashtagFormat {
  final HashtagPosition position;
  final String separator;
  final int maxLength;
  final String prefix;

  const HashtagFormat({
    required this.position,
    required this.separator,
    required this.maxLength,
    required this.prefix,
  });
}

/// Hashtag position enum
enum HashtagPosition {
  inline, // Integrated within the text
  end, // At the end of the post
}

/// Social platform enum for type safety
enum SocialPlatform {
  facebook,
  instagram,
  youtube,
  twitter,
  tiktok;

  /// Get the string identifier for this platform
  String get id => name;

  /// Get the display name for this platform
  String get displayName => SocialPlatforms.getDisplayName(id);

  /// Get the color for this platform
  Color get color => SocialPlatforms.getColor(id);

  /// Get the icon for this platform
  IconData get icon => SocialPlatforms.getIcon(id);

  /// Get the capabilities for this platform
  PlatformCapabilities? get capabilities => SocialPlatforms.getCapabilities(id);

  /// Check if this platform requires media
  bool get requiresMedia => SocialPlatforms.requiresMedia(id);

  /// Check if this platform supports text-only posts
  bool get supportsTextOnly => SocialPlatforms.supportsTextOnly(id);

  /// Create from string identifier
  static SocialPlatform? fromString(String platform) {
    final canonical = SocialPlatforms.getCanonicalName(platform);
    if (canonical == null) return null;

    return SocialPlatform.values.firstWhere(
      (p) => p.id == canonical,
      orElse: () => throw ArgumentError('Unknown platform: $platform'),
    );
  }
}
