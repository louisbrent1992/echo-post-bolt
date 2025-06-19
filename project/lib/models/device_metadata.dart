import 'package:json_annotation/json_annotation.dart';

part 'device_metadata.g.dart';

@JsonSerializable()
class DeviceMetadata {
  @JsonKey(name: 'creation_time')
  final String creationTime;

  final double? latitude;
  final double? longitude;
  final int orientation;
  final int width;
  final int height;

  @JsonKey(name: 'file_size_bytes')
  final int fileSizeBytes;

  final double? duration;
  final int? bitrate;

  @JsonKey(name: 'sampling_rate')
  final int? samplingRate;

  @JsonKey(name: 'frame_rate')
  final double? frameRate;

  DeviceMetadata({
    required this.creationTime,
    this.latitude,
    this.longitude,
    this.orientation = 1,
    this.width = 0,
    this.height = 0,
    this.fileSizeBytes = 0,
    this.duration,
    this.bitrate,
    this.samplingRate,
    this.frameRate,
  });

  factory DeviceMetadata.fromJson(Map<String, dynamic> json) =>
      _$DeviceMetadataFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceMetadataToJson(this);
}
