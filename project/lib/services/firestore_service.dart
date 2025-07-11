import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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

  // Delete an action by document ID (for corrupted posts)
  Future<void> deleteActionById(String docId) async {
    final uid = _currentUserId;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('actions')
          .doc(docId)
          .delete();
    } catch (e) {
      throw Exception('Failed to delete action by ID: $e');
    }
  }

  // Clear all actions (for clear history functionality)
  Future<void> clearAllActions() async {
    final uid = _currentUserId;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Get all action documents for this user
      final querySnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('actions')
          .get();

      // Delete all documents in batches
      final batch = _firestore.batch();
      for (final doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to clear all actions: $e');
    }
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
}
