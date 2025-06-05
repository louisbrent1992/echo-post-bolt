import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Helper method to get current user safely
  String? get _currentUserId => _auth.currentUser?.uid;

  // Save a new social action to Firestore
  Future<void> saveAction(Map<String, dynamic> actionJson) async {
    final uid = _currentUserId;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    final actionId = actionJson['action_id'];
    if (actionId == null) {
      throw Exception('Action ID is required');
    }

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('actions')
          .doc(actionId)
          .set({
        'created_at': FieldValue.serverTimestamp(),
        'status': 'pending',
        'retry_count': 0,
        'last_attempt': null,
        'error_log': [],
        'action_json': actionJson,
      });
    } catch (e) {
      throw Exception('Failed to save action: $e');
    }
  }

  // Update an existing action
  Future<void> updateAction(
      String actionId, Map<String, dynamic> updatedJson) async {
    final uid = _currentUserId;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('actions')
          .doc(actionId)
          .update({
        'action_json': updatedJson,
      });
    } catch (e) {
      throw Exception('Failed to update action: $e');
    }
  }

  // Mark an action as successfully posted to social media platforms
  Future<void> markActionPosted(String actionId,
      Map<String, dynamic> updatedJson, Map<String, String> postIds) async {
    final uid = _currentUserId;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('actions')
          .doc(actionId)
          .update({
        'status': 'posted',
        'last_attempt': FieldValue.serverTimestamp(),
        'action_json': updatedJson,
        'posted_ids': postIds,
      });
    } catch (e) {
      throw Exception('Failed to mark action posted: $e');
    }
  }

  // Delete an action
  Future<void> deleteAction(String actionId) async {
    final uid = _currentUserId;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('actions')
          .doc(actionId)
          .delete();
    } catch (e) {
      throw Exception('Failed to delete action: $e');
    }
  }

  // Cache media selection for a query
  Future<void> cacheMediaSelection(String query, String assetId) async {
    final uid = _currentUserId;
    if (uid == null) {
      return; // Silently fail if not authenticated
    }

    try {
      final queryHash = _hashQuery(query);

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('media_cache')
          .doc(queryHash)
          .set({
        'original_query': query,
        'selected_asset_id': assetId,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        print('Warning: Failed to cache media selection: $e');
      }
    }
  }

  // Get cached media asset for a query
  Future<String?> getCachedMediaAsset(String query) async {
    final uid = _currentUserId;
    if (uid == null) {
      return null;
    }

    try {
      final queryHash = _hashQuery(query);

      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('media_cache')
          .doc(queryHash)
          .get();

      if (doc.exists) {
        return doc.data()?['selected_asset_id'] as String?;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Warning: Failed to get cached media asset: $e');
      }
    }

    return null;
  }

  // Get user preferences
  Future<Map<String, dynamic>> getUserPreferences() async {
    final uid = _currentUserId;
    if (uid == null) {
      // Return default preferences if not authenticated
      return {
        'default_platforms': ['instagram', 'twitter'],
        'default_hashtags': [],
        'auto_location': true,
        'signature': '',
        'media_albums': [], // Empty list means use default "All Photos"
      };
    }

    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('user_preferences')
          .doc('settings')
          .get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        // Ensure media_albums exists, default to empty list if not
        if (!data.containsKey('media_albums')) {
          data['media_albums'] = [];
        }
        return data;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Warning: Failed to get user preferences: $e');
      }
    }

    // Return default preferences if none exist or on error
    return {
      'default_platforms': ['instagram', 'twitter'],
      'default_hashtags': [],
      'auto_location': true,
      'signature': '',
      'media_albums': [], // Empty list means use default "All Photos"
    };
  }

  // Get selected media album IDs
  Future<List<String>> getSelectedMediaAlbums() async {
    final prefs = await getUserPreferences();
    final albumIds = prefs['media_albums'] as List<dynamic>? ?? [];
    return albumIds.map((id) => id.toString()).toList();
  }

  // Update selected media albums
  Future<void> updateSelectedMediaAlbums(List<String> albumIds) async {
    final uid = _currentUserId;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('user_preferences')
          .doc('settings')
          .set({
        'media_albums': albumIds,
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to update selected media albums: $e');
    }
  }

  // Update user preferences
  Future<void> updateUserPreferences(Map<String, dynamic> prefs) async {
    final uid = _currentUserId;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('user_preferences')
          .doc('settings')
          .set(prefs, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to update user preferences: $e');
    }
  }

  // Get a stream of actions for the history screen
  Stream<QuerySnapshot> getActionsStream() {
    final uid = _currentUserId;
    if (uid == null) {
      // Return empty stream if not authenticated
      return const Stream.empty();
    }

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('actions')
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  // Get a specific action by ID
  Future<DocumentSnapshot?> getAction(String actionId) async {
    final uid = _currentUserId;
    if (uid == null) {
      return null;
    }

    try {
      return await _firestore
          .collection('users')
          .doc(uid)
          .collection('actions')
          .doc(actionId)
          .get();
    } catch (e) {
      if (kDebugMode) {
        print('Warning: Failed to get action: $e');
      }
      return null;
    }
  }

  // Helper to hash a query string for media cache
  String _hashQuery(String query) {
    final bytes = utf8.encode(query.toLowerCase().trim());
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
