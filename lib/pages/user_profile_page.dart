import 'package:beam/services/log_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:marquee/marquee.dart';
import 'dart:io';
import 'dart:math';
import '../pages/login_page.dart';
import '../services/upload_service.dart';
import '../services/user_service.dart';
import '../services/snackbar_service.dart';
import '../pages/quiz_page.dart';
import '../pages/quiz_result_page.dart';
import '../models/profession.dart';
import '../widgets/platform_loading_indicator.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

// Function to get human-readable address from coordinates
Future<String> getAddressFromLatLng(GeoPoint geoPoint) async {
  try {
    List<Placemark> placemarks = await placemarkFromCoordinates(
      geoPoint.latitude,
      geoPoint.longitude,
    );

    if (placemarks.isNotEmpty) {
      Placemark place = placemarks[0];
      // Create a more compact display format
      String locality = place.locality ?? '';
      String adminArea = place.administrativeArea ?? '';
      String country = place.country ?? '';

      // First try with locality and admin area
      String location = '';
      if (locality.isNotEmpty && adminArea.isNotEmpty) {
        // If locality and adminArea are the same, don't repeat
        if (locality == adminArea) {
          location = locality;
        } else {
          location = '$locality, $adminArea';
        }
      } else if (locality.isNotEmpty) {
        location = locality;
      } else if (adminArea.isNotEmpty) {
        location = adminArea;
      } else if (country.isNotEmpty) {
        location = country;
      }

      // If we couldn't get a meaningful location, use the country
      if (location.isEmpty && country.isNotEmpty) {
        location = country;
      }

      return location.isEmpty ? 'Unknown location' : location;
    }
    return 'Unknown location';
  } catch (e) {
    LogService.e('Error getting address', e, StackTrace.current);
    return 'Invalid location';
  }
}

// Function to calculate distance between two positions
Future<double> getDistanceBetween(GeoPoint point1, GeoPoint point2) async {
  try {
    final distanceInMeters = Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
    return distanceInMeters / 1000; // Convert to kilometers
  } catch (e) {
    LogService.e('Error calculating distance', e, StackTrace.current);
    return -1; // Return -1 to indicate error
  }
}

class _UserProfilePageState extends State<UserProfilePage> {
  bool _isEditing = false;
  bool _isLoading = true;
  final _imagePicker = ImagePicker();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserService _userService = UserService();

  Map<String, dynamic> _userData = {};
  final Map<String, TextEditingController> _controllers = {};
  String _locationString = 'Loading location...';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Use Future.microtask to ensure the context is available
    Future.microtask(() => _loadUserData());
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final User? currentUser = _auth.currentUser;

