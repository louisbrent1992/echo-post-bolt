import 'package:json_annotation/json_annotation.dart';
import 'media_item.dart';

part 'content.g.dart';

@JsonSerializable()
class Content {
  final String text;
  final List<String> hashtags;
  final List<String> mentions;
  final String? link;
  final List<MediaItem> media;

  Content({
    required this.text,
    this.hashtags = const [],
    this.mentions = const [],
    this.link,
    this.media = const [],
  });

  factory Content.fromJson(Map<String, dynamic> json) =>
      _$ContentFromJson(json);
  Map<String, dynamic> toJson() => _$ContentToJson(this);
}
