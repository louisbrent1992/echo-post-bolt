import 'package:flutter/foundation.dart';
import '../services/video_validation_service.dart';

/// Example usage of VideoValidationService for social media platforms
///
/// This example demonstrates how to validate video files against platform
/// requirements for Instagram, TikTok, and Twitter.
class VideoValidationExample {
  /// Example: Validate a video for Instagram posting
  static Future<void> validateVideoForInstagram(String videoPath) async {
    if (kDebugMode) {
      print('🎬 Validating video for Instagram...');
    }

    final result = await VideoValidationService.validateVideoForPlatforms(
      videoPath,
      ['instagram'],
      strictMode: true, // Use strict mode for production posting
    );

    if (result.isValid) {
      if (kDebugMode) {
        print('✅ Video is compatible with Instagram!');
        if (result.warnings.isNotEmpty) {
          print('⚠️ Warnings:');
          for (final warning in result.warnings) {
            print('   - $warning');
          }
        }
      }
    } else {
      if (kDebugMode) {
        print('❌ Video is NOT compatible with Instagram:');
        for (final error in result.errors) {
          print('   - $error');
        }
      }
    }
  }

  /// Example: Validate a video for TikTok posting
  static Future<void> validateVideoForTikTok(String videoPath) async {
    if (kDebugMode) {
      print('🎬 Validating video for TikTok...');
    }

    final result = await VideoValidationService.validateVideoForPlatforms(
      videoPath,
      ['tiktok'],
      strictMode: false, // Use lenient mode for warnings
    );

    if (result.isValid) {
      if (kDebugMode) {
        print('✅ Video is compatible with TikTok!');
      }
    } else {
      if (kDebugMode) {
        print('❌ Video has compatibility issues with TikTok:');
        for (final error in result.errors) {
          print('   - $error');
        }
      }
    }

    // Check specific platform recommendations
    final recommendations =
        VideoValidationService.getPlatformRecommendations('tiktok');
    if (kDebugMode) {
      print('💡 TikTok recommendations:');
      for (final entry in recommendations.entries) {
        print('   ${entry.key}: ${entry.value}');
      }
    }
  }

  /// Example: Validate a video for multiple platforms
  static Future<void> validateVideoForMultiplePlatforms(
      String videoPath) async {
    final platforms = ['instagram', 'tiktok', 'twitter'];

    if (kDebugMode) {
      print(
          '🎬 Validating video for multiple platforms: ${platforms.join(', ')}');
    }

    final result = await VideoValidationService.validateVideoForPlatforms(
      videoPath,
      platforms,
      strictMode: false,
    );

    if (kDebugMode) {
      print(
          '🎯 Overall validation result: ${result.isValid ? 'VALID' : 'INVALID'}');

      // Check each platform individually
      for (final platform in platforms) {
        final platformResult = result.platformResults[platform];
        if (platformResult != null) {
          print('\n📱 $platform:');
          print('   Valid: ${platformResult.isValid}');

          if (platformResult.errors.isNotEmpty) {
            print('   Errors:');
            for (final error in platformResult.errors) {
              print('     - $error');
            }
          }

          if (platformResult.warnings.isNotEmpty) {
            print('   Warnings:');
            for (final warning in platformResult.warnings) {
              print('     - $warning');
            }
          }
        }
      }
    }
  }

  /// Example: Get platform-specific recommendations
  static void showPlatformRecommendations() {
    final platforms = ['instagram', 'tiktok', 'twitter'];

    if (kDebugMode) {
      print('📋 Platform-specific video recommendations:\n');

      for (final platform in platforms) {
        print('📱 ${platform.toUpperCase()}:');
        final recommendations =
            VideoValidationService.getPlatformRecommendations(platform);

        for (final entry in recommendations.entries) {
          final key = entry.key.replaceAll('_', ' ').toUpperCase();
          print('   $key: ${entry.value}');
        }
        print('');
      }
    }
  }

