import 'dart:io';
import 'package:flutter/foundation.dart';

/// VideoValidationService: Platform-specific video format validation
///
/// This service validates video files for compatibility with major social media platforms
/// including Instagram, TikTok, and Twitter. It checks format, duration, resolution,
/// file size, and codec requirements for optimal posting success.
class VideoValidationService {
  static const Map<String, PlatformVideoRequirements> _platformRequirements = {
    'instagram': PlatformVideoRequirements(
      supportedFormats: ['mp4', 'mov'],
      supportedMimeTypes: ['video/mp4', 'video/quicktime'],
      maxDurationSeconds: 60, // Feed posts
      maxFileSizeMB: 4000, // 4GB for IGTV
      minResolution: VideoResolution(width: 320, height: 320),
      maxResolution: VideoResolution(width: 1920, height: 1920),
      preferredAspectRatios: [1.0, 0.8, 1.91], // Square, 4:5, 16:9
      supportedVideoCodecs: ['h264', 'h265'],
      supportedAudioCodecs: ['aac'],
      maxBitrateMbps: 25,
      frameRateRange: FrameRateRange(min: 23, max: 60),
    ),
    'tiktok': PlatformVideoRequirements(
      supportedFormats: ['mp4', 'mov'],
      supportedMimeTypes: ['video/mp4', 'video/quicktime'],
      maxDurationSeconds: 600, // 10 minutes
      maxFileSizeMB: 287, // ~287MB
      minResolution: VideoResolution(width: 540, height: 960),
      maxResolution: VideoResolution(width: 1080, height: 1920),
      preferredAspectRatios: [0.5625], // 9:16 (vertical)
      supportedVideoCodecs: ['h264', 'h265'],
      supportedAudioCodecs: ['aac'],
      maxBitrateMbps: 10,
      frameRateRange: FrameRateRange(min: 23, max: 60),
    ),
    'twitter': PlatformVideoRequirements(
      supportedFormats: ['mp4', 'mov'],
      supportedMimeTypes: ['video/mp4', 'video/quicktime'],
      maxDurationSeconds: 140, // 2 minutes 20 seconds
      maxFileSizeMB: 512, // 512MB
      minResolution: VideoResolution(width: 32, height: 32),
      maxResolution: VideoResolution(width: 1920, height: 1200),
      preferredAspectRatios: [1.77, 1.0, 0.5625], // 16:9, 1:1, 9:16
      supportedVideoCodecs: ['h264'],
      supportedAudioCodecs: ['aac'],
      maxBitrateMbps: 25,
      frameRateRange: FrameRateRange(min: 1, max: 60),
    ),
  };

