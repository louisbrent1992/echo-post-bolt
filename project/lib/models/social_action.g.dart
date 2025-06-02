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
      postAsPage: json['post_as_page'] as bool? ?? false,
      pageId: json['page_id'] as String? ?? '',
      additionalFields: json['additional_fields'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$FacebookDataToJson(FacebookData instance) =>
    <String, dynamic>{
      'post_as_page': instance.postAsPage,
      'page_id': instance.pageId,
      'additional_fields': instance.additionalFields,
    };

InstagramData _$InstagramDataFromJson(Map<String, dynamic> json) =>
    InstagramData(
      postType: json['post_type'] as String? ?? 'feed',
      carousel: json['carousel'] == null
          ? null
          : Carousel.fromJson(json['carousel'] as Map<String, dynamic>),
      igUserId: json['ig_user_id'] as String? ?? '',
    );

Map<String, dynamic> _$InstagramDataToJson(InstagramData instance) =>
    <String, dynamic>{
      'post_type': instance.postType,
      'carousel': instance.carousel?.toJson(),
      'ig_user_id': instance.igUserId,
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
      altTexts: (json['alt_texts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      tweetMode: json['tweet_mode'] as String? ?? 'extended',
    );

Map<String, dynamic> _$TwitterDataToJson(TwitterData instance) =>
    <String, dynamic>{
      'alt_texts': instance.altTexts,
      'tweet_mode': instance.tweetMode,
    };

TikTokData _$TikTokDataFromJson(Map<String, dynamic> json) => TikTokData(
      privacy: json['privacy'] as String? ?? 'public',
      sound: Sound.fromJson(json['sound'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$TikTokDataToJson(TikTokData instance) =>
    <String, dynamic>{
      'privacy': instance.privacy,
      'sound': instance.sound.toJson(),
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
      userPreferences: UserPreferences.fromJson(
          json['user_preferences'] as Map<String, dynamic>),
      mediaIndexId: json['media_index_id'] as String?,
      uiFlags: UiFlags.fromJson(json['ui_flags'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$InternalToJson(Internal instance) => <String, dynamic>{
      'retry_count': instance.retryCount,
      'user_preferences': instance.userPreferences.toJson(),
      'media_index_id': instance.mediaIndexId,
      'ui_flags': instance.uiFlags.toJson(),
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
