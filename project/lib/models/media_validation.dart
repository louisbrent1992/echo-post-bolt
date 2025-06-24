import 'package:flutter/foundation.dart';
import 'dart:math' as math;

/// File "birthprint" - unique identifier combining creation time, size, and filename
class MediaBirthprint {
  final DateTime creationTime;
  final int fileSize;
  final String originalFilename;
  final String? mimeType;

  const MediaBirthprint({
    required this.creationTime,
    required this.fileSize,
    required this.originalFilename,
    this.mimeType,
  });

  /// Creates unique signature for fast lookup and comparison
  String get signature =>
      '${creationTime.millisecondsSinceEpoch}_${fileSize}_${originalFilename.hashCode}';

  /// Similarity score between two birthprints (0.0 to 1.0)
  double similarityTo(MediaBirthprint other) {
    double score = 0.0;

    // File size exact match (40% weight)
    if (fileSize == other.fileSize) score += 0.4;

    // Creation time within 1 second (30% weight)
    final timeDiff =
        creationTime.difference(other.creationTime).abs().inSeconds;
    if (timeDiff <= 1)
      score += 0.3;
    else if (timeDiff <= 5) score += 0.15;

    // Filename similarity (30% weight)
    final filenameSimilarity =
        _calculateFilenameSimilarity(originalFilename, other.originalFilename);
    score += filenameSimilarity * 0.3;

    return score.clamp(0.0, 1.0);
  }

  /// Calculate filename similarity using efficient string matching
  double _calculateFilenameSimilarity(String a, String b) {
    if (a == b) return 1.0;

    final aLower = a.toLowerCase();
    final bLower = b.toLowerCase();

    // Check if one contains the other (handles renames with suffixes)
    if (aLower.contains(bLower) || bLower.contains(aLower)) return 0.8;

    // Basic Levenshtein distance for more complex matching
    final maxLen = math.max(a.length, b.length);
    if (maxLen == 0) return 1.0;

    final distance = _levenshteinDistance(aLower, bLower);
    return 1.0 - (distance / maxLen);
  }

  /// Efficient Levenshtein distance calculation
  int _levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final matrix =
        List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));

    for (int i = 0; i <= a.length; i++) matrix[i][0] = i;
    for (int j = 0; j <= b.length; j++) matrix[0][j] = j;

    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = math.min(
          math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
          matrix[i - 1][j - 1] + cost,
        );
      }
    }

    return matrix[a.length][b.length];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaBirthprint &&
          runtimeType == other.runtimeType &&
          creationTime == other.creationTime &&
          fileSize == other.fileSize &&
          originalFilename == other.originalFilename;

  @override
  int get hashCode => signature.hashCode;

  @override
  String toString() =>
      'MediaBirthprint($originalFilename, ${fileSize}B, $creationTime)';
}

/// Cache entry for validated media with timestamp
class MediaValidationCacheEntry {
  final MediaValidationResult result;
  final DateTime cachedAt;
  final MediaBirthprint? birthprint;

  const MediaValidationCacheEntry({
    required this.result,
    required this.cachedAt,
    this.birthprint,
  });

  /// Whether this cache entry is still valid (24 hour TTL)
  bool get isValid => DateTime.now().difference(cachedAt).inHours < 24;
}

/// Enumeration of different recovery methods used to fix broken media URIs
enum MediaRecoveryMethod {
  /// URI was valid, no recovery needed
  none,

  /// Recovered by searching for exact filename match
  exactFilename,

  /// Recovered by filename pattern matching (handles renames with suffixes)
  filenamePattern,

  /// Recovered by matching file metadata (size, creation time, etc.)
  metadata,

  /// Recovered after forcing comprehensive cache refresh
  cacheRefresh,

  /// All recovery attempts failed
  failed,
}

/// Result of media URI validation and recovery attempt
class MediaValidationResult {
  /// Whether the URI is valid (either originally or after recovery)
  final bool isValid;

  /// The original URI that was being validated
  final String originalUri;

  /// The recovered URI if recovery was successful, null otherwise
  final String? recoveredUri;

  /// The method used to recover the URI
  final MediaRecoveryMethod recoveryMethod;

  /// Error message if validation/recovery failed
  final String? errorMessage;

  /// Additional metadata about the recovery process
  final Map<String, dynamic>? recoveryMetadata;

  const MediaValidationResult({
    required this.isValid,
    required this.originalUri,
    this.recoveredUri,
    required this.recoveryMethod,
    this.errorMessage,
    this.recoveryMetadata,
  });