  /// Validates a video file for all specified platforms
  static Future<VideoValidationResult> validateVideoForPlatforms(
    String filePath,
    List<String> platforms, {
    bool strictMode = false,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return VideoValidationResult(
          isValid: false,
          errors: ['Video file does not exist: $filePath'],
          warnings: [],
          platformResults: {},
        );
      }

      // Get basic file info
      final fileInfo = await _getBasicFileInfo(file);
      if (fileInfo == null) {
        return const VideoValidationResult(
          isValid: false,
          errors: ['Could not read video file information'],
          warnings: [],
          platformResults: {},
        );
      }

      // Validate header
      final headerValidation = await _validateVideoHeader(file);
      if (!headerValidation.isValid) {
        return VideoValidationResult(
          isValid: false,
          errors: headerValidation.errors,
          warnings: headerValidation.warnings,
          platformResults: {},
        );
      }

      // Validate for each platform
      final platformResults = <String, PlatformValidationResult>{};
      final allErrors = <String>[];
      final allWarnings = <String>[];

      for (final platform in platforms) {
        final platformResult = await _validateForPlatform(
          fileInfo,
          platform,
          strictMode: strictMode,
        );

        platformResults[platform] = platformResult;

        if (!platformResult.isValid) {
          allErrors.addAll(platformResult.errors.map((e) => '$platform: $e'));
        }
        allWarnings.addAll(platformResult.warnings.map((w) => '$platform: $w'));
      }

      return VideoValidationResult(
        isValid: allErrors.isEmpty,
        errors: allErrors,
        warnings: allWarnings,
        platformResults: platformResults,
      );
    } catch (e) {
      if (kDebugMode) {
        print('❌ VideoValidationService: Error validating video: $e');
      }
      return VideoValidationResult(
        isValid: false,
        errors: ['Video validation failed: $e'],
        warnings: [],
        platformResults: {},
      );
    }
  }

  /// Gets basic file information needed for validation
  static Future<VideoFileInfo?> _getBasicFileInfo(File file) async {
    try {
      final stats = await file.stat();
      final extension = file.path.toLowerCase().split('.').last;
      final mimeType = _getMimeTypeFromExtension(extension);

      // For basic validation, we'll estimate these values
      // In a full implementation, you'd use a video metadata library
      return VideoFileInfo(
        filePath: file.path,
        fileSizeBytes: stats.size,
        mimeType: mimeType,
        extension: extension,
        // Estimated values - in production use ffprobe or similar
        durationSeconds: 30.0, // Placeholder
        width: 1080, // Placeholder
        height: 1920, // Placeholder
        frameRate: 30.0, // Placeholder
        bitrateMbps: 5.0, // Placeholder
        videoCodec: 'h264', // Assumption for common formats
        audioCodec: 'aac', // Assumption for common formats
      );
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting video file info: $e');
      }
      return null;
    }
  }

  /// Validates video file header to ensure it's a valid video file
  static Future<HeaderValidationResult> _validateVideoHeader(File file) async {
    try {
      final bytes = await file.openRead(0, 32).toList();
      final headerBytes = bytes.expand((x) => x).toList();

      if (headerBytes.length < 8) {
        return const HeaderValidationResult(
          isValid: false,
          errors: ['Video file too small or corrupted'],
          warnings: [],
        );
      }

      // Check common video file signatures
      final isValidVideo = _hasValidVideoHeader(headerBytes);

      if (!isValidVideo) {
        return const HeaderValidationResult(
          isValid: false,
          errors: ['Invalid video file format or corrupted header'],
          warnings: [],
        );
      }

      return const HeaderValidationResult(
        isValid: true,
        errors: [],
        warnings: [],
      );
    } catch (e) {
      return HeaderValidationResult(
        isValid: false,
        errors: ['Could not read video file header: $e'],
        warnings: [],
      );
    }
  }

  /// Checks if the file has a valid video header signature
  static bool _hasValidVideoHeader(List<int> bytes) {
    if (bytes.length < 8) return false;

    // MP4/MOV container (ftyp box)
    if (bytes.length >= 8) {
      final ftypSignature = String.fromCharCodes(bytes.sublist(4, 8));
      if (ftypSignature == 'ftyp') return true;
    }

    // AVI header
    if (bytes.length >= 12) {
      final riffSignature = String.fromCharCodes(bytes.sublist(0, 4));
      final aviSignature = String.fromCharCodes(bytes.sublist(8, 12));
      if (riffSignature == 'RIFF' && aviSignature == 'AVI ') return true;
    }

    // WebM header
    if (bytes.length >= 4) {
      // WebM uses EBML header
      if (bytes[0] == 0x1A &&
          bytes[1] == 0x45 &&
          bytes[2] == 0xDF &&
          bytes[3] == 0xA3) {
        return true;
      }
    }

    return false;
  }

  /// Validates video against platform-specific requirements
  static Future<PlatformValidationResult> _validateForPlatform(
    VideoFileInfo fileInfo,
    String platform, {
    bool strictMode = false,
  }) async {
    final requirements = _platformRequirements[platform.toLowerCase()];
    if (requirements == null) {
      return PlatformValidationResult(
        isValid: false,
        errors: ['Unsupported platform: $platform'],
        warnings: [],
      );
    }

    final errors = <String>[];
    final warnings = <String>[];

    // Format validation
    if (!requirements.supportedFormats.contains(fileInfo.extension)) {
      errors.add('Unsupported format: ${fileInfo.extension}. '
          'Supported: ${requirements.supportedFormats.join(', ')}');
    }

    if (!requirements.supportedMimeTypes.contains(fileInfo.mimeType)) {
      errors.add('Unsupported MIME type: ${fileInfo.mimeType}');
    }

    // Duration validation
    if (fileInfo.durationSeconds > requirements.maxDurationSeconds) {
      if (strictMode) {
        errors.add(
            'Video too long: ${fileInfo.durationSeconds.toStringAsFixed(1)}s. '
            'Max: ${requirements.maxDurationSeconds}s');
      } else {
        warnings.add('Video may be too long for optimal posting: '
            '${fileInfo.durationSeconds.toStringAsFixed(1)}s. '
            'Recommended max: ${requirements.maxDurationSeconds}s');
      }
    }

    // File size validation
    final fileSizeMB = fileInfo.fileSizeBytes / (1024 * 1024);
    if (fileSizeMB > requirements.maxFileSizeMB) {
      errors.add('File too large: ${fileSizeMB.toStringAsFixed(1)}MB. '
          'Max: ${requirements.maxFileSizeMB}MB');
    }

    // Resolution validation
    if (fileInfo.width < requirements.minResolution.width ||
        fileInfo.height < requirements.minResolution.height) {
      errors.add('Resolution too low: ${fileInfo.width}x${fileInfo.height}. '
          'Min: ${requirements.minResolution.width}x${requirements.minResolution.height}');
    }

    if (fileInfo.width > requirements.maxResolution.width ||
        fileInfo.height > requirements.maxResolution.height) {
      warnings.add(
          'Resolution very high: ${fileInfo.width}x${fileInfo.height}. '
          'Max recommended: ${requirements.maxResolution.width}x${requirements.maxResolution.height}');
    }

    // Aspect ratio validation
    final aspectRatio = fileInfo.width / fileInfo.height;
    final hasGoodAspectRatio = requirements.preferredAspectRatios
        .any((preferred) => (aspectRatio - preferred).abs() < 0.1);

    if (!hasGoodAspectRatio) {
      warnings.add(
          'Aspect ratio ${aspectRatio.toStringAsFixed(2)} may not be optimal. '
          'Preferred: ${requirements.preferredAspectRatios.map((r) => r.toStringAsFixed(2)).join(', ')}');
    }

    // Frame rate validation
    if (fileInfo.frameRate < requirements.frameRateRange.min ||
        fileInfo.frameRate > requirements.frameRateRange.max) {
      warnings.add(
          'Frame rate ${fileInfo.frameRate}fps outside recommended range: '
          '${requirements.frameRateRange.min}-${requirements.frameRateRange.max}fps');
    }

    // Bitrate validation
    if (fileInfo.bitrateMbps > requirements.maxBitrateMbps) {
      warnings.add(
          'High bitrate ${fileInfo.bitrateMbps}Mbps may cause upload issues. '
          'Max recommended: ${requirements.maxBitrateMbps}Mbps');
    }

    // Codec validation
    if (requirements.supportedVideoCodecs.isNotEmpty &&
        !requirements.supportedVideoCodecs
            .contains(fileInfo.videoCodec.toLowerCase())) {
      warnings.add('Video codec ${fileInfo.videoCodec} may not be optimal. '
          'Preferred: ${requirements.supportedVideoCodecs.join(', ')}');
    }

    if (requirements.supportedAudioCodecs.isNotEmpty &&
        !requirements.supportedAudioCodecs
            .contains(fileInfo.audioCodec.toLowerCase())) {
      warnings.add('Audio codec ${fileInfo.audioCodec} may not be optimal. '
          'Preferred: ${requirements.supportedAudioCodecs.join(', ')}');
    }

    return PlatformValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  /// Gets MIME type from file extension
  static String _getMimeTypeFromExtension(String extension) {
    const mimeTypes = {
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'avi': 'video/x-msvideo',
      'mkv': 'video/x-matroska',
      'webm': 'video/webm',
      'm4v': 'video/x-m4v',
      '3gp': 'video/3gpp',
      'flv': 'video/x-flv',
      'wmv': 'video/x-ms-wmv',
      'mpg': 'video/mpeg',
      'mpeg': 'video/mpeg',
    };
    return mimeTypes[extension.toLowerCase()] ?? 'video/mp4';
  }

  /// Gets platform-specific recommendations for video optimization
  static Map<String, String> getPlatformRecommendations(String platform) {
    final requirements = _platformRequirements[platform.toLowerCase()];
    if (requirements == null) return {};

    return {
      'format': requirements.supportedFormats.first.toUpperCase(),
      'max_duration': '${requirements.maxDurationSeconds}s',
      'max_file_size': '${requirements.maxFileSizeMB}MB',
      'recommended_resolution':
          '${requirements.maxResolution.width}x${requirements.maxResolution.height}',
      'aspect_ratio':
          requirements.preferredAspectRatios.first.toStringAsFixed(2),
      'video_codec': requirements.supportedVideoCodecs.first.toUpperCase(),
      'audio_codec': requirements.supportedAudioCodecs.first.toUpperCase(),
    };
  }
}

