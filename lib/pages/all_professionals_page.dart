// ignore_for_file: deprecated_member_use

import 'package:beam/services/log_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../services/user_service.dart';
import '../services/log_service.dart';
import 'professional_profile_page.dart';
import '../widgets/platform_loading_indicator.dart';

class AllProfessionals extends StatefulWidget {
  final List<Map<String, dynamic>> professionals;

  const AllProfessionals({super.key, required this.professionals});

  @override
  State<AllProfessionals> createState() => _AllProfessionalsState();
}

class _AllProfessionalsState extends State<AllProfessionals> {
  final UserService _userService = UserService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<Map<String, dynamic>> _professionals = [];
  bool _isLoading = true;
  StreamSubscription<QuerySnapshot>? _nearbyUsersSubscription;

  @override
  void initState() {
    super.initState();
    _professionals = List<Map<String, dynamic>>.from(widget.professionals);
    _setupNearbyUsersListener();
  }

  @override
  void dispose() {
    _nearbyUsersSubscription?.cancel();
    super.dispose();
  }

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
                  _professionals = nearbyUsers;
                  _isLoading = false;
                });
              }
            } catch (e) {
              LogService.e(
                'Error updating nearby users in AllProfessionals',
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
              'Error in nearby users listener in AllProfessionals',
              error,
              StackTrace.current,
            );
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Professionals'),
        centerTitle: true,
        elevation: 0,
      ),
      body:
          _isLoading
              ? Center(
                child: PlatformLoadingIndicator(
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
              : _professionals.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_outline_rounded,
                      size: 64,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No professionals found',
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              )
              : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount:
                      MediaQuery.of(context).size.width > 600 ? 3 : 2,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _professionals.length,
                itemBuilder: (context, index) {
                  final professional = _professionals[index];
                  return Hero(
                    tag:
                        'professional-${professional['id'] ?? professional['name'] ?? DateTime.now().millisecondsSinceEpoch}',
                    child: Material(
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => ProfessionalProfile(
                                    professional: professional,
                                  ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(
                                  context,
                                ).colorScheme.shadow.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
                                child: Image.network(
                                  professional['image'] ?? '',
                                  height: 140,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      height: 140,
                                      width: double.infinity,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer,
                                      child: Icon(
                                        Icons.person,
                                        size: 50,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                      ),
                                    );
                                  },
                                  loadingBuilder: (
                                    BuildContext context,
                                    Widget child,
                                    ImageChunkEvent? loadingProgress,
                                  ) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      height: 140,
                                      width: double.infinity,
                                      color: Colors.grey.shade100,
                                      child: Center(
                                        child: PlatformLoadingIndicator(
                                          size: 15.0,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      professional['name'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      professional['profession'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.secondary,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Column(
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.work_outline,
                                              size: 16,
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.secondary,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                professional['experience'] ??
                                                    '',
                                                style: TextStyle(
                                                  color:
                                                      Theme.of(
                                                        context,
                                                      ).colorScheme.secondary,
                                                  fontSize: 12,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.location_on_outlined,
                                              size: 16,
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.secondary,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                professional['distance'] ?? '',
                                                style: TextStyle(
                                                  color:
                                                      Theme.of(
                                                        context,
                                                      ).colorScheme.secondary,
                                                  fontSize: 12,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
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
                    ),
                  );
                },
              ),
    );
  }
}
