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
      // Request permissions for ALL platforms
      try {
        NotificationSettings settings = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
          criticalAlert: true,
          announcement: true,
        );

        debugPrint(
          'User notification permission status: ${settings.authorizationStatus}',
        );

        if (settings.authorizationStatus != AuthorizationStatus.authorized) {
          debugPrint(
            'User declined or has not accepted notification permissions',
          );
        }
      } catch (e) {
        debugPrint('Error requesting notification permissions: $e');
      }

      // Setup notification channels for Android
      if (Platform.isAndroid) {
        try {
          await _createAndroidNotificationChannel();
        } catch (e) {
          debugPrint('Error creating Android notification channel: $e');
          // Continue even if local notifications fail
        }
      }

      // iOS: Get APNS token first - this is required before getting FCM token
      if (Platform.isIOS) {
        try {
          String? apnsToken = await _messaging.getAPNSToken();
          debugPrint('Initial APNS Token: $apnsToken');

          // If APNS token is null, wait and try again
          if (apnsToken == null) {
            // Wait for 3 seconds
            await Future.delayed(const Duration(seconds: 3));
            apnsToken = await _messaging.getAPNSToken();
            debugPrint('APNS Token after delay: $apnsToken');

            // Check if we're on a simulator
            if (apnsToken == null) {
              _isSimulator = true;
              debugPrint(
                'Running on iOS simulator - push notifications will not work',
              );
            }
          }
        } catch (e) {
          debugPrint('Error getting APNS token: $e');
          // Assume we might be on a simulator if there's an error
          _isSimulator = true;
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
    try {
      debugPrint('Creating Android notification channels');

      // Create channel for calls
      const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
        'high_importance_channel',
        'Call Notifications',
        description: 'This channel is used for call notifications',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('call_ringtone'),
      );

      // Create channel for interest requests
      const AndroidNotificationChannel interestChannel =
          AndroidNotificationChannel(
            'interest_channel',
            'Interest Request Notifications',
            description:
                'This channel is used for interest request notifications',
            importance: Importance.high,
            enableVibration: true,
            playSound: true,
          );

      // Get plugin
      final androidPlugin =
          flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(callChannel);
        await androidPlugin.createNotificationChannel(interestChannel);
        debugPrint('Android notification channels created successfully');
      } else {
        debugPrint('Could not resolve Android notification plugin');
      }

      // Initialize local notifications
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@drawable/ic_notification');

      final DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
            onDidReceiveLocalNotification: (id, title, body, payload) {
              debugPrint(
                'Received local notification: $id, $title, $body, $payload',
              );
              return;
            },
          );

      final InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsIOS,
          );

      final success = await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (
          NotificationResponse notificationResponse,
        ) {
          // Handle notification tap
          debugPrint('Notification tapped: ${notificationResponse.payload}');
        },
      );

      debugPrint('Notification plugin initialization result: $success');
    } catch (e) {
      debugPrint('Error initializing notification channels: $e');
    }
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

  // Send interest request notification
  Future<void> sendInterestNotification({
    required String receiverId,
    required String senderName,
    required String requestId,
    String? title,
    String? body,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        debugPrint('No authenticated user found');
        return;
      }

      debugPrint('Sending notification from ${currentUser.uid} to $receiverId');
      debugPrint('Title: $title');
      debugPrint('Body: $body');

      // Get receiver's FCM token
      final receiverDoc =
          await _firestore.collection('users').doc(receiverId).get();
      if (!receiverDoc.exists) {
        debugPrint('Receiver document does not exist: $receiverId');
        return;
      }

      final receiverData = receiverDoc.data();
      if (receiverData == null || !receiverData.containsKey('fcmToken')) {
        debugPrint('Receiver FCM token not found for user: $receiverId');
        return;
      }

      final fcmToken = receiverData['fcmToken'] as String?;
      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint('Invalid FCM token for user: $receiverId');
        return;
      }

      debugPrint('Found FCM token for receiver: $receiverId');

      // Create notification data
      final data = {
        'token': fcmToken,
        'notification': {
          'title': title ?? 'New Interest Request',
          'body': body ?? '$senderName is interested in connecting with you',
        },
        'data': {
          'type': 'interest_request',
          'requestId': requestId,
          'senderId': currentUser.uid,
          'senderName': senderName,
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
        'android': {
          'priority': 'high',
          'notification': {
            'channel_id': 'interest_channel',
            'priority': 'high',
          },
        },
        'apns': {
          'headers': {'apns-priority': '5'},
          'payload': {
            'aps': {
              'sound': 'default',
              'category': 'interest',
              'content-available': 1,
            },
          },
        },
      };

      // Store the notification in Firestore
      await _firestore.collection('notifications').add({
        'to': fcmToken,
        'message': data,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });

      debugPrint('Notification stored in Firestore for processing');

      // Show a local notification if the receiver is using the app
      // and it's not a self-notification
      if (receiverId != currentUser.uid) {
        debugPrint('Showing local notification for receiver: $receiverId');
        _showForegroundNotification(
          title:
              (data['notification'] as Map<String, dynamic>)['title'] as String,
          body:
              (data['notification'] as Map<String, dynamic>)['body'] as String,
          payload:
              '{"type":"interest_request","requestId":"$requestId","senderId":"${currentUser.uid}","senderName":"$senderName"}',
        );
      } else {
        debugPrint(
          'Skipping local notification as sender and receiver are the same',
        );
      }
    } catch (e) {
      debugPrint('Error sending interest notification: $e');
    }
  }

  // Handle incoming notifications in foreground
  void setupForegroundNotificationHandling() {
    try {
      FirebaseMessaging.onMessage.listen(
        (RemoteMessage message) {
          // When a message arrives in the foreground, display a notification
          debugPrint('Got a foreground message: ${message.messageId}');
          debugPrint('Message data: ${message.data}');
          debugPrint(
            'Notification: ${message.notification?.title}, ${message.notification?.body}',
          );

          String title = '';
          String body = '';

          // Get title and body from notification or data payload
          if (message.notification != null) {
            title = message.notification!.title ?? 'New Notification';
            body = message.notification!.body ?? 'You have a new notification';
            debugPrint('Using notification data for alert: $title, $body');
          } else if (message.data.containsKey('title') &&
              message.data.containsKey('body')) {
            title = message.data['title'];
            body = message.data['body'];
            debugPrint('Using data payload for alert: $title, $body');
          } else {
            title = 'New Message';
            body = 'You received a new message';
            debugPrint('Using default alert text');
          }

          // Always show a notification when a message is received in foreground
          _showForegroundNotification(
            title: title,
            body: body,
            payload: message.data.toString(),
          );
        },
        onError: (error) {
          debugPrint('Error in foreground message handling: $error');
        },
      );

      // Also initialize the notification tap handler
      _setupNotificationTapHandling();

      debugPrint('Foreground notification handling setup complete');
    } catch (e) {
      debugPrint('Error setting up foreground message handler: $e');
    }
  }

  // Setup handling for notification taps
  void _setupNotificationTapHandling() {
    flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification tapped with payload: ${response.payload}');

        // Try to parse the payload and handle accordingly
        try {
          if (response.payload != null) {
            final data = response.payload!;
            if (data.contains('interest_request')) {
              debugPrint('Interest request notification tapped');

              // The navigation will need to be handled elsewhere since we don't have context here
              // But we can broadcast an event that can be listened to in the app
            }
          }
        } catch (e) {
          debugPrint('Error handling notification tap: $e');
        }
      },
    );
  }

  // Show a local notification when the app is in foreground
  Future<void> _showForegroundNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'high_importance_channel',
          'Important Notifications',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
        );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      platformDetails,
      payload: payload,
    );
  }
}
