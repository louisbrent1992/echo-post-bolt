import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';

part 'social_action.g.dart';

@JsonSerializable(explicitToJson: true)
class SocialAction {
  final String action_id;
  final String created_at;
  final List<String> platforms;
  final Content content;
  final Options options;
  final PlatformData platform_data;
  final Internal internal;

  SocialAction({
    String? action_id,
    String? created_at,
    required this.platforms,
    required this.content,
    required this.options,
    required this.platform_data,
    required this.internal,
  })  : action_id = action_id ?? const Uuid().v4(),
        created_at = created_at ?? DateTime.now().toIso8601String();

  factory SocialAction.fromJson(Map<String, dynamic> json) =>
      _$SocialActionFromJson(json);

  Map<String, dynamic> toJson() => _$SocialActionToJson(this);
}

@JsonSerializable(explicitToJson: true)
class Content {
  final String text;
  final List<String> hashtags;
  final List<String> mentions;
  final Link? link;
  final List<MediaItem> media;

  Content({
    required this.text,
    required this.hashtags,
    required this.mentions,
    this.link,
    required this.media,
  });

  factory Content.fromJson(Map<String, dynamic> json) =>
      _$ContentFromJson(json);

  Map<String, dynamic> toJson() => _$ContentToJson(this);
}

@JsonSerializable()
class Link {
  final String url;
  final String? title;
  final String? description;
  final String? thumbnail_url;

  Link({
    required this.url,
    this.title,
    this.description,
    this.thumbnail_url,
  });

  factory Link.fromJson(Map<String, dynamic> json) => _$LinkFromJson(json);

  Map<String, dynamic> toJson() => _$LinkToJson(this);
}

@JsonSerializable(explicitToJson: true)
class MediaItem {
  final String fileUri;
  final String mimeType;
  final DeviceMetadata deviceMetadata;
  final String? uploadUrl;
  final String? cdnKey;
  final String? caption;

  MediaItem({
    required this.fileUri,
    required this.mimeType,
    required this.deviceMetadata,
    this.uploadUrl,
    this.cdnKey,
    this.caption,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) =>
      _$MediaItemFromJson(json);

  Map<String, dynamic> toJson() => _$MediaItemToJson(this);
}

@JsonSerializable()
class DeviceMetadata {
  final String creationTime;
  final double? latitude;
  final double? longitude;
  final int orientation;
  final int width;
  final int height;
  final int fileSizeBytes;

  DeviceMetadata({
    required this.creationTime,
    this.latitude,
    this.longitude,
    required this.orientation,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
  });

  factory DeviceMetadata.fromJson(Map<String, dynamic> json) =>
      _$DeviceMetadataFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceMetadataToJson(this);
}

@JsonSerializable(explicitToJson: true)
class Options {
  final String schedule;
  final LocationTag? locationTag;
  final Map<String, String?>? visibility;
  final Map<String, String?>? replyToPostId;

  Options({
    required this.schedule,
    this.locationTag,
    this.visibility,
    this.replyToPostId,
  });

  factory Options.fromJson(Map<String, dynamic> json) =>
      _$OptionsFromJson(json);

  Map<String, dynamic> toJson() => _$OptionsToJson(this);
}

@JsonSerializable()
class LocationTag {
  final String name;
  final double latitude;
  final double longitude;

  LocationTag({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  factory LocationTag.fromJson(Map<String, dynamic> json) =>
      _$LocationTagFromJson(json);

  Map<String, dynamic> toJson() => _$LocationTagToJson(this);
}

@JsonSerializable(explicitToJson: true)
class PlatformData {
  final FacebookData? facebook;
  final InstagramData? instagram;
  final TwitterData? twitter;
  final TikTokData? tiktok;

  PlatformData({
    this.facebook,
    this.instagram,
    this.twitter,
    this.tiktok,
  });

  factory PlatformData.fromJson(Map<String, dynamic> json) =>
      _$PlatformDataFromJson(json);

  Map<String, dynamic> toJson() => _$PlatformDataToJson(this);
}

@JsonSerializable()
class FacebookData {
  final bool postAsPage;
  final String pageId;
  final Map<String, dynamic>? additionalFields;

  FacebookData({
    required this.postAsPage,
    required this.pageId,
    this.additionalFields,
  });

  factory FacebookData.fromJson(Map<String, dynamic> json) =>
      _$FacebookDataFromJson(json);

  Map<String, dynamic> toJson() => _$FacebookDataToJson(this);
}

@JsonSerializable(explicitToJson: true)
class InstagramData {
  final String postType;
  final Carousel? carousel;
  final String igUserId;

  InstagramData({
    required this.postType,
    this.carousel,
    required this.igUserId,
  });

  factory InstagramData.fromJson(Map<String, dynamic> json) =>
      _$InstagramDataFromJson(json);

  Map<String, dynamic> toJson() => _$InstagramDataToJson(this);
}

@JsonSerializable()
class Carousel {
  final bool enabled;
  final List<int>? order;

  Carousel({
    required this.enabled,
    this.order,
  });

  factory Carousel.fromJson(Map<String, dynamic> json) =>
      _$CarouselFromJson(json);

  Map<String, dynamic> toJson() => _$CarouselToJson(this);
}

@JsonSerializable()
class TwitterData {
  final List<String> altTexts;
  final String tweetMode;

  TwitterData({
    required this.altTexts,
    required this.tweetMode,
  });

  factory TwitterData.fromJson(Map<String, dynamic> json) =>
      _$TwitterDataFromJson(json);

  Map<String, dynamic> toJson() => _$TwitterDataToJson(this);
}

@JsonSerializable(explicitToJson: true)
class TikTokData {
  final String privacy;
  final Sound sound;

  TikTokData({
    required this.privacy,
    required this.sound,
  });

  factory TikTokData.fromJson(Map<String, dynamic> json) =>
      _$TikTokDataFromJson(json);

  Map<String, dynamic> toJson() => _$TikTokDataToJson(this);
}

@JsonSerializable()
class Sound {
  final bool useOriginalSound;
  final String? musicId;

  Sound({
    required this.useOriginalSound,
    this.musicId,
  });

  factory Sound.fromJson(Map<String, dynamic> json) => _$SoundFromJson(json);

  Map<String, dynamic> toJson() => _$SoundToJson(this);
}

@JsonSerializable(explicitToJson: true)
class Internal {
  final int retryCount;
  final UserPreferences userPreferences;
  final String? mediaIndexId;
  final UiFlags uiFlags;

  Internal({
    required this.retryCount,
    required this.userPreferences,
    this.mediaIndexId,
    required this.uiFlags,
  });

  factory Internal.fromJson(Map<String, dynamic> json) =>
      _$InternalFromJson(json);

  Map<String, dynamic> toJson() => _$InternalToJson(this);
}

@JsonSerializable()
class UserPreferences {
  final List<String> defaultPlatforms;
  final List<String> defaultHashtags;

  UserPreferences({
    required this.defaultPlatforms,
    required this.defaultHashtags,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      _$UserPreferencesFromJson(json);

  Map<String, dynamic> toJson() => _$UserPreferencesToJson(this);
}

@JsonSerializable()
class UiFlags {
  final bool isEditingCaption;
  final bool isMediaPreviewOpen;

  UiFlags({
    required this.isEditingCaption,
    required this.isMediaPreviewOpen,
  });

  factory UiFlags.fromJson(Map<String, dynamic> json) =>
      _$UiFlagsFromJson(json);

  Map<String, dynamic> toJson() => _$UiFlagsToJson(this);
}