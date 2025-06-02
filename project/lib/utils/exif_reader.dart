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
        final latValues = exifData['GPS GPSLatitude']!.values as List<Rational>;
        final latRef = exifData['GPS GPSLatitudeRef']!.printable;
        
        latitude = _convertDMSToDecimal(
          latValues[0].toDouble(),
          latValues[1].toDouble(),
          latValues[2].toDouble(),
          latRef == 'S',
        );
      } catch (e) {
        print('Error parsing latitude: $e');
      }
    }
    
    if (exifData.containsKey('GPS GPSLongitude') && 
        exifData.containsKey('GPS GPSLongitudeRef')) {
      try {
        final lngValues = exifData['GPS GPSLongitude']!.values as List<Rational>;
        final lngRef = exifData['GPS GPSLongitudeRef']!.printable;
        
        longitude = _convertDMSToDecimal(
          lngValues[0].toDouble(),
          lngValues[1].toDouble(),
          lngValues[2].toDouble(),
          lngRef == 'W',
        );
      } catch (e) {
        print('Error parsing longitude: $e');
      }
    }
    
    if (latitude != null) metadata['latitude'] = latitude;
    if (longitude != null) metadata['longitude'] = longitude;
    
    // Extract orientation
    if (exifData.containsKey('Image Orientation')) {
      try {
        metadata['orientation'] = exifData['Image Orientation']!.values[0];
      } catch (e) {
        metadata['orientation'] = 1; // Default orientation
      }
    } else {
      metadata['orientation'] = 1; // Default orientation
    }
    
    return metadata;
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