  /// Whether the URI was recovered (as opposed to being valid originally)
  bool get wasRecovered =>
      recoveryMethod != MediaRecoveryMethod.none &&
      recoveryMethod != MediaRecoveryMethod.failed;

  /// Whether recovery failed completely
  bool get recoveryFailed => recoveryMethod == MediaRecoveryMethod.failed;

  /// The effective URI to use (recovered URI if available, otherwise original)
  String get effectiveUri => recoveredUri ?? originalUri;

  /// Human-readable description of the recovery method
  String get recoveryMethodDescription {
    switch (recoveryMethod) {
      case MediaRecoveryMethod.none:
        return 'No recovery needed';
      case MediaRecoveryMethod.exactFilename:
        return 'Recovered by exact filename match';
      case MediaRecoveryMethod.filenamePattern:
        return 'Recovered by filename pattern';
      case MediaRecoveryMethod.metadata:
        return 'Recovered by metadata matching';
      case MediaRecoveryMethod.cacheRefresh:
        return 'Recovered after cache refresh';
      case MediaRecoveryMethod.failed:
        return 'Recovery failed';
    }
  }

  @override
  String toString() {
    return 'MediaValidationResult(isValid: $isValid, method: ${recoveryMethod.name}, '
        'original: $originalUri, recovered: $recoveredUri)';
  }
}

/// Batch result for validating multiple media items
class MediaValidationBatchResult {
  /// Individual validation results for each media item
  final List<MediaValidationResult> results;

  /// Total number of items validated
  final int totalItems;

  /// Number of items that were valid originally
  final int validItems;

  /// Number of items that were successfully recovered
  final int recoveredItems;

  /// Number of items that failed recovery
  final int failedItems;

  MediaValidationBatchResult({
    required this.results,
  })  : totalItems = results.length,
        validItems = results.where((r) => r.isValid && !r.wasRecovered).length,
        recoveredItems = results.where((r) => r.wasRecovered).length,
        failedItems = results.where((r) => r.recoveryFailed).length;

  /// Whether any items were recovered
  bool get hasRecoveredItems => recoveredItems > 0;

  /// Whether any items failed recovery
  bool get hasFailedItems => failedItems > 0;

  /// Whether all items are valid (either originally or after recovery)
  bool get allItemsValid => failedItems == 0;

  /// Success rate as a percentage
  double get successRate =>
      totalItems > 0 ? (validItems + recoveredItems) / totalItems : 1.0;

  @override
  String toString() {
    return 'MediaValidationBatchResult(total: $totalItems, valid: $validItems, '
        'recovered: $recoveredItems, failed: $failedItems, '
        'success rate: ${(successRate * 100).toStringAsFixed(1)}%)';
  }
}

/// Configuration for media validation and recovery behavior
class MediaValidationConfig {
  /// Whether to attempt recovery for broken URIs
  final bool enableRecovery;

  /// Whether to update Firestore with recovered URIs
  final bool updateFirestore;

  /// Maximum time to spend on recovery attempts per URI
  final Duration maxRecoveryTime;

  /// Whether to enable verbose logging for debugging
  final bool verboseLogging;

  /// Whether to perform comprehensive cache refresh during recovery
  final bool enableCacheRefresh;

  /// Whether to use metadata birthprint matching
  final bool enableMetadataMatching;

  /// Minimum similarity score for metadata matches (0.0 to 1.0)
  final double metadataMatchThreshold;

  /// Whether to purge stale references from cache
  final bool enableStalePurging;

  const MediaValidationConfig({
    this.enableRecovery = true,
    this.updateFirestore = true,
    this.maxRecoveryTime = const Duration(seconds: 10),
    this.verboseLogging = kDebugMode,
    this.enableCacheRefresh = true,
    this.enableMetadataMatching = true,
    this.metadataMatchThreshold = 0.7,
    this.enableStalePurging = true,
  });

  /// Optimized configuration for production use
  static const MediaValidationConfig production = MediaValidationConfig(
    enableRecovery: true,
    updateFirestore: true,
    maxRecoveryTime: Duration(seconds: 5),
    verboseLogging: false,
    enableCacheRefresh: false,
    enableMetadataMatching: true,
    metadataMatchThreshold: 0.8,
    enableStalePurging: true,
  );

  /// Enhanced configuration for development/debug use
  static const MediaValidationConfig debug = MediaValidationConfig(
    enableRecovery: true,
    updateFirestore: true,
    maxRecoveryTime: Duration(seconds: 15),
    verboseLogging: true,
    enableCacheRefresh: true,
    enableMetadataMatching: true,
    metadataMatchThreshold: 0.6,
    enableStalePurging: true,
  );
}

