import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';

class ActivityHistoryPage extends StatefulWidget {
  const ActivityHistoryPage({super.key});

  @override
  State<ActivityHistoryPage> createState() => _ActivityHistoryPageState();
}

class _ActivityHistoryPageState extends State<ActivityHistoryPage> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _userService = UserService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _activities = [];

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      // Get calls where user was involved (either caller or receiver)
      final callsQuery =
          await _firestore
              .collection('calls')
              .where(
                Filter.or(
                  Filter('callerId', isEqualTo: userId),
                  Filter('receiverId', isEqualTo: userId),
                ),
              )
              .orderBy('createdAt', descending: true)
              .limit(50)
              .get();

      final activities = await Future.wait(
        callsQuery.docs.map((doc) async {
          final data = doc.data();
          final otherUserId =
              data['callerId'] == userId
                  ? data['receiverId']
                  : data['callerId'];

          // Get other user's info
          final otherUserDoc =
              await _firestore.collection('users').doc(otherUserId).get();

          final otherUserData = otherUserDoc.data() ?? {};

          return {
            'id': doc.id,
            'type': 'call',
            'status': data['status'],
            'timestamp': data['createdAt'],
            'otherUser': {
              'id': otherUserId,
              'name': otherUserData['name'] ?? 'Unknown User',
              'profession': otherUserData['profession'] ?? '',
              'profileImageUrl': otherUserData['profileImageUrl'] ?? '',
            },
            'isOutgoing': data['callerId'] == userId,
          };
        }),
      );

      if (mounted) {
        setState(() {
          _activities = activities;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading activities: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
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

  Widget _buildActivityItem(Map<String, dynamic> activity) {
    final otherUser = activity['otherUser'];
    final isOutgoing = activity['isOutgoing'] as bool;
    final status = activity['status'] as String;

    IconData getCallIcon() {
      if (status == 'rejected' || status == 'missed') {
        return isOutgoing ? Icons.call_made : Icons.call_received;
      } else if (status == 'connected') {
        return isOutgoing ? Icons.call_made : Icons.call_received;
      } else {
        return Icons.call_end;
      }
    }

    Color getCallColor() {
      if (status == 'CallStatus.rejected' || status == 'CallStatus.missed') {
        return Colors.red.shade400;
      } else if (status == 'CallStatus.connected') {
        return Colors.green.shade400;
      } else {
        return Colors.orange.shade400;
      }
    }

    String getStatusText() {
      if (status == 'rejected') {
        return isOutgoing ? 'Call rejected' : 'Rejected call';
      } else if (status == 'missed') {
        return isOutgoing ? 'No answer' : 'Missed call';
      } else if (status == 'connected') {
        return isOutgoing ? 'Outgoing call' : 'Incoming call';
      } else {
        return 'Call ended';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Profile Image
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surfaceVariant,
                ),
                child: ClipOval(
                  child:
                      otherUser['profileImageUrl'].isNotEmpty
                          ? Image.network(
                            otherUser['profileImageUrl'],
                            fit: BoxFit.cover,
                            errorBuilder:
                                (context, error, stackTrace) => Icon(
                                  Icons.person,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 30,
                                ),
                          )
                          : Icon(
                            Icons.person,
                            color: Theme.of(context).colorScheme.primary,
                            size: 30,
                          ),
                ),
              ),
              const SizedBox(width: 16),
              // Call Information
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            otherUser['name'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatTimestamp(activity['timestamp']),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (otherUser['profession'].isNotEmpty) ...[
                      Text(
                        otherUser['profession'],
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                    ],
                    Row(
                      children: [
                        Icon(getCallIcon(), size: 16, color: getCallColor()),
                        const SizedBox(width: 4),
                        Text(
                          getStatusText(),
                          style: TextStyle(
                            color: getCallColor(),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity History'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _loadActivities,
        child:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _activities.isEmpty
                ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 64,
                        color: Theme.of(
                          context,
                        ).colorScheme.secondary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No activities yet',
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your call history will appear here',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(
                            context,
                          ).colorScheme.secondary.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                )
                : ListView.builder(
                  itemCount: _activities.length,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index) {
                    return _buildActivityItem(_activities[index]);
                  },
                ),
      ),
    );
  }
}
