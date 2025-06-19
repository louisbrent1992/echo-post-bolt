import 'package:json_annotation/json_annotation.dart';

part 'media_query.g.dart';

@JsonSerializable()
class MediaSearchQuery {
  @JsonKey(name: 'directory_path')
  final String? directoryPath;

  @JsonKey(name: 'search_terms')
  final List<String> searchTerms;

  @JsonKey(name: 'date_range')
  final DateRange? dateRange;

  @JsonKey(name: 'media_types')
  final List<String> mediaTypes;

  @JsonKey(name: 'location_query')
  final LocationQuery? locationQuery;

  MediaSearchQuery({
    this.directoryPath,
    this.searchTerms = const [],
    this.dateRange,
    this.mediaTypes = const [],
    this.locationQuery,
  });

  /// Returns true if this query has any search criteria set
  bool get isNotEmpty =>
      directoryPath != null ||
      searchTerms.isNotEmpty ||
      dateRange != null ||
      mediaTypes.isNotEmpty ||
      locationQuery != null;

  factory MediaSearchQuery.fromJson(Map<String, dynamic> json) =>
      _$MediaSearchQueryFromJson(json);
  Map<String, dynamic> toJson() => _$MediaSearchQueryToJson(this);
}

@JsonSerializable()
class DateRange {
  @JsonKey(name: 'start_date')
  final DateTime? startDate;

  @JsonKey(name: 'end_date')
  final DateTime? endDate;

  DateRange({
    this.startDate,
    this.endDate,
  });

  factory DateRange.fromJson(Map<String, dynamic> json) =>
      _$DateRangeFromJson(json);
  Map<String, dynamic> toJson() => _$DateRangeToJson(this);
}

@JsonSerializable()
class LocationQuery {
  @JsonKey(name: 'location_name')
  final String? locationName;

  @JsonKey(name: 'latitude')
  final double? latitude;

  @JsonKey(name: 'longitude')
  final double? longitude;

  @JsonKey(name: 'radius_km')
  final double? radiusKm;

  LocationQuery({
    this.locationName,
    this.latitude,
    this.longitude,
    this.radiusKm,
  });

  factory LocationQuery.fromJson(Map<String, dynamic> json) =>
      _$LocationQueryFromJson(json);
  Map<String, dynamic> toJson() => _$LocationQueryToJson(this);
}
