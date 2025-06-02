// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'social_action.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SocialAction _$SocialActionFromJson(Map<String, dynamic> json) => SocialAction(
      action_id: json['action_id'] as String?,
      created_at: json['created_at'] as String?,
      platforms:
          (json['platforms'] as List<dynamic>).map((e) => e as String).toList(),
      content: Content.fromJson(json['content'] as Map<String, dynamic>),
      options: Options.fromJson(json['options'] as Map<String, dynamic>),
      platform_data:
          PlatformData.fromJson(json['platform_data'] as Map<String, dynamic>),
      internal: Internal.fromJson(json['internal'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$SocialActionToJson(SocialAction instance) =>
    <String, dynamic>{
      'action_id': instance.action_id,
      'created_at': instance.created_at,
      'platforms': instance.platforms,
      'content': instance.content.toJson(),
      'options': instance.options.toJson(),
      'platform_data': instance.platform_data.toJson(),
      'internal': instance.internal.toJson(),
    };

Content _$ContentFromJson(Map<String, dynamic> json) => Content(
      text: json['text'] as String,
      hashtags:
          (json['hashtags'] as List<dynamic>).map((e) => e as String).toList(),
      mentions:
          (json['mentions'] as List<dynamic>).map((e) => e as String).toList(),
      link: json['link'] == null
          ? null
          : Link.fromJson(json['link'] as Map<String, dynamic>),
      media: (json['media'] as List<dynamic>)
          .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
          .toList(),
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
      thumbnail_url: json['thumbnail_url'] as String?,
    );

Map<String, dynamic> _$LinkToJson(Link instance) => <String, dynamic>{
      'url': instance.url,
      'title': instance.title,
      'description': instance.description,
      'thumbnail_url': instance.thumbnail_url,
    };

MediaItem _$MediaItemFromJson(Map<String, dynamic> json) => MediaItem(
      fileUri: json['fileUri'] as String,
      mimeType: json['mimeType'] as String,
      deviceMetadata: DeviceMetadata.fromJson(
          json['deviceMetadata'] as Map<String, dynamic>),
      uploadUrl: json['uploadUrl'] as String?,
      cdnKey: json['cdnKey'] as String?,
      caption: json['caption'] as String?,
    );

Map<String, dynamic> _$MediaItemToJson(MediaItem instance) => <String, dynamic>{
      'fileUri': instance.fileUri,
      'mimeType': instance.mimeType,
      'deviceMetadata': instance.deviceMetadata.toJson(),
      'uploadUrl': instance.uploadUrl,
      'cdnKey': instance.cdnKey,
      'caption': instance.caption,
    };

DeviceMetadata _$DeviceMetadataFromJson(Map<String, dynamic> json) =>
    DeviceMetadata(
      creationTime: json['creationTime'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      orientation: (json['orientation'] as num).toInt(),
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      fileSizeBytes: (json['fileSizeBytes'] as num).toInt(),
    );

Map<String, dynamic> _$DeviceMetadataToJson(DeviceMetadata instance) =>
    <String, dynamic>{
      'creationTime': instance.creationTime,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'orientation': instance.orientation,
      'width': instance.width,
      'height': instance.height,
      'fileSizeBytes': instance.fileSizeBytes,
    };

Options _$OptionsFromJson(Map<String, dynamic> json) => Options(
      schedule: json['schedule'] as String,
      locationTag: json['locationTag'] == null
          ? null
          : LocationTag.fromJson(json['locationTag'] as Map<String, dynamic>),
      visibility: (json['visibility'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String?),
      ),
      replyToPostId: (json['replyToPostId'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String?),
      ),
    );

Map<String, dynamic> _$OptionsToJson(Options instance) => <String, dynamic>{
      'schedule': instance.schedule,
      'locationTag': instance.locationTag?.toJson(),
      'visibility': instance.visibility,
      'replyToPostId': instance.replyToPostId,
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
      postAsPage: json['postAsPage'] as bool,
      pageId: json['pageId'] as String,
      additionalFields: json['additionalFields'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$FacebookDataToJson(FacebookData instance) =>
    <String, dynamic>{
      'postAsPage': instance.postAsPage,
      'pageId': instance.pageId,
      'additionalFields': instance.additionalFields,
    };

InstagramData _$InstagramDataFromJson(Map<String, dynamic> json) =>
    InstagramData(
      postType: json['postType'] as String,
      carousel: json['carousel'] == null
          ? null
          : Carousel.fromJson(json['carousel'] as Map<String, dynamic>),
      igUserId: json['igUserId'] as String,
    );

Map<String, dynamic> _$InstagramDataToJson(InstagramData instance) =>
    <String, dynamic>{
      'postType': instance.postType,
      'carousel': instance.carousel?.toJson(),
      'igUserId': instance.igUserId,
    };

Carousel _$CarouselFromJson(Map<String, dynamic> json) => Carousel(
      enabled: json['enabled'] as bool,
      order: (json['order'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
    );

Map<String, dynamic> _$CarouselToJson(Carousel instance) => <String, dynamic>{
      'enabled': instance.enabled,
      'order': instance.order,
    };

TwitterData _$TwitterDataFromJson(Map<String, dynamic> json) => TwitterData(
      altTexts:
          (json['altTexts'] as List<dynamic>).map((e) => e as String).toList(),
      tweetMode: json['tweetMode'] as String,
    );

Map<String, dynamic> _$TwitterDataToJson(TwitterData instance) =>
    <String, dynamic>{
      'altTexts': instance.altTexts,
      'tweetMode': instance.tweetMode,
    };

TikTokData _$TikTokDataFromJson(Map<String, dynamic> json) => TikTokData(
      privacy: json['privacy'] as String,
      sound: Sound.fromJson(json['sound'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$TikTokDataToJson(TikTokData instance) =>
    <String, dynamic>{
      'privacy': instance.privacy,
      'sound': instance.sound.toJson(),
    };

Sound _$SoundFromJson(Map<String, dynamic> json) => Sound(
      useOriginalSound: json['useOriginalSound'] as bool,
      musicId: json['musicId'] as String?,
    );

Map<String, dynamic> _$SoundToJson(Sound instance) => <String, dynamic>{
      'useOriginalSound': instance.useOriginalSound,
      'musicId': instance.musicId,
    };

Internal _$InternalFromJson(Map<String, dynamic> json) => Internal(
      retryCount: (json['retryCount'] as num).toInt(),
      userPreferences: UserPreferences.fromJson(
          json['userPreferences'] as Map<String, dynamic>),
      mediaIndexId: json['mediaIndexId'] as String?,
      uiFlags: UiFlags.fromJson(json['uiFlags'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$InternalToJson(Internal instance) => <String, dynamic>{
      'retryCount': instance.retryCount,
      'userPreferences': instance.userPreferences.toJson(),
      'mediaIndexId': instance.mediaIndexId,
      'uiFlags': instance.uiFlags.toJson(),
    };

UserPreferences _$UserPreferencesFromJson(Map<String, dynamic> json) =>
    UserPreferences(
      defaultPlatforms: (json['defaultPlatforms'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      defaultHashtags: (json['defaultHashtags'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$UserPreferencesToJson(UserPreferences instance) =>
    <String, dynamic>{
      'defaultPlatforms': instance.defaultPlatforms,
      'defaultHashtags': instance.defaultHashtags,
    };

UiFlags _$UiFlagsFromJson(Map<String, dynamic> json) => UiFlags(
      isEditingCaption: json['isEditingCaption'] as bool,
      isMediaPreviewOpen: json['isMediaPreviewOpen'] as bool,
    );

Map<String, dynamic> _$UiFlagsToJson(UiFlags instance) => <String, dynamic>{
      'isEditingCaption': instance.isEditingCaption,
      'isMediaPreviewOpen': instance.isMediaPreviewOpen,
    };
