import 'package:flutter/foundation.dart';
import '../constants/social_platforms.dart';

/// Result of media detection parsing
class MediaRequest {
  final String mediaType; // 'image' or 'video'
  final bool isRecent; // true if "last/recent/latest" detected
  final String? modifier; // 'my', 'the', etc.
  final double confidence; // matching confidence score
  final List<String> matchedTerms; // for debugging

  const MediaRequest({
    required this.mediaType,
    required this.isRecent,
    this.modifier,
    required this.confidence,
    this.matchedTerms = const [],
  });

  @override
  String toString() {
    return 'MediaRequest(type: $mediaType, recent: $isRecent, modifier: $modifier, confidence: $confidence)';
  }
}

/// Result of platform detection parsing
class PlatformRequest {
  final String platform; // normalized platform name
  final String? modifier; // 'my', 'the', etc.
  final double confidence; // matching confidence score
  final List<String> matchedTerms; // for debugging

  const PlatformRequest({
    required this.platform,
    this.modifier,
    required this.confidence,
    this.matchedTerms = const [],
  });

  @override
  String toString() {
    return 'PlatformRequest(platform: $platform, modifier: $modifier, confidence: $confidence)';
  }
}

/// Flexible regex-based natural language parser for media and platform detection
class NaturalLanguageParser {
  // Base media types with synonyms
  static const Map<String, List<String>> _mediaTypes = {
    'image': ['image', 'picture', 'photo', 'pic', 'shot', 'selfie', 'snap'],
    'video': ['video', 'clip', 'recording', 'movie', 'film', 'footage'],
  };

  // Modifiers (pronouns, articles, demonstratives)
  static const List<String> _possessivePronouns = [
    'my',
    'our',
    'his',
    'her',
    'their',
    'your'
  ];
  static const List<String> _articles = ['the', 'a', 'an'];
  static const List<String> _demonstratives = [
    'this',
    'that',
    'these',
    'those'
  ];

  // Temporal indicators
  static const List<String> _temporalWords = [
    'last',
    'latest',
    'recent',
    'newest',
    'previous'
  ];

  // Action verbs
  static const List<String> _actionVerbs = [
    'post',
    'share',
    'upload',
    'send',
    'publish',
    'put'
  ];

  // Compiled regex patterns
  late final RegExp _mediaReferencePattern;
  late final RegExp _platformReferencePattern;
  late final RegExp _recentMediaPattern;
  late final RegExp _actionPlatformPattern;

  NaturalLanguageParser() {
    _buildPatterns();
  }

  /// Build all regex patterns from component lists
  void _buildPatterns() {
    // Build component groups
    final modifiers = _buildModifierGroup();
    final temporal = _buildTemporalGroup();
    final mediaTypes = _buildMediaTypeGroup();
    final platforms = _buildPlatformGroup();
    final actions = _buildActionGroup();

    // Media reference pattern: (modifier)? (temporal)? (media_type)
    _mediaReferencePattern = RegExp(
      r'\b(?:' +
          modifiers +
          r')?\s*(?:' +
          temporal +
          r')?\s*(?:' +
          mediaTypes +
          r')\b',
      caseSensitive: false,
    );

    // Platform reference pattern: (modifier)? (platform)
    _platformReferencePattern = RegExp(
      r'\b(?:' + modifiers + r')?\s*(?:' + platforms + r')\b',
      caseSensitive: false,
    );

    // Recent media pattern: (temporal) (modifier)? (media_type)
    _recentMediaPattern = RegExp(
      r'\b(?:' +
          temporal +
          r')\s+(?:' +
          modifiers +
          r')?\s*(?:' +
          mediaTypes +
          r')\b',
      caseSensitive: false,
    );

    // Action + platform pattern: (action) (to)? (modifier)? (platform)
    _actionPlatformPattern = RegExp(
      r'\b(?:' +
          actions +
          r')\s+(?:to\s+)?(?:' +
          modifiers +
          r')?\s*(?:' +
          platforms +
          r')\b',
      caseSensitive: false,
    );

    if (kDebugMode) {
      print('🔧 NaturalLanguageParser: Regex patterns compiled');
      print('   Media pattern: ${_mediaReferencePattern.pattern}');
      print('   Platform pattern: ${_platformReferencePattern.pattern}');
    }
  }

  /// Build modifier group (pronouns, articles, demonstratives)
  String _buildModifierGroup() {
    final allModifiers = [
      ..._possessivePronouns,
      ..._articles,
      ..._demonstratives,
    ];
    return allModifiers.join('|');
  }

  /// Build temporal group
  String _buildTemporalGroup() {
    return _temporalWords.join('|');
  }

  /// Build media type group
  String _buildMediaTypeGroup() {
    final allMediaTerms = _mediaTypes.values.expand((terms) => terms).toList();
    return allMediaTerms.join('|');
  }

  /// Build platform group using centralized registry
  String _buildPlatformGroup() {
    final allPlatformTerms =
        SocialPlatforms.aliases.values.expand((terms) => terms).toList();
    return allPlatformTerms.join('|');
  }

  /// Build action group
  String _buildActionGroup() {
    return _actionVerbs.join('|');
  }

