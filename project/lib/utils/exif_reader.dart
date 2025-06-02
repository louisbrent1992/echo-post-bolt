import 'dart:io';
import 'package:exif/exif.dart';

class ExifReader {
  // Read EXIF data from a file
  static Future<Map<String, dynamic>> readExifFromFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final exifData = await readExifFromBytes(bytes);

      return _extractMetadata(exifData);
    } catch (e) {
      print('Error reading EXIF data: $e');
      return {};
    }
  }

  // Extract relevant metadata from EXIF tags
  static Map<String, dynamic> _extractMetadata(Map<String, IfdTag> exifData) {
    final metadata = <String, dynamic>{};

    // Extract creation time
    if (exifData.containsKey('EXIF DateTimeOriginal')) {
      final dateTimeStr = exifData['EXIF DateTimeOriginal']!.printable;
      try {
        // EXIF date format: 'YYYY:MM:DD HH:MM:SS'
        final parts = dateTimeStr.split(' ');
        final dateParts = parts[0].split(':');
        final timeParts = parts[1].split(':');

        final dateTime = DateTime(
          int.parse(dateParts[0]),
          int.parse(dateParts[1]),
          int.parse(dateParts[2]),
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
          int.parse(timeParts[2]),
        );

        metadata['creation_time'] = dateTime.toIso8601String();
      } catch (e) {
        print('Error parsing EXIF date: $e');
      }
    }

    // Extract GPS coordinates
    double? latitude;
    double? longitude;

    if (exifData.containsKey('GPS GPSLatitude') &&
        exifData.containsKey('GPS GPSLatitudeRef')) {
      try {
        final latTag = exifData['GPS GPSLatitude']!;
        final latRef = exifData['GPS GPSLatitudeRef']!.printable;

        // Handle different value types for GPS coordinates
        if (latTag.values is List && (latTag.values as List).length >= 3) {
          final values = latTag.values as List;
          final degrees = _extractNumericValue(values[0]);
          final minutes = _extractNumericValue(values[1]);
          final seconds = _extractNumericValue(values[2]);

          latitude =
              _convertDMSToDecimal(degrees, minutes, seconds, latRef == 'S');
        }
      } catch (e) {
        print('Error parsing latitude: $e');
      }
    }

    if (exifData.containsKey('GPS GPSLongitude') &&
        exifData.containsKey('GPS GPSLongitudeRef')) {
      try {
        final lngTag = exifData['GPS GPSLongitude']!;
        final lngRef = exifData['GPS GPSLongitudeRef']!.printable;

        // Handle different value types for GPS coordinates
        if (lngTag.values is List && (lngTag.values as List).length >= 3) {
          final values = lngTag.values as List;
          final degrees = _extractNumericValue(values[0]);
          final minutes = _extractNumericValue(values[1]);
          final seconds = _extractNumericValue(values[2]);

          longitude =
              _convertDMSToDecimal(degrees, minutes, seconds, lngRef == 'W');
        }
      } catch (e) {
        print('Error parsing longitude: $e');
      }
    }

    if (latitude != null) metadata['latitude'] = latitude;
    if (longitude != null) metadata['longitude'] = longitude;

    // Extract orientation
    if (exifData.containsKey('Image Orientation')) {
      try {
        final orientationTag = exifData['Image Orientation']!;
        if (orientationTag.values is List &&
            (orientationTag.values as List).isNotEmpty) {
          metadata['orientation'] = (orientationTag.values as List)[0];
        } else {
          metadata['orientation'] = 1; // Default orientation
        }
      } catch (e) {
        metadata['orientation'] = 1; // Default orientation
      }
    } else {
      metadata['orientation'] = 1; // Default orientation
    }

    return metadata;
  }

  // Extract numeric value from different EXIF value types
  static double _extractNumericValue(dynamic value) {
    if (value is num) {
      return value.toDouble();
    } else if (value is String) {
      return double.tryParse(value) ?? 0.0;
    } else {
      // Handle Rational or other types by calling toDouble() if available
      try {
        return (value as dynamic).toDouble();
      } catch (e) {
        return 0.0;
      }
    }
  }

  // Convert degrees, minutes, seconds to decimal degrees
  static double _convertDMSToDecimal(
    double degrees,
    double minutes,
    double seconds,
    bool isNegative,
  ) {
    double decimal = degrees + (minutes / 60) + (seconds / 3600);
    return isNegative ? -decimal : decimal;
  }
}
