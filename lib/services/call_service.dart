import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/log_service.dart';
import 'notification_service.dart';

enum CallStatus { idle, calling, ringing, connected, ended, rejected, missed }

class CallService {
  static final CallService _singleton = CallService._internal();
  factory CallService() => _singleton;
  CallService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();

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

      // Send push notification to receiver
      await _notificationService.sendCallNotification(
        receiverId: receiverId,
        callerName: caller.displayName ?? 'Unknown Caller',
        channelName: channelName,
      );

      return channelName;
    } catch (e) {
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
      LogService.e('Error updating call status', e, StackTrace.current);
    }
  }

  // End the call
  Future<void> endCall(String channelName) async {
    try {
      final callDoc =
          await _firestore.collection('calls').doc(channelName).get();
      if (!callDoc.exists) return;

      final callData = callDoc.data()!;
      final callerId = callData['callerId'] as String;
      final receiverId = callData['receiverId'] as String;

      // Update call status
      await _firestore.collection('calls').doc(channelName).update({
        'status': CallStatus.ended.toString(),
        'endTimestamp': FieldValue.serverTimestamp(),
      });

      // Update connection request to mark that a call has been made
      final connectionRequests =
          await _firestore
              .collection('connectionRequests')
              .where(
                Filter.or(
                  Filter.and(
                    Filter('senderId', isEqualTo: callerId),
                    Filter('receiverId', isEqualTo: receiverId),
                  ),
                  Filter.and(
                    Filter('senderId', isEqualTo: receiverId),
                    Filter('receiverId', isEqualTo: callerId),
                  ),
                ),
              )
              .limit(1)
              .get();

      if (connectionRequests.docs.isNotEmpty) {
        await connectionRequests.docs.first.reference.update({
          'hasCalledBefore': true,
          'lastCallAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      LogService.e('Error ending call', e, StackTrace.current);
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
      LogService.e('Error cleaning up old calls', e, StackTrace.current);
    }
  }

  // Share contact during call
  Future<bool> shareContact(String channelName, String otherUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // Get current user's email from Firestore
      final userDoc =
          await _firestore.collection('users').doc(currentUser.uid).get();
      final userEmail = userDoc.data()?['email'] as String?;

      if (userEmail == null) {
        return false;
      }

      // Update connection request with the shared email
      final connectionRequests =
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
              .limit(1)
              .get();

      if (connectionRequests.docs.isEmpty) {
        return false;
      }

      final connectionRequest = connectionRequests.docs.first;
      final isUserSender =
          connectionRequest.data()['senderId'] == currentUser.uid;

      // Update the appropriate email field
      await connectionRequest.reference.update({
        if (isUserSender)
          'senderEmail': userEmail
        else
          'receiverEmail': userEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  // Check if contact was shared in a call
  Future<bool> wasContactShared(String callId) async {
    try {
      final callDoc = await _firestore.collection('calls').doc(callId).get();
      return (callDoc.data()?['contactShared'] as bool?) ?? false;
    } catch (e) {
      return false;
    }
  }

  // Get shared contact details
  Future<String?> getSharedEmail(String otherUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;

      // Check if there's a shared contact record between the users
      final sharedContacts =
          await _firestore
              .collection('sharedContacts')
              .where('fromUserId', isEqualTo: otherUserId)
              .where('toUserId', isEqualTo: currentUser.uid)
              .limit(1)
              .get();

      if (sharedContacts.docs.isEmpty) return null;

      // Get the shared email from the shared contact record
      return sharedContacts.docs.first.data()['sharedEmail'] as String?;
    } catch (e) {
      return null;
    }
  }

  // Check if users have had a call before
  Future<bool> hasCalledBefore(String otherUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // Check for any completed calls between the users
      final calls =
          await _firestore
              .collection('calls')
              .where(
                Filter.or(
                  Filter.and(
                    Filter('callerId', isEqualTo: currentUser.uid),
                    Filter('receiverId', isEqualTo: otherUserId),
                  ),
                  Filter.and(
                    Filter('callerId', isEqualTo: otherUserId),
                    Filter('receiverId', isEqualTo: currentUser.uid),
                  ),
                ),
              )
              .where('status', isEqualTo: CallStatus.ended.toString())
              .limit(1)
              .get();

      return calls.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
