import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';
import 'media_query.dart';

part 'social_action.g.dart';

/// EchoPost Social Action Data Models
///
/// This file defines the complete data structure for social media posts in EchoPost.
/// The models support posting images, videos (MP4/MOV), and audio (MP3/WAV) to
/// Facebook, Instagram, Twitter, and TikTok.
///
/// PLATFORM-SPECIFIC POSTING GUIDELINES:
///
/// Facebook:
/// - For video posts: Set facebook.postType = 'video', include mediaItem.mimeType = 'video/mp4',
///   and pass mediaItem.fileUri to the Graph API endpoint
/// - For images: Set facebook.postType = 'photo', use mediaItem.mimeType = 'image/jpeg'
/// - For links: Set facebook.postType = 'link', populate content.link object
///
/// Instagram:
/// - For feed posts: Set instagram.postType = 'feed', instagram.mediaType = 'image'/'video'
/// - For stories: Set instagram.postType = 'story'
/// - For reels: Set instagram.postType = 'reel', use video media
/// - Audio content: Convert to video with waveform visualization for instagram.audioFileUri
///
/// Twitter:
/// - For media posts: Set twitter.mediaType = 'image'/'video'/'audio'
/// - For video: Include twitter.mediaDuration
/// - For audio: Use twitter.tweetLink to link to hosted audio file
/// - Always provide twitter.altTexts for accessibility
///
/// TikTok:
/// - For video posts: Use tiktok.videoFileUri with video/mp4 format
/// - For audio clips: Use tiktok.audioFileUri (may need conversion to video)
///
/// MEDIA TYPE SUPPORT:
/// - Images: image/jpeg, image/png
/// - Videos: video/mp4, video/quicktime
/// - Audio: audio/mpeg (recommended for .mp3), audio/wav
///
/// Note: When recording with the record package, default to .mp3 (audio/mpeg)
/// for optimal speed/size, but .wav is also supported.

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
  @JsonKey(name: 'media_query')
  final MediaSearchQuery? mediaQuery;

  SocialAction({
    String? actionId,
    String? createdAt,
    required this.platforms,
    required this.content,
    required this.options,
    required this.platformData,
    required this.internal,
    this.mediaQuery,
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
  final String
      mimeType; // Supports image/jpeg, image/png, video/mp4, video/quicktime, audio/mpeg, audio/wav, etc.
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
  // Extended metadata for video and audio files
  final double? duration; // Duration in seconds for video/audio
  final int? bitrate; // Bitrate in kbps for video/audio
  @JsonKey(name: 'sampling_rate')
  final int? samplingRate; // Sampling rate in Hz for audio
  @JsonKey(name: 'frame_rate')
  final double? frameRate; // Frame rate for video

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

/// FacebookData: Enhanced for different post types and media formats
/// Usage: When posting to Facebook as video, set postType = 'video',
/// include mediaItem.mimeType = 'video/mp4', and pass mediaItem.fileUri to the Graph API endpoint
@JsonSerializable()
class FacebookData {
  @JsonKey(name: 'post_here')
  final bool postHere;
  @JsonKey(name: 'post_as_page')
  final bool postAsPage;
  @JsonKey(name: 'page_id')
  final String pageId;
  @JsonKey(name: 'post_type')
  final String? postType; // 'photo', 'video', 'link', 'status'
  @JsonKey(name: 'media_file_uri')
  final String? mediaFileUri; // local file URI or URL for primary media
  @JsonKey(name: 'video_file_uri')
  final String? videoFileUri; // For video posts (legacy, use mediaFileUri)
  @JsonKey(name: 'audio_file_uri')
  final String? audioFileUri; // For audio posts (if supported)
  @JsonKey(name: 'thumbnail_uri')
  final String? thumbnailUri; // Video thumbnail
  @JsonKey(name: 'scheduled_time')
  final String? scheduledTime; // ISO timestamp for scheduled posts
  @JsonKey(name: 'additional_fields')
  final Map<String, dynamic>? additionalFields;

  FacebookData({
    this.postHere = false,
    this.postAsPage = false,
    this.pageId = '',
    this.postType,
    this.mediaFileUri,
    this.videoFileUri,
    this.audioFileUri,
    this.thumbnailUri,
    this.scheduledTime,
    this.additionalFields,
  });

  factory FacebookData.fromJson(Map<String, dynamic> json) =>
      _$FacebookDataFromJson(json);

  Map<String, dynamic> toJson() => _$FacebookDataToJson(this);
}

/// InstagramData: Enhanced for different post types and media formats
/// Supports story vs feed vs reel, carousel (multiple images), and video metadata
@JsonSerializable(explicitToJson: true)
class InstagramData {
  @JsonKey(name: 'post_here')
  final bool postHere;
  @JsonKey(name: 'post_type')
  final String? postType; // 'feed', 'story', 'reel'
  final Carousel? carousel;
  @JsonKey(name: 'ig_user_id')
  final String igUserId;
  @JsonKey(name: 'media_type')
  final String? mediaType; // 'image', 'video', 'carousel'
  @JsonKey(name: 'media_file_uri')
  final String? mediaFileUri; // local file URI or URL for primary media
  @JsonKey(name: 'video_thumbnail_uri')
  final String? videoThumbnailUri; // For video posts
  @JsonKey(name: 'video_file_uri')
  final String? videoFileUri; // For video posts (legacy, use mediaFileUri)
  @JsonKey(name: 'audio_file_uri')
  final String? audioFileUri; // For audio content (converted to video)
  @JsonKey(name: 'scheduled_time')
  final String? scheduledTime; // ISO timestamp for scheduled posts

  InstagramData({
    this.postHere = false,
    this.postType,
    this.carousel,
    this.igUserId = '',
    this.mediaType,
    this.mediaFileUri,
    this.videoThumbnailUri,
    this.videoFileUri,
    this.audioFileUri,
    this.scheduledTime,
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

/// TwitterData: Enhanced with media type support and link posting
/// Supports alt texts for accessibility and different media types
@JsonSerializable()
class TwitterData {
  @JsonKey(name: 'post_here')
  final bool postHere;
  @JsonKey(name: 'alt_texts')
  final List<String> altTexts;
  @JsonKey(name: 'tweet_mode')
  final String tweetMode;
  @JsonKey(name: 'media_type')
  final String? mediaType; // 'image', 'video', 'audio'
  @JsonKey(name: 'media_file_uri')
  final String? mediaFileUri; // local file URI or URL for primary media
  @JsonKey(name: 'media_duration')
  final double? mediaDuration; // Duration for video/audio in seconds
  @JsonKey(name: 'tweet_link')
  final String? tweetLink; // For posting links to audio/external content
  @JsonKey(name: 'scheduled_time')
  final String? scheduledTime; // ISO timestamp for scheduled posts

  TwitterData({
    this.postHere = false,
    this.altTexts = const [],
    this.tweetMode = 'extended',
    this.mediaType,
    this.mediaFileUri,
    this.mediaDuration,
    this.tweetLink,
    this.scheduledTime,
  });

  factory TwitterData.fromJson(Map<String, dynamic> json) =>
      _$TwitterDataFromJson(json);

  Map<String, dynamic> toJson() => _$TwitterDataToJson(this);
}

/// TikTokData: Enhanced for video and audio content
/// Supports both video posts and audio clips
@JsonSerializable(explicitToJson: true)
class TikTokData {
  @JsonKey(name: 'post_here')
  final bool postHere;
  final String privacy;
  final Sound sound;
  @JsonKey(name: 'media_file_uri')
  final String? mediaFileUri; // local file URI or URL for primary media
  @JsonKey(name: 'video_file_uri')
  final String? videoFileUri; // For video posts (legacy, use mediaFileUri)
  @JsonKey(name: 'audio_file_uri')
  final String? audioFileUri; // For audio clips
  @JsonKey(name: 'scheduled_time')
  final String? scheduledTime; // ISO timestamp for scheduled posts

  TikTokData({
    this.postHere = false,
    this.privacy = 'public',
    required this.sound,
    this.mediaFileUri,
    this.videoFileUri,
    this.audioFileUri,
    this.scheduledTime,
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

/// Internal: Enhanced with AI metadata fields for tracking AI-generated content
/// Tracks whether content was generated by ChatGPT, original transcription, and fallback reasons
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
  @JsonKey(name: 'ai_generated')
  final bool aiGenerated;
  @JsonKey(name: 'original_transcription')
  final String originalTranscription;
  @JsonKey(name: 'fallback_reason')
  final String? fallbackReason;

  Internal({
    this.retryCount = 0,
    UserPreferences? userPreferences,
    this.mediaIndexId,
    UiFlags? uiFlags,
    this.aiGenerated = false,
    this.originalTranscription = '',
    this.fallbackReason,
  })  : userPreferences = userPreferences ?? UserPreferences(),
        uiFlags = uiFlags ?? UiFlags();

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
