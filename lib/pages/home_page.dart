import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/beam_blob.dart';
import '../widgets/nearby_professional_card.dart';
import '../services/user_service.dart';
import '../services/call_service.dart';
import 'all_professionals_page.dart';
import 'user_profile_page.dart';
import 'voice_call_page.dart';
import 'activity_history_page.dart';

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

class _HomePageState extends State<HomePage> {
  final _userService = UserService();
  final _callService = CallService();
  bool isBeaming = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> professionals = [];
  StreamSubscription? _callSubscription;

  @override
  void initState() {
    super.initState();
    _loadUserStatus();
    _loadNearbyUsers();
    _listenForIncomingCalls();
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    super.dispose();
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
      print('Error loading user status: $e');
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isBeaming
                    ? 'You are now visible to nearby professionals'
                    : 'You are now hidden from nearby professionals',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Revert the state if the update failed
        setState(() {
          isBeaming = !isBeaming;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update status')),
          );
        }
      }
    } catch (e) {
      print('Error updating beam status: $e');
      // Revert the state if the update failed
      setState(() {
        isBeaming = !isBeaming;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update status: $e')));
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
        professionals = nearbyUsers;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading nearby users: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshLocation() async {
    try {
      final success = await _userService.updateUserLocation();
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location updated successfully')),
        );
        _loadNearbyUsers();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update location')),
        );
      }
    } catch (e) {
      print('Error refreshing location: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating location: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: Theme.of(context).colorScheme.background,
      extendBody: true,
      appBar: AppBar(
        title: Text('Beam'),
        centerTitle: true,
        leading: IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ActivityHistoryPage(),
              ),
            );
          },
          icon: Icon(Icons.history),
          alignment: Alignment.topLeft,
          color: Theme.of(context).colorScheme.primary,
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
      body: RefreshIndicator(
        onRefresh: _loadNearbyUsers,
        child: SafeArea(
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
                    if (!_isLoading && professionals.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          try {
                            // Create a deep copy of the professionals list to avoid reference issues
                            final List<Map<String, dynamic>> professionalsCopy =
                                [];

                            // Validate each professional item before adding to the copy
                            for (var prof in professionals) {
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
                            print('Error navigating to AllProfessionals: $e');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Error loading professionals list: $e',
                                ),
                              ),
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
                Expanded(child: Center(child: CircularProgressIndicator()))
              else if (professionals.isNotEmpty)
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom,
                    ),
                    itemCount: professionals.length,
                    itemBuilder: (context, index) {
                      final professional = professionals[index];
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
                              padding: const EdgeInsets.symmetric(
                                vertical: 24.0,
                              ),
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
                                          Theme.of(
                                            context,
                                          ).colorScheme.secondary,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextButton(
                                    onPressed: _loadNearbyUsers,
                                    child: const Text('Refresh'),
                                  ),
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
      ),
    );
  }
}
