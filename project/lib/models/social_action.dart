import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';

part 'social_action.g.dart';

@JsonSerializable(explicitToJson: true)
class SocialAction {
  @JsonKey(name: 'action_id')
  final String actionId;
  @JsonKey(name: 'created_at')
  final String createdAt;
  final List<String> platforms;
  final Content content;
  final Options options;
  @JsonKey(name: 'platform_data')
  final PlatformData platformData;
  final Internal internal;

  SocialAction({
    String? actionId,
    String? createdAt,
    required this.platforms,
    required this.content,
    required this.options,
    required this.platformData,
    required this.internal,
  })  : actionId = actionId ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now().toIso8601String();

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
    this.hashtags = const [],
    this.mentions = const [],
    this.link,
    this.media = const [],
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
  @JsonKey(name: 'thumbnail_url')
  final String? thumbnailUrl;

  Link({
    required this.url,
    this.title,
    this.description,
    this.thumbnailUrl,
  });

  factory Link.fromJson(Map<String, dynamic> json) => _$LinkFromJson(json);

  Map<String, dynamic> toJson() => _$LinkToJson(this);
}

@JsonSerializable(explicitToJson: true)
class MediaItem {
  @JsonKey(name: 'file_uri')
  final String fileUri;
  @JsonKey(name: 'mime_type')
  final String mimeType;
  @JsonKey(name: 'device_metadata')
  final DeviceMetadata deviceMetadata;
  @JsonKey(name: 'upload_url')
  final String? uploadUrl;
  @JsonKey(name: 'cdn_key')
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
  @JsonKey(name: 'creation_time')
  final String creationTime;
  final double? latitude;
  final double? longitude;
  final int orientation;
  final int width;
  final int height;
  @JsonKey(name: 'file_size_bytes')
  final int fileSizeBytes;

  DeviceMetadata({
    required this.creationTime,
    this.latitude,
    this.longitude,
    this.orientation = 1,
    this.width = 0,
    this.height = 0,
    this.fileSizeBytes = 0,
  });

  factory DeviceMetadata.fromJson(Map<String, dynamic> json) =>
      _$DeviceMetadataFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceMetadataToJson(this);
}

@JsonSerializable(explicitToJson: true)
class Options {
  final String schedule;
  @JsonKey(name: 'location_tag')
  final LocationTag? locationTag;
  final Map<String, String?>? visibility;
  @JsonKey(name: 'reply_to_post_id')
  final Map<String, String?>? replyToPostId;

  Options({
    this.schedule = 'now',
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
  @JsonKey(name: 'post_as_page')
  final bool postAsPage;
  @JsonKey(name: 'page_id')
  final String pageId;
  @JsonKey(name: 'additional_fields')
  final Map<String, dynamic>? additionalFields;

  FacebookData({
    this.postAsPage = false,
    this.pageId = '',
    this.additionalFields,
  });

  factory FacebookData.fromJson(Map<String, dynamic> json) =>
      _$FacebookDataFromJson(json);

  Map<String, dynamic> toJson() => _$FacebookDataToJson(this);
}

@JsonSerializable(explicitToJson: true)
class InstagramData {
  @JsonKey(name: 'post_type')
  final String postType;
  final Carousel? carousel;
  @JsonKey(name: 'ig_user_id')
  final String igUserId;

  InstagramData({
    this.postType = 'feed',
    this.carousel,
    this.igUserId = '',
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
    this.enabled = false,
    this.order,
  });

  factory Carousel.fromJson(Map<String, dynamic> json) =>
      _$CarouselFromJson(json);

  Map<String, dynamic> toJson() => _$CarouselToJson(this);
}

@JsonSerializable()
class TwitterData {
  @JsonKey(name: 'alt_texts')
  final List<String> altTexts;
  @JsonKey(name: 'tweet_mode')
  final String tweetMode;

  TwitterData({
    this.altTexts = const [],
    this.tweetMode = 'extended',
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
    this.privacy = 'public',
    required this.sound,
  });

  factory TikTokData.fromJson(Map<String, dynamic> json) =>
      _$TikTokDataFromJson(json);

  Map<String, dynamic> toJson() => _$TikTokDataToJson(this);
}

@JsonSerializable()
class Sound {
  @JsonKey(name: 'use_original_sound')
  final bool useOriginalSound;
  @JsonKey(name: 'music_id')
  final String? musicId;

  Sound({
    this.useOriginalSound = true,
    this.musicId,
  });

  factory Sound.fromJson(Map<String, dynamic> json) => _$SoundFromJson(json);

  Map<String, dynamic> toJson() => _$SoundToJson(this);
}

@JsonSerializable(explicitToJson: true)
class Internal {
  @JsonKey(name: 'retry_count')
  final int retryCount;
  @JsonKey(name: 'user_preferences')
  final UserPreferences userPreferences;
  @JsonKey(name: 'media_index_id')
  final String? mediaIndexId;
  @JsonKey(name: 'ui_flags')
  final UiFlags uiFlags;

  Internal({
    this.retryCount = 0,
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
  @JsonKey(name: 'default_platforms')
  final List<String> defaultPlatforms;
  @JsonKey(name: 'default_hashtags')
  final List<String> defaultHashtags;

  UserPreferences({
    this.defaultPlatforms = const [],
    this.defaultHashtags = const [],
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      _$UserPreferencesFromJson(json);

  Map<String, dynamic> toJson() => _$UserPreferencesToJson(this);
}

@JsonSerializable()
class UiFlags {
  @JsonKey(name: 'is_editing_caption')
  final bool isEditingCaption;
  @JsonKey(name: 'is_media_preview_open')
  final bool isMediaPreviewOpen;

  UiFlags({
    this.isEditingCaption = false,
    this.isMediaPreviewOpen = false,
  });

  factory UiFlags.fromJson(Map<String, dynamic> json) =>
      _$UiFlagsFromJson(json);

  Map<String, dynamic> toJson() => _$UiFlagsToJson(this);
}
