// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceMetadata _$DeviceMetadataFromJson(Map<String, dynamic> json) =>
    DeviceMetadata(
      creationTime: json['creation_time'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      orientation: (json['orientation'] as num?)?.toInt() ?? 1,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toDouble(),
      bitrate: (json['bitrate'] as num?)?.toInt(),
      samplingRate: (json['sampling_rate'] as num?)?.toInt(),
      frameRate: (json['frame_rate'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$DeviceMetadataToJson(DeviceMetadata instance) =>
    <String, dynamic>{
      'creation_time': instance.creationTime,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'orientation': instance.orientation,
      'width': instance.width,
      'height': instance.height,
      'file_size_bytes': instance.fileSizeBytes,
      'duration': instance.duration,
      'bitrate': instance.bitrate,
      'sampling_rate': instance.samplingRate,
      'frame_rate': instance.frameRate,
    };
