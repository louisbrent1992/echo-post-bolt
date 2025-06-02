import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/social_action.dart';

class SocialPostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Posts the action to every platform listed (simplified stub implementation)
  Future<Map<String, bool>> postToAllPlatforms(SocialAction action) async {
    final results = <String, bool>{};

    // For now, simulate posting with a delay and return success
    // In a real implementation, this would integrate with actual social media APIs
    await Future.delayed(const Duration(seconds: 2));

    for (final platform in action.platforms) {
      try {
        switch (platform) {
          case 'facebook':
            await _simulatePost('Facebook', action);
            results['facebook'] = true;
            break;
          case 'instagram':
            await _simulatePost('Instagram', action);
            results['instagram'] = true;
            break;
          case 'twitter':
            await _simulatePost('Twitter', action);
            results['twitter'] = true;
            break;
          case 'tiktok':
            await _simulatePost('TikTok', action);
            results['tiktok'] = true;
            break;
          default:
            if (kDebugMode) {
              print('Unsupported platform: $platform');
            }
            results[platform] = false;
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error posting to $platform: $e');
        }
        results[platform] = false;
        await _markActionFailed(
          action.actionId,
          '$platform error: ${e.toString()}',
        );
      }
    }

    // If all succeeded, mark the action posted
    if (results.values.every((success) => success)) {
      await _markActionPosted(action.actionId);
    }

    return results;
  }

  /// Simulate posting to a platform (for development/testing)
  Future<void> _simulatePost(String platform, SocialAction action) async {
    if (kDebugMode) {
      print('Simulating post to $platform:');

      print('  Text: ${action.content.text}');
      print('  Hashtags: ${action.content.hashtags.join(', ')}');
      print('  Media count: ${action.content.media.length}');
    }

    // Simulate some processing time
    await Future.delayed(const Duration(milliseconds: 500));

    // Randomly fail 10% of the time to simulate real-world conditions
    if (DateTime.now().millisecond % 10 == 0) {
      throw Exception('Simulated $platform API error');
    }

    if (kDebugMode) {
      print('  ✓ Successfully posted to $platform');
    }
  }

  /// Mark an action as successfully posted
  Future<void> _markActionPosted(String actionId) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('actions')
          .doc(actionId)
          .update({
        'status': 'posted',
        'posted_at': FieldValue.serverTimestamp(),
        'last_attempt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('Action $actionId marked as posted');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error marking action as posted: $e');
      }
    }
  }

  /// Mark an action as failed
  Future<void> _markActionFailed(String actionId, String error) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('actions')
          .doc(actionId)
          .update({
        'status': 'failed',
        'last_attempt': FieldValue.serverTimestamp(),
        'error_log': FieldValue.arrayUnion([
          {
            'timestamp': FieldValue.serverTimestamp(),
            'error': error,
          }
        ]),
      });

      if (kDebugMode) {
        print('Action $actionId marked as failed: $error');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error marking action as failed: $e');
      }
    }
  }
}
