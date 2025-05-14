import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../pages/audio_call_page.dart';

class CallService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription<QuerySnapshot>? _callsSubscription;

  // Initialize call listener
  void initCallListener(BuildContext context) {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    // Cancel any existing subscription first
    _callsSubscription?.cancel();

    // First, clean up any stale calls
    _cleanupStaleCalls(currentUserId);

    // Listen for incoming calls where the user is the callee
    _callsSubscription = _firestore
        .collection('calls')
        .where('callee', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'initiated')
        .snapshots()
        .listen(
          (snapshot) {
            for (var change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                print('New incoming call detected: ${change.doc.id}');
                _handleIncomingCall(context, change.doc);
              }
            }
          },
          onError: (error) {
            print('Error listening for calls: $error');
          },
        );
  }

  // Clean up stale calls that might be stuck in 'initiated' state
  Future<void> _cleanupStaleCalls(String userId) async {
    try {
      // Get calls that are more than 30 seconds old and still in 'initiated' state
      final thirtySecondsAgo = DateTime.now().subtract(Duration(seconds: 30));

      // Clean up calls where user is callee
      final calleeSnapshot =
          await _firestore
              .collection('calls')
              .where('callee', isEqualTo: userId)
              .where('status', isEqualTo: 'initiated')
              .get();

      for (var doc in calleeSnapshot.docs) {
        final data = doc.data();
        final timestamp = data['timestamp'] as Timestamp?;

        // If the call is old or has no timestamp, mark it as missed
        if (timestamp == null ||
            timestamp.toDate().isBefore(thirtySecondsAgo)) {
          await doc.reference.update({
            'status': 'missed',
            'endedAt': FieldValue.serverTimestamp(),
          });
          print('Cleaned up stale incoming call: ${doc.id}');
        }
      }

      // Also clean up outgoing calls that never connected
      final callerSnapshot =
          await _firestore
              .collection('calls')
              .where('caller', isEqualTo: userId)
              .where('status', isEqualTo: 'initiated')
              .get();

      for (var doc in callerSnapshot.docs) {
        final data = doc.data();
        final timestamp = data['timestamp'] as Timestamp?;

        // If the call is old or has no timestamp, mark it as missed
        if (timestamp == null ||
            timestamp.toDate().isBefore(thirtySecondsAgo)) {
          await doc.reference.update({
            'status': 'no_answer',
            'endedAt': FieldValue.serverTimestamp(),
          });
          print('Cleaned up stale outgoing call: ${doc.id}');
        }
      }
    } catch (e) {
      print('Error cleaning up stale calls: $e');
    }
  }

  // Handle incoming call
  void _handleIncomingCall(BuildContext context, DocumentSnapshot callDoc) {
    final callData = callDoc.data() as Map<String, dynamic>;
    final callerId = callData['caller'] as String?;

    if (callerId == null) return;

    // Fetch caller's user profile
    _firestore
        .collection('users')
        .doc(callerId)
        .get()
        .then((userDoc) {
          if (!userDoc.exists) return;

          final userData = userDoc.data() as Map<String, dynamic>;
          final professional = {
            'id': callerId,
            'name': userData['name'] ?? 'Unknown Caller',
            'profession': userData['profession'] ?? '',
            'image': userData['profilePicture'],
          };

          // Show incoming call UI
          _showIncomingCallDialog(context, callDoc.id, professional);
        })
        .catchError((error) {
          print('Error fetching caller data: $error');
        });
  }

  // Show incoming call dialog
  void _showIncomingCallDialog(
    BuildContext context,
    String callId,
    Map<String, dynamic> caller,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => IncomingCallDialog(
            caller: caller,
            callId: callId,
            onAccept: () {
              Navigator.pop(context); // Close the dialog

              // Navigate to the call screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => AudioCallPage(
                        professional: caller,
                        isIncoming: true,
                        roomId: callId,
                      ),
                ),
              );
            },
            onDecline: () {
              // Update call status to declined
              _firestore
                  .collection('calls')
                  .doc(callId)
                  .update({
                    'status': 'declined',
                    'endedAt': FieldValue.serverTimestamp(),
                  })
                  .catchError((error) {
                    print('Error declining call: $error');
                  });

              Navigator.pop(context); // Close the dialog
            },
          ),
    );
  }

  // Cleanup resources
  void dispose() {
    _callsSubscription?.cancel();
    _callsSubscription = null;
  }
}

// Incoming call dialog widget
class IncomingCallDialog extends StatelessWidget {
  final Map<String, dynamic> caller;
  final String callId;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const IncomingCallDialog({
    Key? key,
    required this.caller,
    required this.callId,
    required this.onAccept,
    required this.onDecline,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              image:
                  caller['image'] != null
                      ? DecorationImage(
                        image: NetworkImage(caller['image']),
                        fit: BoxFit.cover,
                      )
                      : null,
              color: Colors.grey[200],
            ),
            child:
                caller['image'] == null
                    ? const Icon(Icons.person, size: 40, color: Colors.grey)
                    : null,
          ),
          const SizedBox(height: 16),
          Text('Incoming Call', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            caller['name'] ?? 'Unknown',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            caller['profession'] ?? '',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.red,
                child: IconButton(
                  icon: const Icon(Icons.call_end, color: Colors.white),
                  onPressed: onDecline,
                ),
              ),
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.green,
                child: IconButton(
                  icon: const Icon(Icons.call, color: Colors.white),
                  onPressed: onAccept,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
