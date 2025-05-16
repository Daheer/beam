import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum CallStatus { idle, calling, ringing, connected, ended, rejected, missed }

class CallService {
  static final CallService _singleton = CallService._internal();
  factory CallService() => _singleton;
  CallService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Create a call document in Firestore
  Future<String?> initiateCall(String receiverId) async {
    try {
      final caller = _auth.currentUser;
      if (caller == null) return null;

      // Generate a unique channel name using timestamp
      final channelName = DateTime.now().millisecondsSinceEpoch.toString();

      // Create a call document
      await _firestore.collection('calls').doc(channelName).set({
        'channelName': channelName,
        'callerId': caller.uid,
        'receiverId': receiverId,
        'status': CallStatus.calling.toString(),
        'timestamp': FieldValue.serverTimestamp(),
        'callerName': caller.displayName ?? 'Unknown Caller',
        // We'll let Agora SDK generate the UIDs by passing 0
        'callerAgoraUid': 0,
        'receiverAgoraUid': 0,
      });

      return channelName;
    } catch (e) {
      debugPrint('Error initiating call: $e');
      return null;
    }
  }

  // Listen for incoming calls
  Stream<QuerySnapshot> listenForCalls() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }

    // Get active calls where the current user is the receiver
    return _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: CallStatus.calling.toString())
        .snapshots();
  }

  // Update call status
  Future<void> updateCallStatus(String channelName, CallStatus status) async {
    try {
      await _firestore.collection('calls').doc(channelName).update({
        'status': status.toString(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating call status: $e');
    }
  }

  // End the call
  Future<void> endCall(String channelName) async {
    try {
      await _firestore.collection('calls').doc(channelName).update({
        'status': CallStatus.ended.toString(),
        'endTimestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error ending call: $e');
    }
  }

  // Clean up old calls
  Future<void> cleanupOldCalls() async {
    try {
      final oldCalls =
          await _firestore
              .collection('calls')
              .where(
                'timestamp',
                isLessThan: DateTime.now().subtract(const Duration(hours: 24)),
              )
              .get();

      for (var doc in oldCalls.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('Error cleaning up old calls: $e');
    }
  }
}
