// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MediaItem _$MediaItemFromJson(Map<String, dynamic> json) => MediaItem(
      fileUri: json['file_uri'] as String,
      mimeType: json['mime_type'] as String,
      deviceMetadata: DeviceMetadata.fromJson(
          json['device_metadata'] as Map<String, dynamic>),
      caption: json['caption'] as String?,
    );

Map<String, dynamic> _$MediaItemToJson(MediaItem instance) => <String, dynamic>{
      'file_uri': instance.fileUri,
      'mime_type': instance.mimeType,
      'device_metadata': instance.deviceMetadata,
      'caption': instance.caption,
    };