  /// Parse media request from transcription
  MediaRequest? parseMediaRequest(String transcription) {
    final text = transcription.toLowerCase().trim();

    // Try recent media pattern first (higher confidence)
    final recentMatch = _recentMediaPattern.firstMatch(text);
    if (recentMatch != null) {
      final matchedText = recentMatch.group(0)!;
      final mediaType = _extractMediaType(matchedText);
      final modifier = _extractModifier(matchedText);

      if (mediaType != null) {
        if (kDebugMode) {
          print(
              '📱 Recent media match: "$matchedText" -> type: $mediaType, modifier: $modifier');
        }

        return MediaRequest(
          mediaType: mediaType,
          isRecent: true,
          modifier: modifier,
          confidence: 0.9,
          matchedTerms: [matchedText],
        );
      }
    }

    // Try general media pattern
    final mediaMatch = _mediaReferencePattern.firstMatch(text);
    if (mediaMatch != null) {
      final matchedText = mediaMatch.group(0)!;
      final mediaType = _extractMediaType(matchedText);
      final modifier = _extractModifier(matchedText);
      final isRecent = _hasTemporalIndicator(matchedText);

      if (mediaType != null) {
        if (kDebugMode) {
          print(
              '📱 Media match: "$matchedText" -> type: $mediaType, modifier: $modifier, recent: $isRecent');
        }

        return MediaRequest(
          mediaType: mediaType,
          isRecent: isRecent,
          modifier: modifier,
          confidence: 0.7,
          matchedTerms: [matchedText],
        );
      }
    }

    return null;
  }

  /// Extract platforms from transcription
  List<PlatformRequest> extractPlatforms(String transcription) {
    final text = transcription.toLowerCase().trim();
    final platforms = <PlatformRequest>[];

    // Find action + platform combinations (higher confidence)
    final actionMatches = _actionPlatformPattern.allMatches(text);
    for (final match in actionMatches) {
      final matchedText = match.group(0)!;
      final platform = _extractPlatform(matchedText);
      final modifier = _extractModifier(matchedText);

      if (platform != null) {
        platforms.add(PlatformRequest(
          platform: platform,
          modifier: modifier,
          confidence: 0.9,
          matchedTerms: [matchedText],
        ));
      }
    }

    // Find general platform references
    final platformMatches = _platformReferencePattern.allMatches(text);
    for (final match in platformMatches) {
      final matchedText = match.group(0)!;
      final platform = _extractPlatform(matchedText);
      final modifier = _extractModifier(matchedText);

      if (platform != null) {
        // Check if we already found this platform with higher confidence
        final alreadyFound = platforms.any((p) => p.platform == platform);
        if (!alreadyFound) {
          platforms.add(PlatformRequest(
            platform: platform,
            modifier: modifier,
            confidence: 0.6,
            matchedTerms: [matchedText],
          ));
        }
      }
    }

    if (kDebugMode && platforms.isNotEmpty) {
      print(
          '🎯 Platform matches: ${platforms.map((p) => p.toString()).join(', ')}');
    }

    return platforms;
  }

  /// Check if transcription references media
  bool hasMediaReference(String transcription) {
    final mediaRequest = parseMediaRequest(transcription);
    return mediaRequest != null;
  }

  /// Check if transcription has recent media indicators
  bool hasRecentMediaIndicators(String transcription) {
    final mediaRequest = parseMediaRequest(transcription);
    return mediaRequest?.isRecent == true;
  }

  /// Extract media type from matched text
  String? _extractMediaType(String text) {
    for (final entry in _mediaTypes.entries) {
      for (final term in entry.value) {
        if (text.contains(term)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  /// Extract platform from matched text using centralized registry
  String? _extractPlatform(String text) {
    for (final entry in SocialPlatforms.aliases.entries) {
      for (final term in entry.value) {
        if (text.contains(term)) {
          return entry.key; // Return canonical platform name
        }
      }
    }
    return null;
  }

  /// Extract modifier from matched text
  String? _extractModifier(String text) {
    final allModifiers = [
      ..._possessivePronouns,
      ..._articles,
      ..._demonstratives,
    ];

    for (final modifier in allModifiers) {
      if (text.contains(modifier)) {
        return modifier;
      }
    }
    return null;
  }

  /// Check if text has temporal indicator
  bool _hasTemporalIndicator(String text) {
    return _temporalWords.any((word) => text.contains(word));
  }

  /// Test the parser with common phrases
  void testPatterns() {
    if (!kDebugMode) return;

    final testPhrases = [
      'post my last video',
      'share my latest picture to Instagram',
      'upload this video to my TikTok',
      'put the photo on Facebook',
      'send our recent clip to YouTube',
      'post the image',
      'share to my Instagram',
      'upload to TikTok',
    ];

    print('🧪 Testing NaturalLanguageParser patterns:');
    for (final phrase in testPhrases) {
      print('   "$phrase"');

      final mediaRequest = parseMediaRequest(phrase);
      if (mediaRequest != null) {
        print('      Media: $mediaRequest');
      }

      final platforms = extractPlatforms(phrase);
      if (platforms.isNotEmpty) {
        print(
            '      Platforms: ${platforms.map((p) => p.platform).join(', ')}');
      }

      if (mediaRequest == null && platforms.isEmpty) {
        print('      No matches');
      }
    }
  }
}
