import 'package:flutter/foundation.dart';
import '../constants/social_platforms.dart';
import 'auth/facebook_auth_service.dart';
import 'auth/instagram_auth_service.dart';
import 'auth/youtube_auth_service.dart';
import 'auth/twitter_auth_service.dart';
import 'auth/tiktok_auth_service.dart';

/// Unified service for checking platform connection status
/// This serves as the single source of truth for platform authentication
/// by delegating to individual auth services that have platform-specific logic
class PlatformConnectionService {
  /// Check if a platform is connected by delegating to the appropriate auth service
  /// This is the ground truth for platform authentication status
  static Future<bool> isPlatformConnected(String platform) async {
    try {
      if (kDebugMode) {
        print('🔍 Checking connection status for $platform');
      }

      final isConnected = await _getPlatformConnectionStatus(platform);

      if (kDebugMode) {
        print(
            '${isConnected ? '✅' : '❌'} $platform connection status: $isConnected');
      }

      return isConnected;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking $platform connection: $e');
      }
      return false;
    }
  }

  /// Get connection status for all platforms
  static Future<Map<String, bool>> getAllPlatformConnectionStatus() async {
    final statusMap = <String, bool>{};

    for (final platform in SocialPlatforms.all) {
      statusMap[platform] = await isPlatformConnected(platform);
    }

    if (kDebugMode) {
      print('📊 All platform connection status:');
      for (final entry in statusMap.entries) {
        print('   ${entry.key}: ${entry.value ? '✅' : '❌'}');
      }
    }

    return statusMap;
  }

  /// Get list of connected platforms
  static Future<List<String>> getConnectedPlatforms() async {
    final statusMap = await getAllPlatformConnectionStatus();
    return statusMap.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
  }

  /// Get list of disconnected platforms
  static Future<List<String>> getDisconnectedPlatforms() async {
    final statusMap = await getAllPlatformConnectionStatus();
    return statusMap.entries
        .where((entry) => !entry.value)
        .map((entry) => entry.key)
        .toList();
  }

  /// Check if user has any connected platforms
  static Future<bool> hasAnyConnectedPlatform() async {
    final connectedPlatforms = await getConnectedPlatforms();
    return connectedPlatforms.isNotEmpty;
  }

  /// Check if user has connected platforms that support a specific content type
  static Future<List<String>> getConnectedPlatformsForContentType(
      String contentType) async {
    final connectedPlatforms = await getConnectedPlatforms();

    return connectedPlatforms
        .where((platform) =>
            SocialPlatforms.isPlatformCompatible(platform, contentType))
        .toList();
  }

  /// Check if user has connected platforms that require media
  static Future<List<String>> getConnectedMediaRequiredPlatforms() async {
    final connectedPlatforms = await getConnectedPlatforms();

    return connectedPlatforms
        .where((platform) => SocialPlatforms.requiresMedia(platform))
        .toList();
  }

  /// Check if user has connected platforms that support text-only posts
  static Future<List<String>> getConnectedTextSupportedPlatforms() async {
    final connectedPlatforms = await getConnectedPlatforms();

    return connectedPlatforms
        .where((platform) => SocialPlatforms.supportsTextOnly(platform))
        .toList();
  }

  /// Delegate to platform-specific auth service
  static Future<bool> _getPlatformConnectionStatus(String platform) async {
    switch (platform.toLowerCase()) {
      case 'facebook':
        return await FacebookAuthService().isFacebookConnected();

      case 'instagram':
        return await InstagramAuthService().isInstagramConnected();

      case 'youtube':
        return await YouTubeAuthService().isYouTubeConnected();

      case 'twitter':
        return await TwitterAuthService().isTwitterConnected();

      case 'tiktok':
        return await TikTokAuthService().isTikTokConnected();

      default:
        if (kDebugMode) {
          print('⚠️ Unknown platform: $platform - returning false');
        }
        return false;
    }
  }

  /// Validate that a platform is supported before checking connection
  static bool isPlatformSupported(String platform) {
    return SocialPlatforms.isSupported(platform);
  }

  /// Get user-friendly connection status message
  static String getConnectionStatusMessage(List<String> connectedPlatforms) {
    if (connectedPlatforms.isEmpty) {
      return 'No platforms connected';
    }

    final platformNames = connectedPlatforms
        .map((platform) => SocialPlatforms.getDisplayName(platform))
        .join(', ');

    return 'Connected to: $platformNames';
  }

  /// Get user-friendly disconnection status message
  static String getDisconnectionStatusMessage(
      List<String> disconnectedPlatforms) {
    if (disconnectedPlatforms.isEmpty) {
      return 'All platforms connected';
    }

    final platformNames = disconnectedPlatforms
        .map((platform) => SocialPlatforms.getDisplayName(platform))
        .join(', ');

    return 'Not connected to: $platformNames';
  }
}
