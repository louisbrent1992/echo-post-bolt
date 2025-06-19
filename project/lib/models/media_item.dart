import 'package:json_annotation/json_annotation.dart';
import 'device_metadata.dart';

part 'media_item.g.dart';

@JsonSerializable()
class MediaItem {
  @JsonKey(name: 'file_uri')
  final String fileUri;

  @JsonKey(name: 'mime_type')
  final String mimeType;

  @JsonKey(name: 'device_metadata')
  final DeviceMetadata deviceMetadata;

  final String? caption;

  MediaItem({
    required this.fileUri,
    required this.mimeType,
    required this.deviceMetadata,
    this.caption,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) =>
      _$MediaItemFromJson(json);
  Map<String, dynamic> toJson() => _$MediaItemToJson(this);
}
