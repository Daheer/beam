// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../pages/voice_call_page.dart';
import '../services/call_service.dart';
import '../services/snackbar_service.dart';
import '../services/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/connection_request_service.dart';
import '../services/log_service.dart';

class ProfessionalProfile extends StatefulWidget {
  final Map<String, dynamic> professional;

  const ProfessionalProfile({super.key, required this.professional});

  @override
  State<ProfessionalProfile> createState() => _ProfessionalProfileState();
}

class _ProfessionalProfileState extends State<ProfessionalProfile> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CallService _callService = CallService();
  final NotificationService _notificationService = NotificationService();
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final ConnectionRequestService _connectionService =
      ConnectionRequestService();
  bool _isSendingRequest = false;
  bool _hasExistingRequest = false;
  String? _requestStatus;
  bool _isOutgoingRequest = true;
  StreamSubscription<QuerySnapshot>? _requestSubscription;

  @override
  void initState() {
    super.initState();
    _checkExistingRequest();
    _setupRequestListener();
    _initNotifications();
  }

  @override
  void dispose() {
    _requestSubscription?.cancel();
    super.dispose();
  }

  void _checkExistingRequest() async {
    if (_auth.currentUser == null) return;

    try {
      final currentUserId = _auth.currentUser!.uid;
      final professionalId = widget.professional['id'];

      // First check for requests from current user to professional
      final sentRequests =
          await _firestore
              .collection('connectionRequests')
              .where('senderId', isEqualTo: currentUserId)
              .where('receiverId', isEqualTo: professionalId)
              .orderBy('createdAt', descending: true)
              .limit(1)
              .get();

      if (sentRequests.docs.isNotEmpty) {
        final status = sentRequests.docs.first.data()['status'];
        setState(() {
          _hasExistingRequest = true;
          _requestStatus = status;
          _isOutgoingRequest = true;
        });
        return;
      }

      // If no outgoing request found, check for incoming requests
      final receivedRequests =
          await _firestore
              .collection('connectionRequests')
              .where('senderId', isEqualTo: professionalId)
              .where('receiverId', isEqualTo: currentUserId)
              .orderBy('createdAt', descending: true)
              .limit(1)
              .get();

      if (receivedRequests.docs.isNotEmpty) {
        final status = receivedRequests.docs.first.data()['status'];
        setState(() {
          _hasExistingRequest = true;
          _requestStatus = status;
          _isOutgoingRequest = false;
          // Don't show accept/reject here anymore, just status
        });
      }
    } catch (e) {
      LogService.e('Error checking existing request', e, StackTrace.current);
    }
  }

  void _setupRequestListener() {
    if (_auth.currentUser == null) return;

    final currentUserId = _auth.currentUser!.uid;
    final professionalId = widget.professional['id'];

    // Listen for both incoming and outgoing requests
    _requestSubscription = _firestore
        .collection('connectionRequests')
        .where(
          Filter.or(
            Filter.and(
              Filter('senderId', isEqualTo: currentUserId),
              Filter('receiverId', isEqualTo: professionalId),
            ),
            Filter.and(
              Filter('senderId', isEqualTo: professionalId),
              Filter('receiverId', isEqualTo: currentUserId),
            ),
          ),
        )
        .snapshots()
        .listen(
          (snapshot) async {
            if (!mounted) return;

            if (snapshot.docs.isEmpty) {
              setState(() {
                _hasExistingRequest = false;
                _requestStatus = null;
              });
              return;
            }

            final doc = snapshot.docs.first;
            final data = doc.data();
            final isOutgoing = data['senderId'] == currentUserId;

            setState(() {
              _hasExistingRequest = true;
              _requestStatus = data['status'];
              _isOutgoingRequest = isOutgoing;
            });
          },
          onError: (error) {
            LogService.e(
              'Error in request listener',
              error,
              StackTrace.current,
            );
          },
        );
  }

  Future<bool> _handleMicrophonePermission() async {
    try {
      debugPrint('Checking microphone permission using multiple methods...');

      // Try creating an Agora engine instance to check permissions
      final RtcEngine engine = createAgoraRtcEngine();
      await engine.initialize(
        const RtcEngineContext(
          appId: "88c37957d22a4576a441b90c70e02608",
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );

      // Enable audio - this will trigger the permission request if needed
      await engine.enableAudio();
      debugPrint('Agora engine initialized and audio enabled successfully');

      // If we got here, the permission must be granted
      await engine.release();
      return true;
    } catch (e) {
      debugPrint('Error during Agora permission check: $e');

      // If Agora check failed, try system permission
      final status = await Permission.microphone.status;
      debugPrint('System permission status: $status');

      if (status.isGranted) return true;

      // Show settings dialog
      if (!mounted) return false;
      final bool openSettings =
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder:
                (context) => AlertDialog(
                  title: const Text('Microphone Access Required'),
                  content: const Text(
                    'Please ensure microphone access is enabled in both system settings and app permissions for voice calls to work.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Open Settings'),
                    ),
                  ],
                ),
          ) ??
          false;

      if (openSettings) {
        await openAppSettings();
        // Wait for user to potentially change settings
        await Future.delayed(const Duration(seconds: 1));
        return Permission.microphone.status.then((status) => status.isGranted);
      }

      return false;
    }
  }

  void _sendConnectionRequest() async {
    if (_auth.currentUser == null) return;

    setState(() {
      _isSendingRequest = true;
    });

    try {
      final requestId = await _connectionService.sendConnectionRequest(
        widget.professional['id'],
      );

      if (requestId == null) {
        throw Exception('Failed to send connection request');
      }

      if (mounted) {
        setState(() {
          _hasExistingRequest = true;
          _requestStatus = 'pending';
        });
      }
    } catch (e) {
      debugPrint('Error sending connection request: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSendingRequest = false;
        });
      }
    }
  }

  void _startCall() async {
    if (_auth.currentUser == null) return;

    setState(() {
      _isSendingRequest = true;
    });

    try {
      // First verify mutual connection
      final canCall = await _connectionService.canCall(
        widget.professional['id'],
      );

      if (!canCall) {
        throw Exception('Mutual connection is required to start a call');
      }

      debugPrint('Checking microphone permissions...');
      final hasPermission = await _handleMicrophonePermission();

      if (!hasPermission) {
        throw Exception('Microphone permission is required for voice calls');
      }

      debugPrint('Permission granted, initiating call...');
      final channelName = await _callService.initiateCall(
        widget.professional['id'],
      );

      if (channelName == null) {
        throw Exception('Failed to initiate call');
      }

      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => VoiceCallPage(
                  channelName: channelName,
                  isIncoming: false,
                  remoteUserId: widget.professional['id'],
                ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error during connection: $e');
      if (mounted) {
        SnackbarService.showError(context, message: 'Failed to connect: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingRequest = false;
        });
      }
    }
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_notification');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );
    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  @override
  Widget build(BuildContext context) {
    final skills = widget.professional['skills'] as List<dynamic>? ?? [];
    final about =
        widget.professional['about'] as String? ?? 'No information provided.';

    return Scaffold(
      body: Stack(
        children: [
          // Content
          CustomScrollView(
            slivers: [
              // App Bar with Image
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                backgroundColor: Colors.transparent,
                elevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag:
                            'professional-${widget.professional['id'] ?? widget.professional['name'] ?? DateTime.now().millisecondsSinceEpoch}',
                        child: Image.network(
                          widget.professional['image'] ?? '',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                              child: Icon(
                                Icons.person,
                                size: 100,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            );
                          },
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.1),
                              Colors.black.withOpacity(0.8),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                    ),
                    child: const SizedBox(height: 32),
                  ),
                ),
              ),
              // Profile Content
              SliverToBoxAdapter(
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.professional['name'] ?? 'Unnamed Professional',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        widget.professional['profession'] != null &&
                                widget.professional['profession']
                                    .toString()
                                    .isNotEmpty
                            ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                widget.professional['profession'],
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            )
                            : const SizedBox.shrink(),
                        const SizedBox(height: 24),
                        // Stats Row
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                context,
                                Icons.work_outline,
                                'Experience',
                                widget.professional['experience'] ??
                                    'Not specified',
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildStatCard(
                                context,
                                Icons.location_on_outlined,
                                'Distance',
                                widget.professional['distance'] ?? 'Unknown',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'About',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          about,
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.secondary,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 32),
                        skills.isNotEmpty
                            ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Skills',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children:
                                      skills
                                          .map(
                                            (skill) => Chip(
                                              label: Text(skill.toString()),
                                              backgroundColor:
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .secondaryContainer,
                                            ),
                                          )
                                          .toList(),
                                ),
                              ],
                            )
                            : const SizedBox.shrink(),
                        const SizedBox(height: 100), // Space for button
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Connect Button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24.0),
              child: _buildConnectionStatus(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus() {
    if (_isSendingRequest) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasExistingRequest) {
      return ElevatedButton(
        onPressed: _sendConnectionRequest,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primary.withOpacity(0.8),
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 1,
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add, size: 24),
            SizedBox(width: 8),
            Text(
              'Connect',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    // Show status button instead of chip
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (_requestStatus) {
      case 'pending':
        statusColor = Colors.orange;
        statusIcon =
            _isOutgoingRequest ? Icons.pending_outlined : Icons.person_add_alt;
        statusText = _isOutgoingRequest ? 'Request Sent' : 'Request Pending';
        break;
      case 'accepted':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_outline;
        statusText = 'Connected';
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel_outlined;
        statusText =
            _isOutgoingRequest ? 'Request Rejected' : 'Request Declined';
        break;
      default:
        statusColor = Theme.of(context).colorScheme.secondary;
        statusIcon = Icons.info_outline;
        statusText = 'Unknown Status';
    }

    // If connected, show status and call button side by side
    if (_requestStatus == 'accepted') {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                backgroundColor: statusColor.withOpacity(0.1),
                disabledBackgroundColor: statusColor.withOpacity(0.1),
                disabledForegroundColor: statusColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: statusColor.withOpacity(0.5)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(statusIcon, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 64,
            child: ElevatedButton(
              onPressed: _startCall,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withOpacity(0.8),
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 1,
              ),
              child: const Icon(Icons.call, size: 24),
            ),
          ),
        ],
      );
    }

    // For other states, show just the status button
    return ElevatedButton(
      onPressed: null,
      style: ElevatedButton.styleFrom(
        backgroundColor: statusColor.withOpacity(0.1),
        disabledBackgroundColor: statusColor.withOpacity(0.1),
        disabledForegroundColor: statusColor,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: statusColor.withOpacity(0.5)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(statusIcon, size: 24),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
