import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../constants/social_platforms.dart';

/// Service responsible for managing platform document initialization and nullification
/// This ensures all users have consistent platform document structures in Firestore
class PlatformDocumentService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Initialize platform documents for a new user
  /// Creates nullified documents for all platforms defined in SocialPlatforms.all
  static Future<void> initializePlatformDocuments(String userId) async {
    try {
      if (kDebugMode) {
        print('🔧 Initializing platform documents for user: $userId');
      }

      // Create nullified documents for all platforms
      for (final platform in SocialPlatforms.all) {
        await _createNullifiedPlatformDocument(userId, platform);
      }

      if (kDebugMode) {
        print(
            '✅ Platform documents initialized for all ${SocialPlatforms.all.length} platforms');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing platform documents: $e');
      }
      rethrow;
    }
  }

  /// Create a nullified platform document with platform-specific schema
  static Future<void> _createNullifiedPlatformDocument(
      String userId, String platform) async {
    try {
      final nullifiedFields = getNullifiedFieldsForPlatform(platform);

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('tokens')
          .doc(platform)
          .set(nullifiedFields, SetOptions(merge: true));

      if (kDebugMode) {
        print('📄 Created nullified document for $platform');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error creating nullified document for $platform: $e');
      }
      rethrow;
    }
  }

  /// Get platform-specific nullification schema
  /// Each platform has different required fields that should be nullified on logout
  static Map<String, dynamic> getNullifiedFieldsForPlatform(String platform) {
    final baseFields = {
      'created_at': FieldValue.serverTimestamp(),
      'last_updated': FieldValue.serverTimestamp(),
    };

    switch (platform.toLowerCase()) {
      case 'facebook':
        return {
          ...baseFields,
          'access_token': null,
          'user_id': null,
          'expires_at': null,
          'user_name': null,
          'user_email': null,
        };

      case 'instagram':
        return {
          ...baseFields,
          'access_token': null,
          'user_id': null,
          'username': null,
          'account_type': null,
          'media_count': null,
          'expires_in': null,
          'token_type': null,
          'scope': null,
        };

      case 'youtube':
        return {
          ...baseFields,
          'access_token': null,
          'refresh_token': null,
          'token_type': null,
          'scope': null,
          'channel_id': null,
          'channel_title': null,
          'channel_description': null,
          'subscriber_count': null,
          'video_count': null,
          'view_count': null,
        };

      case 'twitter':
        return {
          ...baseFields,
          'oauth_token': null,
          'oauth_token_secret': null,
          'user_id': null,
          'screen_name': null,
          'name': null,
          'profile_image_url': null,
          'followers_count': null,
          'friends_count': null,
          'statuses_count': null,
        };

      case 'tiktok':
        return {
          ...baseFields,
          'access_token': null,
          'refresh_token': null,
          'token_type': null,
          'scope': null,
          'user_id': null,
          'username': null,
          'display_name': null,
          'avatar_url': null,
          'follower_count': null,
          'following_count': null,
          'likes_count': null,
          'video_count': null,
        };

      default:
        if (kDebugMode) {
          print(
              '⚠️ Unknown platform: $platform - using empty nullification schema');
        }
        return baseFields;
    }
  }

  /// Check if a platform document exists for a user
  /// Used for migration of existing users who don't have platform documents
  static Future<bool> platformDocumentExists(
      String userId, String platform) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('tokens')
          .doc(platform)
          .get();

      return doc.exists;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking if platform document exists: $e');
      }
      return false;
    }
  }

  /// Migrate existing users to have platform documents
  /// This ensures all users have the required platform document structure
  static Future<void> migrateUserToPlatformDocuments(String userId) async {
    try {
      if (kDebugMode) {
        print('🔄 Migrating user to platform documents: $userId');
      }

      // Check which platform documents are missing
      final missingPlatforms = <String>[];

      for (final platform in SocialPlatforms.all) {
        final exists = await platformDocumentExists(userId, platform);
        if (!exists) {
          missingPlatforms.add(platform);
        }
      }

      if (missingPlatforms.isNotEmpty) {
        if (kDebugMode) {
          print(
              '📋 Creating missing platform documents: ${missingPlatforms.join(', ')}');
        }

        // Create missing platform documents
        for (final platform in missingPlatforms) {
          await _createNullifiedPlatformDocument(userId, platform);
        }

        if (kDebugMode) {
          print(
              '✅ Migration completed - created ${missingPlatforms.length} platform documents');
        }
      } else {
        if (kDebugMode) {
          print('ℹ️ User already has all platform documents');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error migrating user to platform documents: $e');
      }
      rethrow;
    }
  }

  /// Get the required fields for a platform that determine authentication status
  /// These are the fields that must be non-null for the platform to be considered authenticated
  static List<String> getRequiredFieldsForPlatform(String platform) {
    switch (platform.toLowerCase()) {
      case 'facebook':
        return ['access_token', 'user_id'];
      case 'instagram':
        return ['access_token', 'user_id'];
      case 'youtube':
        return ['access_token', 'channel_id'];
      case 'twitter':
        return ['oauth_token', 'user_id'];
      case 'tiktok':
        return ['access_token', 'user_id'];
      default:
        return [];
    }
  }

  /// Check if a platform document is nullified (all required fields are null)
  static bool isPlatformDocumentNullified(
      Map<String, dynamic> tokenData, String platform) {
    final requiredFields = getRequiredFieldsForPlatform(platform);

    for (final field in requiredFields) {
      if (tokenData[field] != null) {
        return false; // Found a non-null required field
      }
    }

    return true; // All required fields are null
  }
}