      if (currentUser != null) {
        LogService.i('Loading user data for ${currentUser.uid}');

        try {
          // Use the UserService instead of direct Firestore access
          final userData = await _userService.getCurrentUserData();

          if (userData != null) {
            // Convert the GeoPoint to a human-readable address if it exists
            if (userData['location'] is GeoPoint) {
              _locationString = await getAddressFromLatLng(
                userData['location'],
              );
            } else {
              _locationString = 'Location not set';
            }

            setState(() {
              _userData = userData;
              // Handle the case where skills might be null
              _userData['skills'] ??= <String>[];
              // Ensure experience is displayed correctly
              if (_userData['experience'] is int) {
                _userData['experience'] = '${_userData['experience']} years';
              }
              // Set default image if none exists - use doodleipsum
              _userData['profileImageUrl'] ??=
                  'https://doodleipsum.com/700?i=6bff1692e77c36e5effde3d6f48fab6e&n=${currentUser.uid}';
              _userData['image'] =
                  _userData['profileImageUrl']; // For compatibility with existing code
            });

            // Initialize controllers for editable fields
            ['name', 'about'].forEach((field) {
              _controllers[field] = TextEditingController(
                text: _userData[field] ?? '',
              );
            });
          } else {
            LogService.i(
              'User document does not exist, creating default profile',
            );
            // Create a default user document if it doesn't exist
            await _createDefaultUserProfile(currentUser);
          }
        } catch (e) {
          LogService.e('Error loading profile', e, StackTrace.current);
          setState(() {
            _errorMessage = 'Error loading profile: $e';
          });
        }
      } else {
        LogService.i('No current user found');
        // Handle the case when there is no current user
        setState(() {
          _errorMessage =
              'No user logged in. Please log in to view your profile.';
        });

        if (mounted) {
          // Navigate back to login page after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const LoginPage()),
              );
            }
          });
        }
      }
    } catch (e) {
      LogService.e('Error loading profile', e, StackTrace.current);
      setState(() {
        _errorMessage = 'Error loading profile: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createDefaultUserProfile(User user) async {
    // Get current position for location
    Position? position;
    try {
      position = await _determinePosition();
    } catch (e) {
      LogService.e('Error getting position', e, StackTrace.current);
    }

    final GeoPoint location =
        position != null
            ? GeoPoint(position.latitude, position.longitude)
            : const GeoPoint(0, 0);

    if (position != null) {
      _locationString = await getAddressFromLatLng(location);
    } else {
      _locationString = 'Location not available';
    }

    final defaultUserData = {
      'name': user.displayName ?? 'New User',
      'email': user.email ?? '',
      'profession': '',
      'experience': 0,
      'location': location,
      'about': '',
      'skills': <String>[],
      'profileImageUrl':
          user.photoURL ??
          'https://doodleipsum.com/700?i=6bff1692e77c36e5effde3d6f48fab6e&n=${user.uid}',
      'isBeaming': false,
    };

    try {
      // Use UserService to update data
      await _userService.updateUserData(defaultUserData);

      setState(() {
        _userData = defaultUserData;
        _userData['image'] = _userData['profileImageUrl'];
        _userData['experience'] = '0 years';
      });

      // Initialize controllers
      ['name', 'about'].forEach((field) {
        _controllers[field] = TextEditingController(text: _userData[field]);
      });
    } catch (e) {
      SnackbarService.showError(context, message: 'Error creating profile: $e');
    }
  }

  // Function to get the current position with permission handling
  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }

    // When we reach here, permissions are granted and we can get the position
    return await Geolocator.getCurrentPosition();
  }

  Future<void> _updateLocation() async {
    // Show loading indicator
    SnackbarService.showInfo(
      context,
      message: 'Updating your location...',
      duration: const Duration(seconds: 1),
    );

    try {
      // Use UserService to update location
      final success = await _userService.updateUserLocation();

      if (success) {
        // Get updated user data
        final userData = await _userService.getCurrentUserData(
          forceRefresh: true,
        );

        if (userData != null && userData['location'] is GeoPoint) {
          String address = await getAddressFromLatLng(userData['location']);

          setState(() {
            _userData['location'] = userData['location'];
            _locationString = address;
          });

          SnackbarService.showSuccess(
            context,
            message: 'Location updated to: $address',
          );
        }
      } else {
        SnackbarService.showError(
          context,
          message: 'Failed to update location',
        );
      }
    } catch (e) {
      LogService.e('Error updating location', e, StackTrace.current);
      SnackbarService.showError(
        context,
        message:
            'Failed to update location: ${e.toString().substring(0, min(e.toString().length, 50))}',
      );
    }
  }

  @override
  void dispose() {
    _controllers.values.forEach((controller) => controller.dispose());
    super.dispose();
  }

  Widget _buildStatCard(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    bool showEditIcon = false,
  }) {
    final bool isLocation = label == 'Location';

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
          isLocation
              ? SizedBox(
                height: 20,
                child: Marquee(
                  text: value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  scrollAxis: Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  blankSpace: 20.0,
                  velocity: 30.0,
                  pauseAfterRound: const Duration(seconds: 1),
                  startPadding: 10.0,
                  accelerationDuration: const Duration(seconds: 1),
                  accelerationCurve: Curves.linear,
                  decelerationDuration: const Duration(milliseconds: 500),
                  decelerationCurve: Curves.easeOut,
                ),
              )
              : Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
          if (showEditIcon)
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Icon(
                  Icons.edit,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );
      if (image != null) {
        setState(() {
          _isLoading = true;
        });

        // Upload the image to Uploadcare using our service
        final String? imageUrl = await UploadService.uploadImage(
          image.path,
          context: context,
          onLoadingChanged: (isLoading) {
            setState(() {
              _isLoading = isLoading;
            });
          },
        );

        if (imageUrl != null) {
          // Update the image URL using UserService
          await _userService.updateUserData({'profileImageUrl': imageUrl});

          // Update local state
          setState(() {
            _userData['image'] = imageUrl;
            _userData['profileImageUrl'] = imageUrl;
          });

          SnackbarService.showSuccess(
            context,
            message: 'Profile picture updated successfully',
          );
        } else {
          SnackbarService.showError(context, message: 'Failed to upload image');
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      SnackbarService.showError(
        context,
        message: 'Failed to update profile picture: $e',
      );
    }
  }

  Future<void> _showConfirmationDialog({
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) async {
    return showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              title,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You will need to pass a verification test to confirm your knowledge in the field.',
                          style: TextStyle(fontSize: 14, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  onConfirm();
                },
                child: const Text('Continue'),
              ),
            ],
          ),
    );
  }

  Future<void> _showProfessionDialog() async {
    await _showConfirmationDialog(
      title: 'Update Profession',
      message:
          'You are about to change your profession. This will require you to verify your knowledge in the new field.',
      onConfirm: () async {
        String? selectedProfession = _userData['profession'];
        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(
                  'Select New Profession',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Changing your profession will require verification. Please select your new profession:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: selectedProfession,
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Profession',
                        labelStyle: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                        ),
                        prefixIcon: Icon(
                          Icons.work_outline,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.3),
                          ),
                        ),
                      ),
                      items:
                          Profession.techProfessions.map((profession) {
                            return DropdownMenuItem<String>(
                              value: profession.name,
                              child: Row(
                                children: [
                                  Text(profession.icon),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      profession.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                      onChanged: (value) {
                        selectedProfession = value;
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (selectedProfession != null &&
                          selectedProfession!.isNotEmpty) {
                        // Close the dialog
                        Navigator.pop(context);
                        // Start verification process
                        _startProfessionVerification(selectedProfession);
                      }
                    },
                    child: const Text('Update'),
                  ),
                ],
              ),
        );
      },
    );
  }

  Future<void> _showExperienceDialog() async {
    await _showConfirmationDialog(
      title: 'Update Experience',
      message:
          'You are about to change your years of experience. This will require you to verify your expertise level.',
      onConfirm: () async {
        final experienceStr = _userData['experience'].toString();
        final controller = TextEditingController(
          text: experienceStr.replaceAll(' years', ''),
        );
        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(
                  'Enter New Experience',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Changing your years of experience will require verification. Enter your new experience:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Years of Experience',
                        labelStyle: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                        ),
                        border: OutlineInputBorder(),
                        suffixText: 'years',
                        suffixStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (controller.text.isNotEmpty) {
                        final newExperience =
                            int.tryParse(controller.text) ?? 0;
                        // Close the dialog
                        Navigator.pop(context);
                        // Start verification process
                        _startProfessionVerification(
                          _userData['profession'],
                          newExperience,
                        );
                      }
                    },
                    child: const Text('Update'),
                  ),
                ],
              ),
        );
      },
    );
  }

  void _startProfessionVerification([
    String? newProfession,
    int? newExperience,
  ]) {
    // Navigate to quiz page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => QuizPage(
              profession: newProfession ?? _userData['profession'],
              experience:
                  newExperience ??
                  int.tryParse(
                    _userData['experience'].toString().replaceAll(' years', ''),
                  ) ??
                  1,
              onQuizComplete:
                  (isPassed) => _handleQuizComplete(
                    isPassed,
                    newProfession,
                    newExperience,
                  ),
            ),
      ),
    );
  }

  void _handleQuizComplete(
    bool isPassed,
    String? newProfession,
    int? newExperience,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => QuizResultPage(
              isPassed: isPassed,
              onContinue: () async {
                if (isPassed) {
                  // Update the values in Firestore and local state
                  final updates = <String, dynamic>{};
                  if (newProfession != null) {
                    updates['profession'] = newProfession;
                  }
                  if (newExperience != null) {
                    updates['experience'] = newExperience;
                  }

                  try {
                    await _firestore
                        .collection('users')
                        .doc(_auth.currentUser!.uid)
                        .update(updates);

                    setState(() {
                      if (newProfession != null) {
                        _userData['profession'] = newProfession;
                      }
                      if (newExperience != null) {
                        _userData['experience'] = '$newExperience years';
                      }
                    });

                    if (mounted) {
                      SnackbarService.showSuccess(
                        context,
                        message: 'Profile updated successfully',
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      SnackbarService.showError(
                        context,
                        message: 'Failed to update profile: $e',
                      );
                    }
                  }
                }
              },
              onRetake: () {
                // Pop result page and retake the quiz
                Navigator.of(context).pop();
                _startProfessionVerification(newProfession, newExperience);
              },
              onLowerExperience: () {
                // Pop both pages and reduce experience level
                Navigator.of(context).pop();
                Navigator.of(context).pop();
                if (newExperience != null && newExperience > 1) {
                  _startProfessionVerification(
                    newProfession,
                    newExperience - 1,
                  );
                } else {
                  SnackbarService.showInfo(
                    context,
                    message: 'Experience level already at minimum',
                  );
                }
              },
            ),
      ),
    );
  }

  void _toggleEdit() {
    if (_isEditing) {
      // Save changes
      setState(() {
        _userData['name'] = _controllers['name']!.text;
        _userData['about'] = _controllers['about']!.text;
        _isEditing = false;
      });

      // Update Firestore
      _firestore.collection('users').doc(_auth.currentUser!.uid).update({
        'name': _userData['name'],
        'about': _userData['about'],
      });
    } else {
      setState(() {
        _isEditing = true;
      });
    }
  }

  void _signOut() async {
    // Show confirmation dialog
    final shouldSignOut =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Sign Out'),
                content: const Text('Are you sure you want to sign out?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('CANCEL'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('SIGN OUT'),
                  ),
                ],
              ),
        ) ??
        false;

    if (shouldSignOut) {
      try {
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false, // Remove all previous routes
          );
        }
      } catch (e) {
        if (mounted) {
          SnackbarService.showError(context, message: 'Error signing out: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:
          _isLoading
              ? Center(
                child: PlatformLoadingIndicator(
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
              : _errorMessage != null
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 60,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadUserData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
              : CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 300,
                    pinned: true,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    actions: [
                      IconButton(
                        icon: Icon(
                          _isEditing ? Icons.check : Icons.settings,
                          color: Colors.white,
                        ),
                        onPressed: _toggleEdit,
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          _userData['image'] != null
                              ? _userData['image'].toString().startsWith('http')
                                  ? Image.network(
                                    _userData['image'],
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary.withOpacity(0.3),
                                        child: Icon(
                                          Icons.person,
                                          size: 80,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        ),
                                      );
                                    },
                                  )
                                  : Image.file(
                                    File(_userData['image']),
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary.withOpacity(0.3),
                                        child: Icon(
                                          Icons.person,
                                          size: 80,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        ),
                                      );
                                    },
                                  )
                              : Container(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.3),
                                child: Icon(
                                  Icons.person,
                                  size: 80,
                                  color: Theme.of(context).colorScheme.primary,
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
                          if (_isEditing)
                            Positioned(
                              left: 16,
                              bottom: 16,
                              child: FloatingActionButton(
                                heroTag: "signOutBtn",
                                backgroundColor: Colors.red.shade700,
                                onPressed: _signOut,
                                child: const Icon(
                                  Icons.logout,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          if (_isEditing)
                            Positioned(
                              right: 16,
                              bottom: 16,
                              child: FloatingActionButton(
                                heroTag: "cameraBtn",
                                onPressed: _pickImage,
                                child: const Icon(Icons.camera_alt),
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
                  SliverToBoxAdapter(
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _isEditing
                                ? TextFormField(
                                  controller: _controllers['name'],
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Enter your name',
                                    hintStyle: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.7),
                                    ),
                                    border: InputBorder.none,
                                    suffixIcon: Icon(
                                      Icons.edit,
                                      size: 20,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                )
                                : Text(
                                  _userData['name'] ?? 'No Name',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _isEditing ? _showProfessionDialog : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _userData['profession'] ??
                                          'Add Profession',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (_isEditing) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.edit,
                                        size: 16,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap:
                                        _isEditing
                                            ? _showExperienceDialog
                                            : null,
                                    child: _buildStatCard(
                                      context,
                                      Icons.work_outline,
                                      'Experience',
                                      _userData['experience'] ?? '0 years',
                                      showEditIcon: _isEditing,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: InkWell(
                                    onTap: _isEditing ? _updateLocation : null,
                                    child: _buildStatCard(
                                      context,
                                      Icons.location_on_outlined,
                                      'Location',
                                      _locationString,
                                      showEditIcon: _isEditing,
                                    ),
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
                            _isEditing
                                ? TextFormField(
                                  controller: _controllers['about'],
                                  maxLines: null,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    height: 1.6,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Tell us about yourself',
                                    hintStyle: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.7),
                                    ),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: Icon(
                                      Icons.edit,
                                      size: 20,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                )
                                : Text(
                                  _userData['about'] ??
                                      'Add some information about yourself',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                    height: 1.6,
                                  ),
                                ),
                            const SizedBox(height: 32),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                if (_isEditing)
                                  IconButton(
                                    onPressed: _showAddSkillDialog,
                                    icon: Icon(
                                      Icons.add_circle_outline,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            (_userData['skills'] ?? []).isEmpty
                                ? Text(
                                  'No skills added yet',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                                : Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children:
                                      (_userData['skills'] as List<dynamic>)
                                          .map<Widget>(
                                            (skill) => Chip(
                                              label: Text(skill.toString()),
                                              backgroundColor:
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .secondaryContainer,
                                              deleteIcon:
                                                  _isEditing
                                                      ? const Icon(
                                                        Icons.close,
                                                        size: 16,
                                                      )
                                                      : null,
                                              onDeleted:
                                                  _isEditing
                                                      ? () => _removeSkill(
                                                        skill.toString(),
                                                      )
                                                      : null,
                                            ),
                                          )
                                          .toList(),
                                ),
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
    );
  }

  Future<void> _showAddSkillDialog() async {
    final controller = TextEditingController();
    return showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Skill'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Add a new skill to your profile:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Skill',
                    labelStyle: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                    hintStyle: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (controller.text.isNotEmpty) {
                    _addSkill(controller.text);
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }

  void _addSkill(String skill) {
    setState(() {
      final skills = List<String>.from(_userData['skills'] ?? []);
      if (!skills.contains(skill)) {
        skills.add(skill);
        _userData['skills'] = skills;

        // Update Firestore
        _firestore.collection('users').doc(_auth.currentUser!.uid).update({
          'skills': skills,
        });
      }
    });
  }

  void _removeSkill(String skill) {
    setState(() {
      final skills = List<String>.from(_userData['skills'] ?? []);
      skills.remove(skill);
      _userData['skills'] = skills;

      // Update Firestore
      _firestore.collection('users').doc(_auth.currentUser!.uid).update({
        'skills': skills,
      });
    });
  }

  Future<void> _saveChanges() async {
    // Get updated values from controllers
    final updatedUserData = {
      'name': _controllers['name']!.text.trim(),
      'about': _controllers['about']!.text.trim(),
    };

    try {
      // Use UserService to update data
      await _userService.updateUserData(updatedUserData);

      // Update local state
      setState(() {
        _userData.addAll(updatedUserData);
        _isEditing = false;
      });

      SnackbarService.showSuccess(
        context,
        message: 'Profile updated successfully',
      );
    } catch (e) {
      SnackbarService.showError(
        context,
        message: 'Failed to update profile: $e',
      );
    }
  }
}
