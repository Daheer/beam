// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:beam/services/log_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/connection_request_service.dart';
import '../services/snackbar_service.dart';
import 'professional_profile_page.dart';
import 'voice_call_page.dart';
import '../services/call_service.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/platform_loading_indicator.dart';

class ActivityHistoryPage extends StatefulWidget {
  final String? notificationRequestId;

  const ActivityHistoryPage({super.key, this.notificationRequestId});

  @override
  State<ActivityHistoryPage> createState() => _ActivityHistoryPageState();
}

class _ActivityHistoryPageState extends State<ActivityHistoryPage>
    with SingleTickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _connectionService = ConnectionRequestService();
  final _callService = CallService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _activities = [];
  late TabController _tabController;
  String _processingRequestId = '';
  StreamSubscription<QuerySnapshot>? _requestsSubscription;
  StreamSubscription<QuerySnapshot>? _connectionsSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // If opened from a notification, ensure we're on the connection tab
    if (widget.notificationRequestId != null) {
      _tabController.index = 0;
    }

    // Listen for changes to reload activities
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _isLoading = true; // Set loading state when switching tabs
          _activities = []; // Clear current activities
        });
        _setupListeners();
      }
    });

    _setupListeners();
  }

  @override
  void dispose() {
    _requestsSubscription?.cancel();
    _connectionsSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _setupListeners() {
    // Cancel existing subscriptions
    _requestsSubscription?.cancel();
    _connectionsSubscription?.cancel();

    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    if (_tabController.index == 0) {
      // Listen for connection requests
      _requestsSubscription = _firestore
          .collection('connectionRequests')
          .where(
            Filter.or(
              Filter('senderId', isEqualTo: userId),
              Filter('receiverId', isEqualTo: userId),
            ),
          )
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snapshot) async {
            await _loadConnectionRequests(userId);
          });
    } else {
      // Listen for established connections
      _connectionsSubscription = _firestore
          .collection('connectionRequests')
          .where(
            Filter.or(
              Filter('senderId', isEqualTo: userId),
              Filter('receiverId', isEqualTo: userId),
            ),
          )
          .where('status', isEqualTo: 'accepted')
          .where('hasCalledBefore', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snapshot) async {
            await _loadConnections(userId);
          });
    }
  }

  Future<void> _loadActivities() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _activities = []; // Clear existing activities while loading
    });

    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      if (_tabController.index == 0) {
        // Load connection requests that haven't been moved to connections yet
        await _loadConnectionRequests(userId);
      } else {
        // Load established connections
        await _loadConnections(userId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadConnectionRequests(String userId) async {
    try {
      // Get current user's location
      final currentUserDoc =
          await _firestore.collection('users').doc(userId).get();
      final currentUserLocation =
          currentUserDoc.data()?['location'] as GeoPoint?;

      // Get connection requests where user is involved (either sender or receiver)
      final requestsQuery =
          await _firestore
              .collection('connectionRequests')
              .where(
                Filter.or(
                  Filter('senderId', isEqualTo: userId),
                  Filter('receiverId', isEqualTo: userId),
                ),
              )
              .orderBy('createdAt', descending: true)
              .limit(50)
              .get();

      if (!mounted) return;

      if (requestsQuery.docs.isEmpty) {
        setState(() {
          _activities = [];
          _isLoading = false;
          _processingRequestId = '';
        });
        return;
      }

      List<Map<String, dynamic>> activities = [];

      // Process each document
      for (var doc in requestsQuery.docs) {
        try {
          final data = doc.data();
          final otherUserId =
              data['senderId'] == userId
                  ? data['receiverId'] as String
                  : data['senderId'] as String;

          // Only move to connections if they've called and shared emails
          final hasCalledBefore = data['hasCalledBefore'] == true;
          final senderEmail = data['senderEmail'] as String?;
          final receiverEmail = data['receiverEmail'] as String?;
          final bothEmailsShared = senderEmail != null && receiverEmail != null;

          // Skip this request if it should be in the connections tab
          if (hasCalledBefore &&
              bothEmailsShared &&
              data['status'] == 'accepted') {
            continue;
          }

          // Get other user's info
          final otherUserDoc =
              await _firestore.collection('users').doc(otherUserId).get();

          if (!otherUserDoc.exists) continue;

          final otherUserData = otherUserDoc.data()!;

          // Calculate distance if both users have location
          String distance = '…';
          if (currentUserLocation != null &&
              otherUserData['location'] != null) {
            final otherUserLocation = otherUserData['location'] as GeoPoint;
            final distanceInMeters = Geolocator.distanceBetween(
              currentUserLocation.latitude,
              currentUserLocation.longitude,
              otherUserLocation.latitude,
              otherUserLocation.longitude,
            );
            final distanceInKm = distanceInMeters / 1000;
            distance = '${distanceInKm.toStringAsFixed(1)} km';
          }

          activities.add({
            'id': doc.id,
            'type': 'connection',
            'status': data['status'],
            'isMutual': false,
            'timestamp': data['createdAt'],
            'hasCalledBefore': hasCalledBefore,
            'otherUser': {
              'id': otherUserId,
              'name': otherUserData['name'] as String? ?? 'Unknown User',
              'profession': otherUserData['profession'] as String? ?? '',
              'profileImageUrl':
                  otherUserData['profileImageUrl'] as String? ?? '',
              'image':
                  otherUserData['profileImageUrl'] as String? ??
                  otherUserData['image'] as String? ??
                  '',
              'about':
                  otherUserData['about'] as String? ??
                  'No information provided.',
              'experience':
                  otherUserData['experience'] != null
                      ? otherUserData['experience'].toString()
                      : 'Not specified',
              'distance': distance,
              'skills': otherUserData['skills'] as List<dynamic>? ?? [],
            },
            'isOutgoing': data['senderId'] == userId,
          });
        } catch (e) {
          LogService.e(
            'Error processing request ${doc.id}',
            e,
            StackTrace.current,
          );
        }
      }

      if (mounted) {
        setState(() {
          _activities = activities;
          _isLoading = false;
          _processingRequestId = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _activities = [];
        });
      }
    }
  }

  Future<bool> _checkSharedContact(String userId, String otherUserId) async {
    try {
      final sharedContacts =
          await _firestore
              .collection('sharedContacts')
              .where(
                Filter.or(
                  Filter.and(
                    Filter('fromUserId', isEqualTo: userId),
                    Filter('toUserId', isEqualTo: otherUserId),
                  ),
                  Filter.and(
                    Filter('fromUserId', isEqualTo: otherUserId),
                    Filter('toUserId', isEqualTo: userId),
                  ),
                ),
              )
              .limit(1)
              .get();

      return sharedContacts.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _loadConnections(String userId) async {
    try {
      // Get current user's location
      final currentUserDoc =
          await _firestore.collection('users').doc(userId).get();
      final currentUserLocation =
          currentUserDoc.data()?['location'] as GeoPoint?;

      // Get all connection requests that have both called and shared emails
      final connectionsQuery =
          await _firestore
              .collection('connectionRequests')
              .where(
                Filter.or(
                  Filter('senderId', isEqualTo: userId),
                  Filter('receiverId', isEqualTo: userId),
                ),
              )
              .where('status', isEqualTo: 'accepted')
              .where('hasCalledBefore', isEqualTo: true)
              .orderBy('createdAt', descending: true)
              .get();

      if (!mounted) return;

      if (connectionsQuery.docs.isEmpty) {
        setState(() {
          _activities = [];
          _isLoading = false;
        });
        return;
      }

      // Process connections
      List<Map<String, dynamic>> activities = [];

      for (var doc in connectionsQuery.docs) {
        try {
          final data = doc.data();
          final otherUserId =
              data['senderId'] == userId
                  ? data['receiverId'] as String
                  : data['senderId'] as String;

          // Only show if both emails are shared
          final senderEmail = data['senderEmail'] as String?;
          final receiverEmail = data['receiverEmail'] as String?;
          if (senderEmail == null || receiverEmail == null) continue;

          final otherUserDoc =
              await _firestore.collection('users').doc(otherUserId).get();

          if (!otherUserDoc.exists) continue;

          final otherUserData = otherUserDoc.data() ?? {};

          // Calculate distance if both users have location
          String distance = '…';
          if (currentUserLocation != null &&
              otherUserData['location'] != null) {
            final otherUserLocation = otherUserData['location'] as GeoPoint;
            final distanceInMeters = Geolocator.distanceBetween(
              currentUserLocation.latitude,
              currentUserLocation.longitude,
              otherUserLocation.latitude,
              otherUserLocation.longitude,
            );
            final distanceInKm = distanceInMeters / 1000;
            distance = '${distanceInKm.toStringAsFixed(1)} km';
          }

          // Get the appropriate email to show based on whether the user is sender or receiver
          final sharedEmail =
              data['senderId'] == userId ? receiverEmail : senderEmail;

          activities.add({
            'id': doc.id,
            'type': 'connection',
            'connectionType': 'shared_contact',
            'timestamp': data['createdAt'],
            'hasCalledBefore': data['hasCalledBefore'] == true,
            'otherUser': {
              'id': otherUserId,
              'name': otherUserData['name'] as String? ?? 'Unknown User',
              'profession': otherUserData['profession'] as String? ?? '',
              'profileImageUrl':
                  otherUserData['profileImageUrl'] as String? ?? '',
              'image':
                  otherUserData['profileImageUrl'] as String? ??
                  otherUserData['image'] as String? ??
                  '',
              'about':
                  otherUserData['about'] as String? ??
                  'No information provided.',
              'experience':
                  otherUserData['experience'] != null
                      ? otherUserData['experience'].toString()
                      : 'Not specified',
              'distance': distance,
              'skills': otherUserData['skills'] as List<dynamic>? ?? [],
              'sharedEmail': sharedEmail,
            },
            'isOutgoing': data['senderId'] == userId,
          });
        } catch (e) {
          LogService.e(
            'Error processing connection ${doc.id}',
            e,
            StackTrace.current,
          );
        }
      }

      // Sort all activities by timestamp
      activities.sort(
        (a, b) => (b['timestamp'] as Timestamp).compareTo(
          a['timestamp'] as Timestamp,
        ),
      );

      if (mounted) {
        setState(() {
          _activities = activities;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _activities = [];
        });
      }
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';

    final now = DateTime.now();
    final date = timestamp.toDate();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return '${date.day}/${date.month}/${date.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _viewProfile(Map<String, dynamic> otherUser) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfessionalProfile(professional: otherUser),
      ),
    );
    _loadActivities();
  }

  Future<void> _acceptConnectionRequest(String requestId) async {
    setState(() {
      _processingRequestId = requestId;
      _isLoading = true;
    });

    try {
      final success = await _connectionService.acceptConnectionRequest(
        requestId,
      );
      if (success && mounted) {
        SnackbarService.showSuccess(
          context,
          message: 'Connection request accepted successfully',
        );
        await Future.delayed(const Duration(milliseconds: 300));
        _loadActivities();
      } else if (mounted) {
        SnackbarService.showError(context, message: 'Failed to accept request');
        setState(() {
          _isLoading = false;
          _processingRequestId = '';
        });
      }
    } catch (e) {
      if (mounted) {
        SnackbarService.showError(
          context,
          message: 'Failed to accept request: $e',
        );
        setState(() {
          _isLoading = false;
          _processingRequestId = '';
        });
      }
    }
  }

  Future<void> _rejectConnectionRequest(String requestId) async {
    setState(() {
      _processingRequestId = requestId;
      _isLoading = true;
    });

    try {
      final success = await _connectionService.rejectConnectionRequest(
        requestId,
      );
      if (success && mounted) {
        SnackbarService.showSuccess(
          context,
          message: 'Connection request rejected',
        );
        _loadActivities();
      } else if (mounted) {
        SnackbarService.showError(context, message: 'Failed to reject request');
        setState(() {
          _isLoading = false;
          _processingRequestId = '';
        });
      }
    } catch (e) {
      if (mounted) {
        SnackbarService.showError(
          context,
          message: 'Failed to reject request: $e',
        );
        setState(() {
          _isLoading = false;
          _processingRequestId = '';
        });
      }
    }
  }

  Future<void> _startCall(String otherUserId) async {
    try {
      final channelName = await _callService.initiateCall(otherUserId);
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
                  remoteUserId: otherUserId,
                ),
          ),
        );
        _loadActivities();
      }
    } catch (e) {
      if (mounted) {
        SnackbarService.showError(context, message: 'Failed to start call: $e');
      }
    }
  }

  Widget _buildActivityItem(Map<String, dynamic> activity) {
    if (_isLoading || activity == null) {
      return Card(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          leading: CircleAvatar(
            child: Center(
              child: PlatformLoadingIndicator(
                size: 10.0,
                strokeWidth: 2.0,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          title: LinearProgressIndicator(),
        ),
      );
    }

    final type = activity['type'] as String?;
    if (type == null) return const SizedBox.shrink();

    try {
      if (type == 'connection') {
        if (_tabController.index == 0) {
          return _buildConnectionRequestItem(activity);
        } else {
          return _buildConnectionItem(activity);
        }
      }
    } catch (e) {
      LogService.e('Error building activity item', e, StackTrace.current);
    }

    return const SizedBox.shrink(); // Fallback for unknown types or errors
  }

  Widget _buildConnectionRequestItem(Map<String, dynamic> activity) {
    final otherUser = activity['otherUser'];
    final isOutgoing = activity['isOutgoing'] as bool;
    final status = activity['status'] as String;
    final isMutual = activity['isMutual'] as bool;
    final requestId = activity['id'] as String;
    final isProcessing = _isLoading && _processingRequestId == requestId;
    final distance = otherUser['distance'] as String? ?? '…';

    Widget buildTrailing() {
      if (isProcessing) {
        return SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: PlatformLoadingIndicator(
              size: 10.0,
              strokeWidth: 2.0,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      }

      // Show accept/reject buttons only for incoming pending requests in the connections tab
      if (!isOutgoing && status == 'pending' && _tabController.index == 0) {
        return SizedBox(
          width: 96,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                constraints: const BoxConstraints(minWidth: 40),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.check_circle, color: Colors.green),
                onPressed: () => _acceptConnectionRequest(requestId),
                tooltip: 'Accept request',
              ),
              IconButton(
                constraints: const BoxConstraints(minWidth: 40),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.cancel, color: Colors.red),
                onPressed: () => _rejectConnectionRequest(requestId),
                tooltip: 'Reject request',
              ),
            ],
          ),
        );
      }

      // Show call button for accepted requests that haven't had a call yet
      if (status == 'accepted' && !activity['hasCalledBefore']) {
        return IconButton(
          constraints: const BoxConstraints(minWidth: 40),
          padding: EdgeInsets.zero,
          icon: Icon(Icons.call, color: Colors.green.shade600),
          onPressed: () => _startCall(otherUser['id']),
          tooltip: 'Start call',
        );
      }

      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        onTap: () => _viewProfile(otherUser),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          minLeadingWidth: 48,
          horizontalTitleGap: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: Hero(
            tag: 'professional-${otherUser['id']}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                height: 48,
                color: Theme.of(context).colorScheme.primaryContainer,
                child:
                    otherUser['image']?.isNotEmpty == true
                        ? Image.network(
                          otherUser['image'],
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (context, error, stackTrace) => Icon(
                                Icons.person,
                                color: Theme.of(context).colorScheme.primary,
                                size: 24,
                              ),
                        )
                        : Icon(
                          Icons.person,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
              ),
            ),
          ),
          title: Text(
            otherUser['name'],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (otherUser['profession']?.isNotEmpty == true)
                Text(
                  otherUser['profession'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    distance,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  if (otherUser['experience']?.isNotEmpty == true) ...[
                    Text(
                      ' • ',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                    Text(
                      otherUser['experience'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                    Text(
                      int.parse(otherUser['experience']) > 1
                          ? ' years '
                          : ' year ',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    status == 'rejected'
                        ? Icons.cancel_outlined
                        : status == 'accepted'
                        ? isMutual
                            ? Icons.connect_without_contact
                            : Icons.check_circle_outline
                        : isOutgoing
                        ? Icons.pending_outlined
                        : Icons.person_add_alt,
                    size: 14,
                    color:
                        status == 'rejected'
                            ? Colors.red
                            : status == 'accepted'
                            ? isMutual
                                ? Theme.of(context).colorScheme.primary
                                : Colors.green
                            : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      status == 'rejected'
                          ? isOutgoing
                              ? 'Request rejected'
                              : 'You rejected this request'
                          : status == 'accepted'
                          ? isMutual
                              ? 'Mutual connection'
                              : isOutgoing
                              ? 'Request accepted'
                              : 'You accepted this request'
                          : isOutgoing
                          ? 'Request sent'
                          : 'Connection request received',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            status == 'rejected'
                                ? Colors.red
                                : status == 'accepted'
                                ? isMutual
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.green
                                : Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          trailing: buildTrailing(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionItem(Map<String, dynamic> activity) {
    // Early return if activity data is not properly loaded
    if (!activity.containsKey('otherUser') || activity['otherUser'] == null) {
      return const SizedBox.shrink();
    }

    final otherUser = activity['otherUser'] as Map<String, dynamic>;
    final isOutgoing = activity['isOutgoing'] as bool? ?? false;
    final connectionType = activity['connectionType'] as String? ?? 'mutual';
    final sharedEmail = otherUser['sharedEmail'] as String?;
    final name = otherUser['name'] as String? ?? 'Unknown User';
    final profession = otherUser['profession'] as String? ?? '';
    final image = otherUser['image'] as String?;
    final userId = otherUser['id'] as String?;
    final distance = otherUser['distance'] as String? ?? '…';

    if (userId == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: Hero(
              tag: 'professional-$userId',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 48,
                  height: 48,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child:
                      image?.isNotEmpty == true
                          ? Image.network(
                            image!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (context, error, stackTrace) => Icon(
                                  Icons.person,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 24,
                                ),
                          )
                          : Icon(
                            Icons.person,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                ),
              ),
            ),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (profession.isNotEmpty)
                  Text(
                    profession,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      distance,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      connectionType == 'shared_contact'
                          ? Icons.share
                          : Icons.connect_without_contact,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      connectionType == 'shared_contact'
                          ? isOutgoing
                              ? 'You shared your contact'
                              : 'Shared their contact with you'
                          : 'Mutual connection',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (sharedEmail != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.email_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sharedEmail,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final bool isConnectionsTab = _tabController.index == 0;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isConnectionsTab
                ? Icons.person_add_alt_1_outlined
                : Icons.connect_without_contact,
            size: 64,
            color: Theme.of(context).colorScheme.secondary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            isConnectionsTab ? 'No connection requests' : 'No connections yet',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isConnectionsTab
                ? 'Connection requests will appear here'
                : 'Your connections will appear here after sharing contacts',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.secondary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity History'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Connection Requests'),
            Tab(text: 'Connections'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Connection requests tab
          _isLoading
              ? Center(
                child: PlatformLoadingIndicator(
                  size: 20.0,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
              : _activities.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                itemCount: _activities.length,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder:
                    (context, index) => _buildActivityItem(_activities[index]),
              ),

          // Connections tab
          _isLoading
              ? Center(
                child: PlatformLoadingIndicator(
                  size: 20.0,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
              : _activities.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                itemCount: _activities.length,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder:
                    (context, index) => _buildActivityItem(_activities[index]),
              ),
        ],
      ),
    );
  }
}