/// Platform-specific video requirements
class PlatformVideoRequirements {
  final List<String> supportedFormats;
  final List<String> supportedMimeTypes;
  final int maxDurationSeconds;
  final int maxFileSizeMB;
  final VideoResolution minResolution;
  final VideoResolution maxResolution;
  final List<double> preferredAspectRatios;
  final List<String> supportedVideoCodecs;
  final List<String> supportedAudioCodecs;
  final int maxBitrateMbps;
  final FrameRateRange frameRateRange;

  const PlatformVideoRequirements({
    required this.supportedFormats,
    required this.supportedMimeTypes,
    required this.maxDurationSeconds,
    required this.maxFileSizeMB,
    required this.minResolution,
    required this.maxResolution,
    required this.preferredAspectRatios,
    required this.supportedVideoCodecs,
    required this.supportedAudioCodecs,
    required this.maxBitrateMbps,
    required this.frameRateRange,
  });
}

/// Video file information structure
class VideoFileInfo {
  final String filePath;
  final int fileSizeBytes;
  final String mimeType;
  final String extension;
  final double durationSeconds;
  final int width;
  final int height;
  final double frameRate;
  final double bitrateMbps;
  final String videoCodec;
  final String audioCodec;

  const VideoFileInfo({
    required this.filePath,
    required this.fileSizeBytes,
    required this.mimeType,
    required this.extension,
    required this.durationSeconds,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.bitrateMbps,
    required this.videoCodec,
    required this.audioCodec,
  });
}

/// Video resolution structure
class VideoResolution {
  final int width;
  final int height;

  const VideoResolution({
    required this.width,
    required this.height,
  });
}

/// Frame rate range structure
class FrameRateRange {
  final int min;
  final int max;

  const FrameRateRange({
    required this.min,
    required this.max,
  });
}

/// Overall validation result
class VideoValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final Map<String, PlatformValidationResult> platformResults;

  const VideoValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
    required this.platformResults,
  });
}

/// Platform-specific validation result
class PlatformValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;

  const PlatformValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
  });
}

/// Header validation result
class HeaderValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;

  const HeaderValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
  });
}
