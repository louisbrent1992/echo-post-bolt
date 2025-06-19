import 'package:uuid/uuid.dart';

class MediaDirectory {
  final String id;
  final String path;
  final String displayName;
  final bool isDefault;
  final bool isEnabled;

  MediaDirectory({
    String? id,
    required this.path,
    required this.displayName,
    this.isDefault = false,
    this.isEnabled = true,
  }) : id = id ?? const Uuid().v4();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaDirectory &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}