  /// Example: Common video format compatibility check
  static Future<void> checkCommonVideoFormats() async {
    final formats = [
      {'path': '/path/to/video.mp4', 'description': 'MP4 H.264'},
      {'path': '/path/to/video.mov', 'description': 'QuickTime MOV'},
      {'path': '/path/to/video.avi', 'description': 'AVI'},
      {'path': '/path/to/video.mkv', 'description': 'MKV'},
    ];

    if (kDebugMode) {
      print('🔍 Testing common video format compatibility:\n');
    }

    for (final format in formats) {
      if (kDebugMode) {
        print('📹 Testing ${format['description']}...');
      }

      try {
        final result = await VideoValidationService.validateVideoForPlatforms(
          format['path']!,
          ['instagram', 'tiktok', 'twitter'],
          strictMode: false,
        );

        if (kDebugMode) {
          print('   Overall valid: ${result.isValid}');
          print(
              '   Instagram: ${result.platformResults['instagram']?.isValid ?? false}');
          print(
              '   TikTok: ${result.platformResults['tiktok']?.isValid ?? false}');
          print(
              '   Twitter: ${result.platformResults['twitter']?.isValid ?? false}');
          print('');
        }
      } catch (e) {
        if (kDebugMode) {
          print('   Error: $e\n');
        }
      }
    }
  }

  /// Example: Handle video validation in UI workflow
  static Future<Map<String, String>> validateVideoForUI(
    String videoPath,
    List<String> selectedPlatforms,
  ) async {
    final result = await VideoValidationService.validateVideoForPlatforms(
      videoPath,
      selectedPlatforms,
      strictMode: false,
    );

    final messages = <String, String>{};

    if (result.isValid) {
      if (result.warnings.isEmpty) {
        messages['success'] =
            'Video is compatible with all selected platforms! 🎉';
      } else {
        messages['warning'] = 'Video is compatible but has some warnings. '
            'Consider optimizing for better results.';
      }
    } else {
      messages['error'] =
          'Video has compatibility issues that need to be resolved '
          'before posting to some platforms.';
    }

    // Add platform-specific messages
    for (final platform in selectedPlatforms) {
      final platformResult = result.platformResults[platform];
      if (platformResult != null) {
        if (!platformResult.isValid) {
          messages['${platform}_error'] = 'Not compatible with $platform: '
              '${platformResult.errors.join(', ')}';
        } else if (platformResult.warnings.isNotEmpty) {
          messages['${platform}_warning'] = '$platform warnings: '
              '${platformResult.warnings.join(', ')}';
        }
      }
    }

    return messages;
  }
}

/// Platform-specific video requirements summary
class VideoRequirementsSummary {
  static const Map<String, Map<String, String>> platformRequirements = {
    'instagram': {
      'formats': 'MP4, MOV',
      'codecs': 'H.264/H.265 + AAC',
      'duration': '60 seconds (feed), 15 minutes (IGTV)',
      'resolution': '320x320 to 1920x1920',
      'aspect_ratio': '1:1, 4:5, 16:9',
      'file_size': '4GB max',
      'bitrate': '25 Mbps max',
      'frame_rate': '23-60 fps',
    },
    'tiktok': {
      'formats': 'MP4, MOV',
      'codecs': 'H.264/H.265 + AAC',
      'duration': '15 seconds to 10 minutes',
      'resolution': '540x960 to 1080x1920',
      'aspect_ratio': '9:16 (vertical preferred)',
      'file_size': '287MB max',
      'bitrate': '10 Mbps max',
      'frame_rate': '23-60 fps',
    },
    'twitter': {
      'formats': 'MP4, MOV',
      'codecs': 'H.264 + AAC',
      'duration': '2 minutes 20 seconds max',
      'resolution': '32x32 to 1920x1200',
      'aspect_ratio': '16:9, 1:1, 9:16',
      'file_size': '512MB max',
      'bitrate': '25 Mbps max',
      'frame_rate': '1-60 fps',
    },
  };

  /// Get formatted requirements for display
  static String getFormattedRequirements(String platform) {
    final requirements = platformRequirements[platform.toLowerCase()];
    if (requirements == null) return 'Platform not supported';

    final buffer = StringBuffer();
    buffer.writeln('${platform.toUpperCase()} Video Requirements:');
    buffer.writeln('');

    for (final entry in requirements.entries) {
      final key = entry.key.replaceAll('_', ' ').toUpperCase();
      buffer.writeln('$key: ${entry.value}');
    }

    return buffer.toString();
  }
}
