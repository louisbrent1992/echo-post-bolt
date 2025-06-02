import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Save a new social action to Firestore
  Future<void> saveAction(Map<String, dynamic> actionJson) async {
    final uid = _auth.currentUser!.uid;
    final actionId = actionJson['action_id'];

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
  }

  // Update an existing action
  Future<void> updateAction(String actionId, Map<String, dynamic> updatedJson) async {
    final uid = _auth.currentUser!.uid;
    
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('actions')
        .doc(actionId)
        .update({
      'action_json': updatedJson,
    });
  }

  // Delete an action
  Future<void> deleteAction(String actionId) async {
    final uid = _auth.currentUser!.uid;
    
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('actions')
        .doc(actionId)
        .delete();
  }

  // Cache media selection for a query
  Future<void> cacheMediaSelection(String query, String assetId) async {
    final uid = _auth.currentUser!.uid;
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
  }

  // Get cached media asset for a query
  Future<String?> getCachedMediaAsset(String query) async {
    final uid = _auth.currentUser!.uid;
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
    
    return null;
  }

  // Get user preferences
  Future<Map<String, dynamic>> getUserPreferences() async {
    final uid = _auth.currentUser!.uid;
    
    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('user_preferences')
        .doc('settings')
        .get();
    
    if (doc.exists) {
      return doc.data() ?? {};
    }
    
    // Return default preferences if none exist
    return {
      'default_platforms': ['instagram', 'twitter'],
      'default_hashtags': [],
      'auto_location': true,
      'signature': '',
    };
  }

  // Update user preferences
  Future<void> updateUserPreferences(Map<String, dynamic> prefs) async {
    final uid = _auth.currentUser!.uid;
    
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('user_preferences')
        .doc('settings')
        .set(prefs, SetOptions(merge: true));
  }

  // Get a stream of actions for the history screen
  Stream<QuerySnapshot> getActionsStream() {
    final uid = _auth.currentUser!.uid;
    
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('actions')
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  // Get a specific action by ID
  Future<DocumentSnapshot?> getAction(String actionId) async {
    final uid = _auth.currentUser!.uid;
    
    return await _firestore
        .collection('users')
        .doc(uid)
        .collection('actions')
        .doc(actionId)
        .get();
  }

  // Helper to hash a query string for media cache
  String _hashQuery(String query) {
    final bytes = utf8.encode(query.toLowerCase().trim());
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}