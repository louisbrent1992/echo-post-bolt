// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_query.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MediaSearchQuery _$MediaSearchQueryFromJson(Map<String, dynamic> json) =>
    MediaSearchQuery(
      directoryPath: json['directory_path'] as String?,
      searchTerms: (json['search_terms'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      dateRange: json['date_range'] == null
          ? null
          : DateRange.fromJson(json['date_range'] as Map<String, dynamic>),
      mediaTypes: (json['media_types'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      locationQuery: json['location_query'] == null
          ? null
          : LocationQuery.fromJson(
              json['location_query'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$MediaSearchQueryToJson(MediaSearchQuery instance) =>
    <String, dynamic>{
      'directory_path': instance.directoryPath,
      'search_terms': instance.searchTerms,
      'date_range': instance.dateRange,
      'media_types': instance.mediaTypes,
      'location_query': instance.locationQuery,
    };

DateRange _$DateRangeFromJson(Map<String, dynamic> json) => DateRange(
      startDate: json['start_date'] == null
          ? null
          : DateTime.parse(json['start_date'] as String),
      endDate: json['end_date'] == null
          ? null
          : DateTime.parse(json['end_date'] as String),
    );

Map<String, dynamic> _$DateRangeToJson(DateRange instance) => <String, dynamic>{
      'start_date': instance.startDate?.toIso8601String(),
      'end_date': instance.endDate?.toIso8601String(),
    };

LocationQuery _$LocationQueryFromJson(Map<String, dynamic> json) =>
    LocationQuery(
      locationName: json['location_name'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      radiusKm: (json['radius_km'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$LocationQueryToJson(LocationQuery instance) =>
    <String, dynamic>{
      'location_name': instance.locationName,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'radius_km': instance.radiusKm,
    };