/// Represents cached information about a directory's media files
class DirectoryCache {
  final String directoryPath;
  final List<MediaFileInfo> mediaFiles;
  final DateTime lastScanned;
  final int fileCount;

  const DirectoryCache({
    required this.directoryPath,
    required this.mediaFiles,
    required this.lastScanned,
    required this.fileCount,
  });

  /// Whether this cache entry is still valid (not expired)
  bool get isValid {
    const maxAge = Duration(hours: 6); // Cache valid for 6 hours
    return DateTime.now().difference(lastScanned) < maxAge;
  }

  /// Gets files that match a specific pattern
  List<MediaFileInfo> getFilesMatching(bool Function(MediaFileInfo) predicate) {
    return mediaFiles.where(predicate).toList();
  }

  /// Gets files by extension
  List<MediaFileInfo> getFilesByExtension(String extension) {
    return mediaFiles
        .where((f) => f.extension.toLowerCase() == extension.toLowerCase())
        .toList();
  }

  @override
  String toString() {
    return 'DirectoryCache(path: $directoryPath, files: $fileCount, lastScanned: $lastScanned)';
  }
}

/// Comprehensive information about a media file for the unified cache system
class MediaFileInfo {
  final String filePath;
  final String fileName;
  final String fileUri;
  final String mimeType;
  final int fileSize;
  final DateTime lastModified;
  final String extension;

  // Metadata fields (populated by enrichWithMetadata)
  DateTime? creationDate;
  double? latitude;
  double? longitude;
  String? locationName;
  String? city;
  String? country;
  int? width;
  int? height;
  double? duration;
  int? orientation;

  MediaFileInfo({
    required this.filePath,
    required this.fileName,
    required this.fileUri,
    required this.mimeType,
    required this.fileSize,
    required this.lastModified,
    required this.extension,
    this.creationDate,
    this.latitude,
    this.longitude,
    this.locationName,
    this.city,
    this.country,
    this.width,
    this.height,
    this.duration,
    this.orientation,
  });

  /// Enriches this file info with metadata from MediaMetadataService
  void enrichWithMetadata(Map<String, dynamic> metadata) {
    try {
      // Date information
      final dateData = metadata['date_data'] as Map<String, dynamic>?;
      if (dateData != null) {
        if (dateData['creation_date'] != null) {
          creationDate = DateTime.tryParse(dateData['creation_date']);
        }
      }

      // Location information
      final locationData = metadata['location_data'] as Map<String, dynamic>?;
      if (locationData != null) {
        latitude = locationData['latitude']?.toDouble();
        longitude = locationData['longitude']?.toDouble();
        locationName = locationData['location_name']?.toString();
        city = locationData['city']?.toString();
        country = locationData['country']?.toString();
      }

      // Media dimensions and properties
      width = metadata['width']?.toInt();
      height = metadata['height']?.toInt();
      duration = metadata['duration']?.toDouble();
      orientation = metadata['orientation']?.toInt();
    } catch (e) {
      // Silently continue if metadata enrichment fails
    }
  }

  /// Converts this MediaFileInfo to the format expected by MediaMetadataService
  Map<String, dynamic> toMetadataServiceFormat() {
    return {
      'id': fileName,
      'file_uri': fileUri,
      'mime_type': mimeType,
      'file_size_bytes': fileSize,
      'creation_time':
          creationDate?.toIso8601String() ?? lastModified.toIso8601String(),
      'width': width ?? 0,
      'height': height ?? 0,
      'duration': duration ?? 0.0,
      'orientation': orientation ?? 1,
      'folder': filePath.substring(0, filePath.lastIndexOf('/')),
      'date_data': {
        'creation_date':
            creationDate?.toIso8601String() ?? lastModified.toIso8601String(),
        'year': (creationDate ?? lastModified).year,
        'month': (creationDate ?? lastModified).month,
        'weekday': (creationDate ?? lastModified).weekday,
      },
      'location_data': {
        'latitude': latitude,
        'longitude': longitude,
        'location_name': locationName,
        'city': city,
        'country': country,
      },
    };
  }

  /// Whether this file is an image
  bool get isImage => mimeType.startsWith('image/');

  /// Whether this file is a video
  bool get isVideo => mimeType.startsWith('video/');

  /// Gets a human-readable file size
  String get formattedFileSize {
    if (fileSize == 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var size = fileSize.toDouble();
    var suffixIndex = 0;

    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }

    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[suffixIndex]}';
  }

  @override
  String toString() {
    return 'MediaFileInfo(fileName: $fileName, mimeType: $mimeType, size: $formattedFileSize)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MediaFileInfo && other.filePath == filePath;
  }

  @override
  int get hashCode => filePath.hashCode;
}
