import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/snackbar_service.dart';
import '../pages/activity_history_page.dart';
import 'dart:convert';

/// Handle a notification payload when the app is opened from a terminated state
class NotificationPayloadHandler {
  static final _firestore = FirebaseFirestore.instance;

  static Future<void> handle(BuildContext context, String payload) async {
    try {
      final data = Map<String, dynamic>.from(json.decode(payload));
      final senderId = data['senderId'] as String;
      final requestId = data['requestId'] as String;

      // For all notification types, navigate to activity history page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) =>
                  ActivityHistoryPage(notificationRequestId: requestId),
        ),
      );

      // Show additional info for connection requests
      if (data['type'] == 'connection_request') {
        // Get sender info
        final senderDoc =
            await _firestore.collection('users').doc(senderId).get();
        final senderData = senderDoc.data() ?? {};
        final senderName = senderData['name'] ?? 'Someone';

        // Show a toast message about the connection request
        SnackbarService.showInfo(
          context,
          message: '$senderName wants to connect with you',
        );
      }
    } catch (e) {
      debugPrint('Error handling notification payload: $e');
    }
  }
}
