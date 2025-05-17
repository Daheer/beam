import 'package:flutter/material.dart';
import '../services/snackbar_service.dart';

/// Handle a notification payload when the app is opened from a terminated state
Future<void> handleNotificationPayload(
  BuildContext context,
  Map<String, dynamic>? data,
) async {
  if (data == null) return;

  if (data.containsKey('type') && data['type'] == 'call') {
    final String? channelName = data['channelName'];
    final String? callerId = data['callerId'];
    final String? callerName = data['callerName'];

    if (channelName != null && callerId != null) {
      // The call might have ended if the notification was received a while ago
      // HomePage listens to active calls, so it will automatically handle this
      // if the call is still active

      // Inform the user about the missed call if needed
      SnackbarService.showInfo(
        context,
        message: 'You have a call from $callerName',
      );
    }
  }
}
