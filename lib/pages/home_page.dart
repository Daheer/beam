// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../widgets/beam_blob.dart';
import '../widgets/nearby_professional_card.dart';
import '../widgets/platform_loading_indicator.dart';
import '../services/user_service.dart';
import '../services/call_service.dart';
import '../utils/notification_payload_handler.dart';
import 'all_professionals_page.dart';
import 'user_profile_page.dart';
import 'voice_call_page.dart';
import 'activity_history_page.dart';
import '../services/snackbar_service.dart';
import '../services/log_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/connection_request_service.dart';
import 'dart:convert';

// Call button widget for both incoming call dialog and call page
class _CallButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final double size;

  const _CallButton({
    required this.onPressed,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    // ignore: unused_element_parameter
    this.size = 55,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        shape: const CircleBorder(),
        color: backgroundColor,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Icon(icon, color: iconColor, size: size * 0.5),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final UserService _userService = UserService();
  final CallService _callService = CallService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ConnectionRequestService _connectionService =
      ConnectionRequestService();
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  List<Map<String, dynamic>> _nearbyUsers = [];
  bool _isLoading = true;
  bool _isLocationEnabled = false;
  StreamSubscription<QuerySnapshot>? _incomingCallsSubscription;
  StreamSubscription<QuerySnapshot>? _interestRequestsSubscription;
  bool isBeaming = false;
  StreamSubscription? _callSubscription;
  StreamSubscription<QuerySnapshot>? _connectionRequestsSubscription;
  StreamSubscription<QuerySnapshot>? _nearbyUsersSubscription;
  int _pendingRequestsCount = 0;

  @override
  void initState() {
    super.initState();

    // Add app lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    _loadUserStatus();
    _loadNearbyUsers();
    _initializeNotifications();
    _listenForIncomingCalls();
    _setupInterestRequestListener();
    _setupConnectionRequestListener();
    _setupNearbyUsersListener();
    _loadPendingRequestsCount();

    // Check for any pending interest requests when the app starts
    _checkForPendingRequests();

    // Set up notification handling
    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message,
    ) {
      if (message != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          NotificationPayloadHandler.handle(context, json.encode(message.data));
        });
      }
    });
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    _incomingCallsSubscription?.cancel();
    _interestRequestsSubscription?.cancel();
    _connectionRequestsSubscription?.cancel();
    _nearbyUsersSubscription?.cancel();

    // Remove app lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  // Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground - check for pending requests
      _checkForPendingRequests();
    }
  }

  // Check for pending interest requests
  void _checkForPendingRequests() {
    _connectionService.checkForPendingRequests((
      senderId,
      senderName,
      requestId,
    ) {
      _showInterestRequestNotification(
        senderId: senderId,
        senderName: senderName,
        requestId: requestId,
      );
    });
  }

  // Set up real-time listener for interest requests
  void _setupInterestRequestListener() {
    _connectionRequestsSubscription = _connectionService
        .getNewConnectionRequests()
        .listen(
          (snapshot) async {
            // Only process added documents (new requests)
            for (var change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final requestData = change.doc.data() as Map<String, dynamic>;
                final senderId = requestData['senderId'] as String;

                try {
                  // Get sender info
                  final senderDoc =
                      await _firestore.collection('users').doc(senderId).get();
                  if (senderDoc.exists) {
                    final senderData = senderDoc.data() as Map<String, dynamic>;
                    final senderName = senderData['name'] ?? 'Someone';

                    // Show local notification
                    _showInterestRequestNotification(
                      senderId: senderId,
                      senderName: senderName,
                      requestId: change.doc.id,
                    );
                  }
                } catch (e) {
                  LogService.e(
                    'Error processing interest request notification',
                    e,
                    StackTrace.current,
                  );
                }
              }
            }
          },
          onError: (error) {
            LogService.e(
              'Error listening for interest requests',
              error,
              StackTrace.current,
            );
          },
        );
  }

  void _listenForIncomingCalls() {
    _callSubscription = _callService.listenForCalls().listen(
      (snapshot) {
        if (!mounted) return;

        for (var doc in snapshot.docs) {
          final callData = doc.data() as Map<String, dynamic>;
          final status = callData['status'] as String;
          final channelName = callData['channelName'] as String;
          final callerId = callData['callerId'] as String;
          final callerName =
              callData['callerName'] as String? ?? 'Unknown Caller';

          if (status == CallStatus.calling.toString()) {
            _showIncomingCallDialog(channelName, callerId, callerName);
          }
        }
      },
      onError: (error) {
        debugPrint('Error listening for calls: $error');
      },
    );
  }

  void _showIncomingCallDialog(
    String channelName,
    String callerId,
    String callerName,
  ) async {
    // Load caller information
    String callerProfession = '';
    String callerExperience = '';
    try {
      final callerDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(callerId)
              .get();

      if (callerDoc.exists) {
        final userData = callerDoc.data()!;
        callerProfession = userData['profession'] ?? '';
        final experience = userData['experience']?.toString() ?? '0';
        callerExperience = '$experience years';
      }
    } catch (e) {
      debugPrint('Error loading caller info: $e');
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Caller avatar/icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withOpacity(0.3),
                    ),
                    child: Icon(
                      Icons.phone_in_talk,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Incoming call text
                  Text(
                    'Incoming Call',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Caller name
                  Text(
                    callerName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (callerProfession.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    // Profession
                    Text(
                      callerProfession,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (callerExperience.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    // Experience
                    Text(
                      callerExperience,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Call controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Reject button
                      _CallButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _callService.updateCallStatus(
                            channelName,
                            CallStatus.rejected,
                          );
                        },
                        icon: Icons.call_end,
                        backgroundColor: Theme.of(context).colorScheme.error,
                        iconColor: Theme.of(context).colorScheme.onError,
                      ),
                      // Accept button
                      _CallButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => VoiceCallPage(
                                    channelName: channelName,
                                    isIncoming: true,
                                    remoteUserId: callerId,
                                  ),
                            ),
                          );
                        },
                        icon: Icons.call,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        iconColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Future<void> _loadUserStatus() async {
    try {
      final userData = await _userService.getCurrentUserData();
      if (userData != null && userData.containsKey('isBeaming')) {
        setState(() {
          isBeaming = userData['isBeaming'] as bool;
        });
      }
    } catch (e) {
      LogService.e('Error loading user status', e, StackTrace.current);
    }
  }

  Future<void> _toggleBeamingStatus() async {
    setState(() {
      isBeaming = !isBeaming;
    });

    try {
      // Update using UserService instead of direct Firestore access
      final success = await _userService.updateUserData({
        'isBeaming': isBeaming,
      });

      if (success) {
        // Refresh nearby users
        _loadNearbyUsers();

        // Show feedback to user
        if (mounted) {
          SnackbarService.showSuccess(
            context,
            message:
                isBeaming
                    ? 'You are now visible to nearby professionals'
                    : 'You are now hidden from nearby professionals',
            duration: const Duration(seconds: 2),
          );
        }
      } else {
        // Revert the state if the update failed
        setState(() {
          isBeaming = !isBeaming;
        });

        if (mounted) {
          SnackbarService.showError(
            context,
            message: 'Failed to update status',
          );
        }
      }
    } catch (e) {
      LogService.e('Error updating beam status', e, StackTrace.current);
      // Revert the state if the update failed
      setState(() {
        isBeaming = !isBeaming;
      });

      if (mounted) {
        SnackbarService.showError(
          context,
          message: 'Failed to update status: $e',
        );
      }
    }
  }

  Future<void> _loadNearbyUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // First ensure location is up-to-date
      await _userService.updateUserLocation();

      // Then fetch nearby users
      final nearbyUsers = await _userService.getNearbyUsers(radiusInKm: 100.0);

      setState(() {
        _nearbyUsers = nearbyUsers;
        _isLoading = false;
      });
    } catch (e) {
      LogService.e('Error loading nearby users', e, StackTrace.current);
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_notification');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    // Initialize with notification tap callback
    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null && mounted) {
          NotificationPayloadHandler.handle(context, response.payload!);
        }
      },
    );

    // Handle notification that launched the app
    final NotificationAppLaunchDetails? launchDetails =
        await _flutterLocalNotificationsPlugin
            .getNotificationAppLaunchDetails();
    if (launchDetails != null &&
        launchDetails.didNotificationLaunchApp &&
        launchDetails.notificationResponse?.payload != null &&
        mounted) {
      NotificationPayloadHandler.handle(
        context,
        launchDetails.notificationResponse!.payload!,
      );
    }
  }

  // Show local notification for interest request
  Future<void> _showInterestRequestNotification({
    required String senderId,
    required String senderName,
    required String requestId,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'interest_channel',
          'Interest Request Notifications',
          channelDescription: 'Notifications for new interest requests',
          importance: Importance.high,
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

    try {
      await _flutterLocalNotificationsPlugin.show(
        requestId.hashCode, // Use hash of requestId as notification ID
        'New Interest Request',
        '$senderName is interested in connecting with you',
        platformDetails,
        payload:
            '{"type":"interest_request","senderId":"$senderId","requestId":"$requestId"}',
      );
    } catch (e) {
      LogService.e(
        'Error showing interest request notification',
        e,
        StackTrace.current,
      );
    }
  }

  // Set up real-time listener for connection requests
  void _setupConnectionRequestListener() {
    _connectionRequestsSubscription = _connectionService
        .getNewConnectionRequests()
        .listen(
          (snapshot) async {
            // Update pending requests count
            if (mounted) {
              setState(() {
                _pendingRequestsCount = snapshot.docs.length;
              });
            }

            // Only process added documents (new requests)
            for (var change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final requestData = change.doc.data() as Map<String, dynamic>;
                final senderId = requestData['senderId'] as String;

                try {
                  // Get sender info
                  final senderDoc =
                      await _firestore.collection('users').doc(senderId).get();
                  if (senderDoc.exists) {
                    final senderData = senderDoc.data() as Map<String, dynamic>;
                    final senderName = senderData['name'] ?? 'Someone';

                    // Show local notification
                    _showConnectionRequestNotification(
                      senderId: senderId,
                      senderName: senderName,
                      requestId: change.doc.id,
                    );
                  }
                } catch (e) {
                  LogService.e(
                    'Error processing connection request notification',
                    e,
                    StackTrace.current,
                  );
                }
              }
            }
          },
          onError: (error) {
            LogService.e(
              'Error listening for connection requests',
              error,
              StackTrace.current,
            );
          },
        );
  }

  // Show local notification for connection request
  Future<void> _showConnectionRequestNotification({
    required String senderId,
    required String senderName,
    required String requestId,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'connection_channel',
          'Connection Request Notifications',
          channelDescription: 'Notifications for new connection requests',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          enableVibration: true,
          playSound: true,
          fullScreenIntent: true,
        );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      final payload = json.encode({
        'type': 'connection_request',
        'senderId': senderId,
        'requestId': requestId,
        'senderName': senderName,
      });

      await _flutterLocalNotificationsPlugin.show(
        requestId.hashCode,
        'New Connection Request',
        '$senderName wants to connect with you',
        platformDetails,
        payload: payload,
      );
    } catch (e) {
      LogService.e(
        'Error showing connection request notification',
        e,
        StackTrace.current,
      );
    }
  }

  Future<void> _loadPendingRequestsCount() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      // Get count of pending requests where user is the receiver
      final pendingRequests =
          await _firestore
              .collection('connectionRequests')
              .where('receiverId', isEqualTo: userId)
              .where('status', isEqualTo: 'pending')
              .get();

      if (mounted) {
        setState(() {
          _pendingRequestsCount = pendingRequests.docs.length;
        });
      }
    } catch (e) {
      LogService.e(
        'Error loading pending requests count',
        e,
        StackTrace.current,
      );
    }
  }

  // Set up real-time listener for nearby users
  void _setupNearbyUsersListener() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Listen for users who are beaming
    _nearbyUsersSubscription = _firestore
        .collection('users')
        .where('isBeaming', isEqualTo: true)
        .snapshots()
        .listen(
          (snapshot) async {
            // Don't update if the widget is disposed
            if (!mounted) return;

            try {
              // First ensure location is up-to-date
              await _userService.updateUserLocation();

              // Then fetch nearby users
              final nearbyUsers = await _userService.getNearbyUsers(
                radiusInKm: 100.0,
              );

              if (mounted) {
                setState(() {
                  _nearbyUsers = nearbyUsers;
                  _isLoading = false;
                });
              }
            } catch (e) {
              LogService.e(
                'Error updating nearby users',
                e,
                StackTrace.current,
              );
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            }
          },
          onError: (error) {
            LogService.e(
              'Error in nearby users listener',
              error,
              StackTrace.current,
            );
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: Theme.of(context).colorScheme.background,
      extendBody: true,
      appBar: AppBar(
        title: Text('Beam'),
        centerTitle: true,
        leading: Stack(
          children: [
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ActivityHistoryPage(),
                  ),
                );
              },
              icon: Icon(Icons.connect_without_contact_outlined),
              alignment: Alignment.topLeft,
              color: Theme.of(context).colorScheme.primary,
            ),
            if (_pendingRequestsCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: BoxConstraints(minWidth: 20, minHeight: 20),
                  child: Text(
                    _pendingRequestsCount.toString(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onError,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const UserProfilePage(),
                ),
              ).then((_) {
                // Only reload nearby users when returning from profile page
                // No need to refresh user data as it's already cached
                _loadNearbyUsers();
              });
            },
            icon: Icon(Icons.person_outlined),
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Spacer(flex: 1),
            BeamBlob(beaming: isBeaming, onBeamToggle: _toggleBeamingStatus),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Nearby Professionals',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  if (!_isLoading && _nearbyUsers.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        try {
                          // Create a deep copy of the professionals list to avoid reference issues
                          final List<Map<String, dynamic>> professionalsCopy =
                              [];

                          // Validate each professional item before adding to the copy
                          for (var prof in _nearbyUsers) {
                            // Ensure all required fields are present
                            final validatedProf = <String, dynamic>{
                              'name': prof['name'] ?? 'Unknown',
                              'profession': prof['profession'] ?? '',
                              'experience':
                                  prof['experience'] ?? 'Not specified',
                              'distance': prof['distance'] ?? 'Unknown',
                              'image':
                                  prof['image'] ??
                                  'https://doodleipsum.com/700?i=6bff1692e77c36e5effde3d6f48fab6e',
                            };

                            // Add other fields from the original
                            prof.forEach((key, value) {
                              if (!validatedProf.containsKey(key)) {
                                validatedProf[key] = value;
                              }
                            });

                            professionalsCopy.add(validatedProf);
                          }

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => AllProfessionals(
                                    professionals: professionalsCopy,
                                  ),
                            ),
                          );
                        } catch (e) {
                          SnackbarService.showError(
                            context,
                            message: 'Error loading professionals list: $e',
                          );
                        }
                      },
                      child: Row(
                        children: [
                          Text(
                            'See All',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (_isLoading)
              Expanded(
                child: Center(
                  child: PlatformLoadingIndicator(
                    size: 20.0,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              )
            else if (_nearbyUsers.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: _nearbyUsers.length,
                  itemBuilder: (context, index) {
                    final professional = _nearbyUsers[index];
                    return NearbyProfessionalCard(info: professional);
                  },
                ),
              )
            else
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.people_outline_rounded,
                                  size: 64,
                                  color:
                                      Theme.of(context).colorScheme.secondary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No professionals found nearby',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
