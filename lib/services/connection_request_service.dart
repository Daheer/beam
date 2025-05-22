import 'package:beam/services/log_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/connection_request.dart';
import '../services/notification_service.dart';

class ConnectionRequestService {
  static final ConnectionRequestService _singleton =
      ConnectionRequestService._internal();
  factory ConnectionRequestService() => _singleton;
  ConnectionRequestService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();

  // Send a connection request
  Future<String?> sendConnectionRequest(String receiverId) async {
    try {
      final sender = _auth.currentUser;
      if (sender == null) {
        return null;
      }

      // Check if we already have a pending request for this receiver
      try {
        final existingRequests =
            await _firestore
                .collection('connectionRequests')
                .where('senderId', isEqualTo: sender.uid)
                .where('receiverId', isEqualTo: receiverId)
                .where(
                  'status',
                  isEqualTo:
                      ConnectionRequestStatus.pending
                          .toString()
                          .split('.')
                          .last,
                )
                .get();

        if (existingRequests.docs.isNotEmpty) {
          return existingRequests.docs.first.id;
        }
      } catch (e) {
        // Continue execution to try creating a new request
      }

      // Create a new request document
      try {
        final requestRef = _firestore.collection('connectionRequests').doc();

        await requestRef.set({
          'senderId': sender.uid,
          'receiverId': receiverId,
          'status': ConnectionRequestStatus.pending.toString().split('.').last,
          'createdAt': FieldValue.serverTimestamp(),
        });

        return requestRef.id;
      } catch (e) {
        throw e;
      }
    } catch (e) {
      return null;
    }
  }

  // Accept a connection request
  Future<bool> acceptConnectionRequest(String requestId) async {
    try {
      // Update the request status
      await _firestore.collection('connectionRequests').doc(requestId).update({
        'status': ConnectionRequestStatus.accepted.toString().split('.').last,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  // Reject a connection request
  Future<bool> rejectConnectionRequest(String requestId) async {
    try {
      // Update the request status
      await _firestore.collection('connectionRequests').doc(requestId).update({
        'status': ConnectionRequestStatus.rejected.toString().split('.').last,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  // Get connection requests for current user
  Stream<QuerySnapshot> getReceivedConnectionRequests() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }

    return _firestore
        .collection('connectionRequests')
        .where('receiverId', isEqualTo: currentUser.uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Set up real-time listener for new connection requests
  Stream<QuerySnapshot> getNewConnectionRequests() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }

    // Only listen for pending connection requests where user is the receiver
    return _firestore
        .collection('connectionRequests')
        .where('receiverId', isEqualTo: currentUser.uid)
        .where(
          'status',
          isEqualTo: ConnectionRequestStatus.pending.toString().split('.').last,
        )
        .snapshots();
  }

  // Check for pending connection requests and trigger notifications
  Future<void> checkForPendingRequests(
    Function(String, String, String) showNotification,
  ) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final requests =
          await _firestore
              .collection('connectionRequests')
              .where('receiverId', isEqualTo: currentUser.uid)
              .where(
                'status',
                isEqualTo:
                    ConnectionRequestStatus.pending.toString().split('.').last,
              )
              .get();

      // Process each pending request
      for (var doc in requests.docs) {
        final requestData = doc.data();
        final senderId = requestData['senderId'] as String;

        // Get sender info
        final senderDoc =
            await _firestore.collection('users').doc(senderId).get();
        if (senderDoc.exists) {
          final senderData = senderDoc.data() ?? {};
          final senderName = senderData['name'] ?? 'Someone';

          // Show notification for this request
          showNotification(senderId, senderName, doc.id);
        }
      }
    } catch (e) {
      LogService.e(
        'Error checking pending connection requests',
        e,
        StackTrace.current,
      );
    }
  }

  // Check if there is a mutual connection (established when either user accepts a request)
  Future<bool> checkMutualConnection(String otherUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // Check if either user has accepted the other's request
      final acceptedRequests =
          await _firestore
              .collection('connectionRequests')
              .where(
                Filter.or(
                  Filter.and(
                    Filter('senderId', isEqualTo: currentUser.uid),
                    Filter('receiverId', isEqualTo: otherUserId),
                  ),
                  Filter.and(
                    Filter('senderId', isEqualTo: otherUserId),
                    Filter('receiverId', isEqualTo: currentUser.uid),
                  ),
                ),
              )
              .where(
                'status',
                isEqualTo:
                    ConnectionRequestStatus.accepted.toString().split('.').last,
              )
              .limit(1)
              .get();

      final hasMutualConnection = acceptedRequests.docs.isNotEmpty;

      return hasMutualConnection;
    } catch (e) {
      return false;
    }
  }

  // Check if user can call another user (requires mutual connection)
  Future<bool> canCall(String otherUserId) async {
    return await checkMutualConnection(otherUserId);
  }
}
