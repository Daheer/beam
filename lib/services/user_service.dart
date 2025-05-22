import 'package:beam/services/log_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Cache for user data
  Map<String, dynamic>? _cachedUserData;
  DateTime? _cacheTimestamp;
  final Duration _cacheDuration = const Duration(
    minutes: 5,
  ); // Cache expires after 5 minutes

  // Check if cache is valid
  bool get _isCacheValid {
    if (_cachedUserData == null || _cacheTimestamp == null) return false;
    return DateTime.now().difference(_cacheTimestamp!) < _cacheDuration;
  }

  // Clear cache
  void clearCache() {
    _cachedUserData = null;
    _cacheTimestamp = null;
  }

  // Get current user data with cache
  Future<Map<String, dynamic>?> getCurrentUserData({
    bool forceRefresh = false,
  }) async {
    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) return null;

      // Return cached data if valid and no force refresh
      if (!forceRefresh && _isCacheValid) {
        return _cachedUserData;
      }

      // Fetch fresh data from Firestore
      final DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(currentUser.uid).get();

      if (userDoc.exists) {
        // Update cache
        _cachedUserData = userDoc.data() as Map<String, dynamic>;
        _cacheTimestamp = DateTime.now();
        return _cachedUserData;
      }
      return null;
    } catch (e) {
      LogService.e('Error getting current user data', e, StackTrace.current);
      return null;
    }
  }

  // Update user data in Firestore and cache
  Future<bool> updateUserData(Map<String, dynamic> newData) async {
    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // Update Firestore
      await _firestore.collection('users').doc(currentUser.uid).update(newData);

      // Update cache if it exists
      if (_cachedUserData != null) {
        _cachedUserData!.addAll(newData);
        _cacheTimestamp = DateTime.now();
      }

      return true;
    } catch (e) {
      LogService.e('Error updating user data', e, StackTrace.current);
      return false;
    }
  }

  // Get nearby users within a specified radius (in km)
  Future<List<Map<String, dynamic>>> getNearbyUsers({
    double radiusInKm = 10.0,
  }) async {
    try {
      // Get current user's location
      final currentUserData = await getCurrentUserData();
      if (currentUserData == null) {
        LogService.e('Current user data is null', StackTrace.current);
        return [];
      }

      if (currentUserData['location'] == null) {
        LogService.e('Current user location is null', StackTrace.current);
        return [];
      }

      final GeoPoint currentUserLocation =
          currentUserData['location'] as GeoPoint;

      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        LogService.e('Current Firebase user is null', StackTrace.current);
        return [];
      }

      final String currentUserId = currentUser.uid;

      // Fetch all users who are beaming
      final QuerySnapshot usersSnapshot;
      try {
        usersSnapshot =
            await _firestore
                .collection('users')
                .where('isBeaming', isEqualTo: true)
                .get();
      } catch (e) {
        LogService.e('Error fetching users from Firestore', StackTrace.current);
        return [];
      }

      // Filter and process users
      List<Map<String, dynamic>> nearbyUsers = [];

      for (var doc in usersSnapshot.docs) {
        try {
          // Skip the current user
          if (doc.id == currentUserId) continue;

          final userData = doc.data() as Map<String, dynamic>;

          // Skip users without location
          if (userData['location'] == null) continue;

          final GeoPoint userLocation = userData['location'] as GeoPoint;

          // Calculate distance
          final distanceInMeters = Geolocator.distanceBetween(
            currentUserLocation.latitude,
            currentUserLocation.longitude,
            userLocation.latitude,
            userLocation.longitude,
          );

          final distanceInKm = distanceInMeters / 1000;

          // Check if user is within the radius
          if (distanceInKm <= radiusInKm) {
            // Create a standardized user data object
            final Map<String, dynamic> standardizedUser = {
              'id': doc.id,
              'name': userData['name'] ?? 'Unknown User',
              'profession': userData['profession'] ?? '',
              'about': userData['about'] ?? '',
              'distance': '${distanceInKm.toStringAsFixed(1)} km',
              'distanceValue': distanceInKm,
              'skills': List<String>.from(userData['skills'] ?? []),
            };

            // Format experience as years
            if (userData['experience'] is int) {
              final int years = userData['experience'];
              standardizedUser['experience'] =
                  '$years ${years == 1 ? 'year' : 'years'}';
            } else {
              standardizedUser['experience'] =
                  userData['experience'] ?? 'Not specified';
            }

            // Ensure profile image URL is set - use doodleipsum instead of picsum
            standardizedUser['image'] =
                userData['profileImageUrl'] ??
                'https://doodleipsum.com/700?i=6bff1692e77c36e5effde3d6f48fab6e&n=${doc.id}';

            nearbyUsers.add(standardizedUser);
          }
        } catch (e) {
          LogService.e(
            'Error processing user ${doc.id}: $e',
            e,
            StackTrace.current,
          );
          // Skip this user but continue with others
          continue;
        }
      }

      // Sort by distance
      nearbyUsers.sort(
        (a, b) => (a['distanceValue'] as double).compareTo(
          b['distanceValue'] as double,
        ),
      );

      return nearbyUsers;
    } catch (e) {
      LogService.e('Error getting nearby users', e, StackTrace.current);
      return [];
    }
  }

  // Update user's location
  Future<bool> updateUserLocation() async {
    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return false;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );

      final updatedLocation = GeoPoint(position.latitude, position.longitude);

      // Update user document
      await _firestore.collection('users').doc(currentUser.uid).update({
        'location': updatedLocation,
      });

      // Update cache if it exists
      if (_cachedUserData != null) {
        _cachedUserData!['location'] = updatedLocation;
        _cacheTimestamp = DateTime.now();
      }

      return true;
    } catch (e) {
      LogService.e('Error updating user location', e, StackTrace.current);
      return false;
    }
  }
}
