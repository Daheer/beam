import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io' show Platform;

class NotificationService {
  static final NotificationService _singleton = NotificationService._internal();
  factory NotificationService() => _singleton;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Flag to track if we're running on a simulator
  bool _isSimulator = false;

  // Android notification channel
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Initialize the service
  Future<void> initialize() async {
    try {
      // Setup notification channels for Android
      if (Platform.isAndroid) {
        try {
          await _createAndroidNotificationChannel();
        } catch (e) {
          debugPrint('Error creating Android notification channel: $e');
          // Continue even if local notifications fail
        }
      }

      // Request permission on iOS
      if (Platform.isIOS) {
        try {
          NotificationSettings settings = await _messaging.requestPermission(
            alert: true,
            badge: true,
            sound: true,
            provisional: false,
            criticalAlert: true,
          );

          if (settings.authorizationStatus != AuthorizationStatus.authorized) {
            debugPrint(
              'User declined or has not accepted notifications permission',
            );
          }

          // iOS: Get APNS token first - this is required before getting FCM token
          try {
            String? apnsToken = await _messaging.getAPNSToken();
            debugPrint('APNS Token: $apnsToken');

            // Check if we're on a simulator (APNS token will be null)
            if (apnsToken == null) {
              _isSimulator = true;
              debugPrint(
                'Running on iOS simulator - push notifications will not work',
              );
            } else {
              // Wait a moment to ensure APNS token is properly registered
              await Future.delayed(const Duration(seconds: 1));
            }
          } catch (e) {
            debugPrint('Error getting APNS token: $e');
            // Assume we might be on a simulator if there's an error
            _isSimulator = true;
          }
        } catch (e) {
          debugPrint('Error requesting iOS notification permissions: $e');
          // Continue even if permissions fail
        }
      }

      // Get FCM token (skip if we're on a simulator)
      try {
        // We first check for any initial notification that might have opened the app
        RemoteMessage? initialMessage = await _messaging.getInitialMessage();
        if (initialMessage != null) {
          debugPrint('App was opened by notification: ${initialMessage.data}');
        }

        // If we're on iOS simulator, we'll skip trying to get an FCM token
        // to avoid the error message, but we'll still set up listeners
        if (Platform.isIOS && _isSimulator) {
          debugPrint('Skipping FCM token retrieval on iOS simulator');
        } else {
          // Then get the FCM token
          String? token = await _messaging.getToken();
          if (token != null) {
            debugPrint('Successfully obtained FCM token: $token');
            await _saveTokenToFirestore(token);
          } else {
            debugPrint('FCM token is null');
          }
        }

        // Listen for token refreshes
        _messaging.onTokenRefresh.listen((String token) {
          debugPrint('FCM token refreshed: $token');
          _saveTokenToFirestore(token);
        });
      } catch (e) {
        debugPrint('Error getting FCM token: $e');
        // Continue even if token retrieval fails
      }
    } catch (e) {
      // Catch any other errors that might occur during initialization
      debugPrint('Error initializing notification service: $e');
    }
  }

  // Create Android notification channel for calls
  Future<void> _createAndroidNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'Call Notifications',
      description: 'This channel is used for call notifications',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('call_ringtone'),
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    // Initialize local notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_notification');

    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (
        NotificationResponse notificationResponse,
      ) {
        // Handle notification tap
        debugPrint('Notification tapped: ${notificationResponse.payload}');
      },
    );
  }

  // Save FCM token to Firestore for the current user
  Future<void> _saveTokenToFirestore(String token) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).update({
        'fcmToken': token,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Send call notification
  Future<void> sendCallNotification({
    required String receiverId,
    required String callerName,
    required String channelName,
  }) async {
    try {
      // Get receiver's FCM token
      final receiverDoc =
          await _firestore.collection('users').doc(receiverId).get();
      if (!receiverDoc.exists) {
        debugPrint('Receiver document does not exist');
        return;
      }

      final receiverData = receiverDoc.data();
      if (receiverData == null || !receiverData.containsKey('fcmToken')) {
        debugPrint('Receiver FCM token not found');
        return;
      }

      final fcmToken = receiverData['fcmToken'] as String?;
      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint('Invalid FCM token');
        return;
      }

      // Create notification data
      final data = {
        'token': fcmToken,
        'notification': {
          'title': 'Incoming Call',
          'body': '$callerName is trying to connect with you on Beam',
        },
        'data': {
          'type': 'call',
          'channelName': channelName,
          'callerId': _auth.currentUser?.uid ?? '',
          'callerName': callerName,
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
        'android': {
          'priority': 'high',
          'notification': {
            'channel_id': 'high_importance_channel',
            'priority': 'high',
            'sound': 'call_ringtone',
            'default_sound': true,
            'default_vibrate_timings': true,
          },
        },
        'apns': {
          'headers': {'apns-priority': '10'},
          'payload': {
            'aps': {
              'sound': 'default',
              'category': 'call',
              'content-available': 1,
            },
          },
        },
      };

      // Store the notification in Firestore, which will trigger a Cloud Function or server to send it
      // This approach avoids using Firebase Functions and keeps credentials secure
      await _firestore.collection('notifications').add({
        'to': fcmToken,
        'message': data,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
    } catch (e) {
      debugPrint('Error sending call notification: $e');
    }
  }

  // Handle incoming notifications in foreground
  void setupForegroundNotificationHandling() {
    try {
      FirebaseMessaging.onMessage.listen(
        (RemoteMessage message) {
          // When a message arrives, the app will handle it
          // No need to display a notification as the app is in foreground
          // You can process the data or trigger events based on the notification
          debugPrint('Got a message whilst in the foreground!');
          debugPrint('Message data: ${message.data}');

          if (message.notification != null) {
            debugPrint(
              'Message also contained a notification: ${message.notification}',
            );
          }
        },
        onError: (error) {
          debugPrint('Error in foreground message handling: $error');
        },
      );
    } catch (e) {
      debugPrint('Error setting up foreground message handler: $e');
    }
  }
}
