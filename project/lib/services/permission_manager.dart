import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionManager extends ChangeNotifier {
  bool _hasMicrophonePermission = false;
  bool _hasMediaPermission = false;
  bool _isRequestingPermissions = false;

  // Getters
  bool get hasMicrophonePermission => _hasMicrophonePermission;
  bool get hasMediaPermission => _hasMediaPermission;
  bool get hasAllPermissions => _hasMicrophonePermission && _hasMediaPermission;
  bool get isRequestingPermissions => _isRequestingPermissions;

  /// Request all required permissions at once
  Future<void> requestAllPermissions() async {
    if (_isRequestingPermissions) return;
    _isRequestingPermissions = true;
    notifyListeners();

    try {
      // Request media permissions using PhotoManager
      final mediaPermissionState = await PhotoManager.requestPermissionExtend();
      _hasMediaPermission = mediaPermissionState.hasAccess;

      // Request microphone permission
      _hasMicrophonePermission =
          await Permission.microphone.request().isGranted;

      if (kDebugMode) {
        print('📱 Permission status:');
        print('   Media: ${_hasMediaPermission ? '✅' : '❌'}');
        print('   Microphone: ${_hasMicrophonePermission ? '✅' : '❌'}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error requesting permissions: $e');
      }
      rethrow;
    } finally {
      _isRequestingPermissions = false;
      notifyListeners();
    }
  }

  /// Check current permission status without requesting
  Future<void> checkPermissions() async {
    try {
      // Check media permissions
      final mediaPermissionState = await PhotoManager.requestPermissionExtend();
      _hasMediaPermission = mediaPermissionState.hasAccess;

      // Check microphone permission
      _hasMicrophonePermission = await Permission.microphone.status.isGranted;

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking permissions: $e');
      }
    }
  }
}
