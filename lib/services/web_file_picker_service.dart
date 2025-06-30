import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

/// Web-specific file picker service for media selection
class WebFilePickerService {
  /// Pick media files (images and videos) for web platform
  static Future<List<Map<String, dynamic>>> pickMediaFiles({
    bool allowMultiple = true,
    List<String>? allowedExtensions,
  }) async {
    try {
      if (!kIsWeb) {
        throw Exception(
            'WebFilePickerService can only be used on web platform');
      }

      if (kDebugMode) {
        print('🌐 Opening web file picker for media files...');
      }

      // Use file_picker package for web
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions ??
            [
              'jpg', 'jpeg', 'png', 'gif', 'webp', // Images
              'mp4', 'mov', 'avi', 'mkv', 'webm', // Videos
            ],
        allowMultiple: allowMultiple,
        withData: true, // Important for web - loads file data into memory
      );

      if (result == null) {
        if (kDebugMode) {
          print('🌐 File picker cancelled by user');
        }
        return [];
      }

      final List<Map<String, dynamic>> mediaFiles = [];

      for (final file in result.files) {
        if (file.bytes != null) {
          final mediaFile = await _processWebFile(file);
          if (mediaFile != null) {
            mediaFiles.add(mediaFile);
          }
        }
      }

      if (kDebugMode) {
        print('🌐 Successfully picked ${mediaFiles.length} media files');
      }

      return mediaFiles;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error picking media files: $e');
      }
      return [];
    }
  }

  /// Pick a single image file
  static Future<Map<String, dynamic>?> pickImageFile() async {
    final files = await pickMediaFiles(
      allowMultiple: false,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp'],
    );
    return files.isNotEmpty ? files.first : null;
  }

  /// Pick a single video file
  static Future<Map<String, dynamic>?> pickVideoFile() async {
    final files = await pickMediaFiles(
      allowMultiple: false,
      allowedExtensions: ['mp4', 'mov', 'avi', 'mkv', 'webm'],
    );
    return files.isNotEmpty ? files.first : null;
  }

  /// Process a picked file into our standard format
  static Future<Map<String, dynamic>?> _processWebFile(
      PlatformFile file) async {
    try {
      if (file.bytes == null || file.name.isEmpty) {
        return null;
      }

      final String mimeType = _getMimeType(file.name);
      final bool isVideo = mimeType.startsWith('video/');
      final bool isImage = mimeType.startsWith('image/');

      if (!isVideo && !isImage) {
        if (kDebugMode) {
          print('⚠️ Unsupported file type: ${file.name}');
        }
        return null;
      }

      // Create blob URL for the file
      final blob = html.Blob([file.bytes!], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);

      final mediaFile = {
        'id': 'web_${DateTime.now().millisecondsSinceEpoch}',
        'path': url, // Blob URL for web access
        'name': file.name,
        'size': file.size,
        'mime_type': mimeType,
        'type': isVideo ? 'video' : 'image',
        'extension': file.extension ?? _getExtensionFromName(file.name),
        'bytes': file.bytes, // Keep in memory for web
        'blob_url': url,
        'last_modified': DateTime.now().toIso8601String(),
        'is_web_file': true,
      };

      // Add additional metadata for videos
      if (isVideo) {
        mediaFile['duration'] = 0; // Will be determined when video loads
        mediaFile['width'] = 0;
        mediaFile['height'] = 0;
      }

      // Add additional metadata for images
      if (isImage) {
        final dimensions = await _getImageDimensions(url);
        mediaFile['width'] = dimensions['width'] ?? 0;
        mediaFile['height'] = dimensions['height'] ?? 0;
      }

      if (kDebugMode) {
        print(
            '🌐 Processed web file: ${file.name} (${_formatFileSize(file.size)})');
      }

      return mediaFile;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error processing web file ${file.name}: $e');
      }
      return null;
    }
  }

  /// Get MIME type from file extension
  static String _getMimeType(String fileName) {
    final extension = _getExtensionFromName(fileName).toLowerCase();

    switch (extension) {
      // Images
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';

      // Videos
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';

      default:
        return 'application/octet-stream';
    }
  }

  /// Get file extension from filename
  static String _getExtensionFromName(String fileName) {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last : '';
  }

  /// Get image dimensions using HTML Image element
  static Future<Map<String, int>> _getImageDimensions(String url) async {
    try {
      final completer = Completer<Map<String, int>>();
      final img = html.ImageElement();

      img.onLoad.listen((_) {
        completer.complete({
          'width': img.naturalWidth,
          'height': img.naturalHeight,
        });
      });

      img.onError.listen((_) {
        completer.complete({'width': 0, 'height': 0});
      });

      img.src = url;

      return await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => {'width': 0, 'height': 0},
      );
    } catch (e) {
      return {'width': 0, 'height': 0};
    }
  }

  /// Format file size for display
  static String _formatFileSize(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var suffixIndex = 0;

    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }

    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[suffixIndex]}';
  }

  /// Clean up blob URLs to prevent memory leaks
  static void cleanupBlobUrl(String url) {
    if (url.startsWith('blob:')) {
      html.Url.revokeObjectUrl(url);
    }
  }

  /// Check if the current platform supports file picker
  static bool get isSupported => kIsWeb;

  /// Get supported file types for web
  static List<String> get supportedImageTypes =>
      ['jpg', 'jpeg', 'png', 'gif', 'webp'];
  static List<String> get supportedVideoTypes =>
      ['mp4', 'mov', 'avi', 'mkv', 'webm'];
  static List<String> get supportedMediaTypes =>
      [...supportedImageTypes, ...supportedVideoTypes];
}
