// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'social_action.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SocialAction _$SocialActionFromJson(Map<String, dynamic> json) => SocialAction(
      actionId: json['action_id'] as String?,
      createdAt: json['created_at'] as String?,
      platforms:
          (json['platforms'] as List<dynamic>).map((e) => e as String).toList(),
      content: Content.fromJson(json['content'] as Map<String, dynamic>),
      options: Options.fromJson(json['options'] as Map<String, dynamic>),
      platformData:
          PlatformData.fromJson(json['platform_data'] as Map<String, dynamic>),
      internal: Internal.fromJson(json['internal'] as Map<String, dynamic>),
      mediaQuery: json['media_query'] == null
          ? null
          : MediaSearchQuery.fromJson(
              json['media_query'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$SocialActionToJson(SocialAction instance) =>
    <String, dynamic>{
      'action_id': instance.actionId,
      'created_at': instance.createdAt,
      'platforms': instance.platforms,
      'content': instance.content.toJson(),
      'options': instance.options.toJson(),
      'platform_data': instance.platformData.toJson(),
      'internal': instance.internal.toJson(),
      'media_query': instance.mediaQuery?.toJson(),
    };

Content _$ContentFromJson(Map<String, dynamic> json) => Content(
      text: json['text'] as String,
      hashtags: (json['hashtags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      mentions: (json['mentions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      link: json['link'] == null
          ? null
          : Link.fromJson(json['link'] as Map<String, dynamic>),
      media: (json['media'] as List<dynamic>?)
              ?.map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$ContentToJson(Content instance) => <String, dynamic>{
      'text': instance.text,
      'hashtags': instance.hashtags,
      'mentions': instance.mentions,
      'link': instance.link?.toJson(),
      'media': instance.media.map((e) => e.toJson()).toList(),
    };

Link _$LinkFromJson(Map<String, dynamic> json) => Link(
      url: json['url'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
    );

Map<String, dynamic> _$LinkToJson(Link instance) => <String, dynamic>{
      'url': instance.url,
      'title': instance.title,
      'description': instance.description,
      'thumbnail_url': instance.thumbnailUrl,
    };

MediaItem _$MediaItemFromJson(Map<String, dynamic> json) => MediaItem(
      fileUri: json['file_uri'] as String,
      mimeType: json['mime_type'] as String,
      deviceMetadata: DeviceMetadata.fromJson(
          json['device_metadata'] as Map<String, dynamic>),
      uploadUrl: json['upload_url'] as String?,
      cdnKey: json['cdn_key'] as String?,
      caption: json['caption'] as String?,
    );

Map<String, dynamic> _$MediaItemToJson(MediaItem instance) => <String, dynamic>{
      'file_uri': instance.fileUri,
      'mime_type': instance.mimeType,
      'device_metadata': instance.deviceMetadata.toJson(),
      'upload_url': instance.uploadUrl,
      'cdn_key': instance.cdnKey,
      'caption': instance.caption,
    };

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

Options _$OptionsFromJson(Map<String, dynamic> json) => Options(
      schedule: json['schedule'] as String? ?? 'now',
      locationTag: json['location_tag'] == null
          ? null
          : LocationTag.fromJson(json['location_tag'] as Map<String, dynamic>),
      visibility: (json['visibility'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String?),
      ),
      replyToPostId: (json['reply_to_post_id'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String?),
      ),
    );

Map<String, dynamic> _$OptionsToJson(Options instance) => <String, dynamic>{
      'schedule': instance.schedule,
      'location_tag': instance.locationTag?.toJson(),
      'visibility': instance.visibility,
      'reply_to_post_id': instance.replyToPostId,
    };

LocationTag _$LocationTagFromJson(Map<String, dynamic> json) => LocationTag(
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );

Map<String, dynamic> _$LocationTagToJson(LocationTag instance) =>
    <String, dynamic>{
      'name': instance.name,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
    };

PlatformData _$PlatformDataFromJson(Map<String, dynamic> json) => PlatformData(
      facebook: json['facebook'] == null
          ? null
          : FacebookData.fromJson(json['facebook'] as Map<String, dynamic>),
      instagram: json['instagram'] == null
          ? null
          : InstagramData.fromJson(json['instagram'] as Map<String, dynamic>),
      twitter: json['twitter'] == null
          ? null
          : TwitterData.fromJson(json['twitter'] as Map<String, dynamic>),
      tiktok: json['tiktok'] == null
          ? null
          : TikTokData.fromJson(json['tiktok'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PlatformDataToJson(PlatformData instance) =>
    <String, dynamic>{
      'facebook': instance.facebook?.toJson(),
      'instagram': instance.instagram?.toJson(),
      'twitter': instance.twitter?.toJson(),
      'tiktok': instance.tiktok?.toJson(),
    };

FacebookData _$FacebookDataFromJson(Map<String, dynamic> json) => FacebookData(
      postHere: json['post_here'] as bool? ?? false,
      postAsPage: json['post_as_page'] as bool? ?? false,
      pageId: json['page_id'] as String? ?? '',
      postType: json['post_type'] as String?,
      mediaFileUri: json['media_file_uri'] as String?,
      videoFileUri: json['video_file_uri'] as String?,
      audioFileUri: json['audio_file_uri'] as String?,
      thumbnailUri: json['thumbnail_uri'] as String?,
      scheduledTime: json['scheduled_time'] as String?,
      additionalFields: json['additional_fields'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$FacebookDataToJson(FacebookData instance) =>
    <String, dynamic>{
      'post_here': instance.postHere,
      'post_as_page': instance.postAsPage,
      'page_id': instance.pageId,
      'post_type': instance.postType,
      'media_file_uri': instance.mediaFileUri,
      'video_file_uri': instance.videoFileUri,
      'audio_file_uri': instance.audioFileUri,
      'thumbnail_uri': instance.thumbnailUri,
      'scheduled_time': instance.scheduledTime,
      'additional_fields': instance.additionalFields,
    };

InstagramData _$InstagramDataFromJson(Map<String, dynamic> json) =>
    InstagramData(
      postHere: json['post_here'] as bool? ?? false,
      postType: json['post_type'] as String?,
      carousel: json['carousel'] == null
          ? null
          : Carousel.fromJson(json['carousel'] as Map<String, dynamic>),
      igUserId: json['ig_user_id'] as String? ?? '',
      mediaType: json['media_type'] as String?,
      mediaFileUri: json['media_file_uri'] as String?,
      videoThumbnailUri: json['video_thumbnail_uri'] as String?,
      videoFileUri: json['video_file_uri'] as String?,
      audioFileUri: json['audio_file_uri'] as String?,
      scheduledTime: json['scheduled_time'] as String?,
    );

Map<String, dynamic> _$InstagramDataToJson(InstagramData instance) =>
    <String, dynamic>{
      'post_here': instance.postHere,
      'post_type': instance.postType,
      'carousel': instance.carousel?.toJson(),
      'ig_user_id': instance.igUserId,
      'media_type': instance.mediaType,
      'media_file_uri': instance.mediaFileUri,
      'video_thumbnail_uri': instance.videoThumbnailUri,
      'video_file_uri': instance.videoFileUri,
      'audio_file_uri': instance.audioFileUri,
      'scheduled_time': instance.scheduledTime,
    };

Carousel _$CarouselFromJson(Map<String, dynamic> json) => Carousel(
      enabled: json['enabled'] as bool? ?? false,
      order: (json['order'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
    );

Map<String, dynamic> _$CarouselToJson(Carousel instance) => <String, dynamic>{
      'enabled': instance.enabled,
      'order': instance.order,
    };

TwitterData _$TwitterDataFromJson(Map<String, dynamic> json) => TwitterData(
      postHere: json['post_here'] as bool? ?? false,
      altTexts: (json['alt_texts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      tweetMode: json['tweet_mode'] as String? ?? 'extended',
      mediaType: json['media_type'] as String?,
      mediaFileUri: json['media_file_uri'] as String?,
      mediaDuration: (json['media_duration'] as num?)?.toDouble(),
      tweetLink: json['tweet_link'] as String?,
      scheduledTime: json['scheduled_time'] as String?,
    );

Map<String, dynamic> _$TwitterDataToJson(TwitterData instance) =>
    <String, dynamic>{
      'post_here': instance.postHere,
      'alt_texts': instance.altTexts,
      'tweet_mode': instance.tweetMode,
      'media_type': instance.mediaType,
      'media_file_uri': instance.mediaFileUri,
      'media_duration': instance.mediaDuration,
      'tweet_link': instance.tweetLink,
      'scheduled_time': instance.scheduledTime,
    };

TikTokData _$TikTokDataFromJson(Map<String, dynamic> json) => TikTokData(
      postHere: json['post_here'] as bool? ?? false,
      privacy: json['privacy'] as String? ?? 'public',
      sound: Sound.fromJson(json['sound'] as Map<String, dynamic>),
      mediaFileUri: json['media_file_uri'] as String?,
      videoFileUri: json['video_file_uri'] as String?,
      audioFileUri: json['audio_file_uri'] as String?,
      scheduledTime: json['scheduled_time'] as String?,
    );

Map<String, dynamic> _$TikTokDataToJson(TikTokData instance) =>
    <String, dynamic>{
      'post_here': instance.postHere,
      'privacy': instance.privacy,
      'sound': instance.sound.toJson(),
      'media_file_uri': instance.mediaFileUri,
      'video_file_uri': instance.videoFileUri,
      'audio_file_uri': instance.audioFileUri,
      'scheduled_time': instance.scheduledTime,
    };

Sound _$SoundFromJson(Map<String, dynamic> json) => Sound(
      useOriginalSound: json['use_original_sound'] as bool? ?? true,
      musicId: json['music_id'] as String?,
    );

Map<String, dynamic> _$SoundToJson(Sound instance) => <String, dynamic>{
      'use_original_sound': instance.useOriginalSound,
      'music_id': instance.musicId,
    };

Internal _$InternalFromJson(Map<String, dynamic> json) => Internal(
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
      userPreferences: json['user_preferences'] == null
          ? null
          : UserPreferences.fromJson(
              json['user_preferences'] as Map<String, dynamic>),
      mediaIndexId: json['media_index_id'] as String?,
      uiFlags: json['ui_flags'] == null
          ? null
          : UiFlags.fromJson(json['ui_flags'] as Map<String, dynamic>),
      aiGenerated: json['ai_generated'] as bool? ?? false,
      originalTranscription: json['original_transcription'] as String? ?? '',
      fallbackReason: json['fallback_reason'] as String?,
    );

Map<String, dynamic> _$InternalToJson(Internal instance) => <String, dynamic>{
      'retry_count': instance.retryCount,
      'user_preferences': instance.userPreferences.toJson(),
      'media_index_id': instance.mediaIndexId,
      'ui_flags': instance.uiFlags.toJson(),
      'ai_generated': instance.aiGenerated,
      'original_transcription': instance.originalTranscription,
      'fallback_reason': instance.fallbackReason,
    };

UserPreferences _$UserPreferencesFromJson(Map<String, dynamic> json) =>
    UserPreferences(
      defaultPlatforms: (json['default_platforms'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      defaultHashtags: (json['default_hashtags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );

Map<String, dynamic> _$UserPreferencesToJson(UserPreferences instance) =>
    <String, dynamic>{
      'default_platforms': instance.defaultPlatforms,
      'default_hashtags': instance.defaultHashtags,
    };

UiFlags _$UiFlagsFromJson(Map<String, dynamic> json) => UiFlags(
      isEditingCaption: json['is_editing_caption'] as bool? ?? false,
      isMediaPreviewOpen: json['is_media_preview_open'] as bool? ?? false,
    );

Map<String, dynamic> _$UiFlagsToJson(UiFlags instance) => <String, dynamic>{
      'is_editing_caption': instance.isEditingCaption,
      'is_media_preview_open': instance.isMediaPreviewOpen,
    };
