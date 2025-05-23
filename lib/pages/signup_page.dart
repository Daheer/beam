import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'login_page.dart';
import 'quiz_page.dart';
import 'quiz_result_page.dart';
import 'dart:io';
import '../services/upload_service.dart';
import '../services/snackbar_service.dart';
import '../models/profession.dart';
import '../widgets/platform_loading_indicator.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  static const String routeName = 'signup_page';

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _pageController = PageController();
  final _authFormKey = GlobalKey<FormState>();
  final _profileFormKey = GlobalKey<FormState>();

  // Text controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _professionController = TextEditingController();
  final _experienceController = TextEditingController();
  final _aboutController = TextEditingController();

  // User data
  UserCredential? _userCredential;
  final List<String> _skills = [];
  String? _profileImagePath;
  Position? _userLocation;
  String _locationStatus = 'Not set yet';

  // State management
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  int _currentPage = 0;
  final int _totalPages = 5;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _professionController.dispose();
    _experienceController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  Future<void> _createUserAccount() async {
    FirebaseAuth auth = FirebaseAuth.instance;

    try {
      setState(() {
        _isLoading = true;
      });

      // Create user with email and password
      _userCredential = await auth.createUserWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );

      // Update display name
      if (_userCredential?.user != null) {
        await _userCredential!.user!.updateDisplayName(_nameController.text);

        // Send email verification
        await _userCredential!.user!.sendEmailVerification();

        // Show success message with verification instructions
        if (mounted) {
          SnackbarService.showSuccess(
            context,
            message: 'Verification email sent. Please check your inbox.',
            duration: const Duration(seconds: 5),
          );
        }
      }

      // Move to the next step
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _nextPage();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      // Show error message
      if (mounted) {
        SnackbarService.showError(
          context,
          message: 'Error creating account: $e',
        );
      }
    }
  }

  Future<void> _completeSignup() async {
    FirebaseFirestore firestore = FirebaseFirestore.instance;

    try {
      setState(() {
        _isLoading = true;
      });

      if (_userCredential?.user != null) {
        // Upload profile image if selected and get URL
        String? profileImageUrl;
        if (_profileImagePath != null) {
          profileImageUrl = await UploadService.uploadImage(
            _profileImagePath!,
            context: context,
            onLoadingChanged: (isLoading) {
              setState(() {
                _isLoading = isLoading;
              });
            },
          );
        }

        // Create a document in Firestore with full user data
        GeoPoint? locationPoint;
        if (_userLocation != null) {
          locationPoint = GeoPoint(
            _userLocation!.latitude,
            _userLocation!.longitude,
          );
        }

        await firestore
            .collection('users')
            .doc(_userCredential!.user!.uid)
            .set({
              'name': _nameController.text,
              'email': _emailController.text,
              'profession': _professionController.text,
              'experience': int.tryParse(_experienceController.text) ?? 0,
              'location': locationPoint ?? const GeoPoint(0, 0),
              'about': _aboutController.text,
              'skills': _skills,
              'profileImageUrl': profileImageUrl ?? '',
              'isBeaming': false,
              'createdAt': FieldValue.serverTimestamp(),
            });

        // Navigate to login page so user can sign in
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginPage()),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      // Show error message
      if (mounted) {
        SnackbarService.showError(
          context,
          message: 'Error completing signup: $e',
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );
      if (image != null) {
        setState(() {
          _profileImagePath = image.path;
        });
      }
    } catch (e) {
      SnackbarService.showError(context, message: 'Failed to pick image: $e');
    }
  }

  Future<void> _requestLocationPermission() async {
    setState(() {
      _locationStatus = 'Requesting permission...';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationStatus = 'Location services are disabled';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationStatus = 'Location permission denied';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationStatus = 'Location permissions permanently denied';
        });
        return;
      }

      // Permission granted, get current position
      _userLocation = await Geolocator.getCurrentPosition();

      // Get address from coordinates
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          _userLocation!.latitude,
          _userLocation!.longitude,
        );

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          String address = [
            if (place.street?.isNotEmpty == true) place.street,
            if (place.locality?.isNotEmpty == true) place.locality,
            if (place.administrativeArea?.isNotEmpty == true)
              place.administrativeArea,
            if (place.country?.isNotEmpty == true) place.country,
          ].where((element) => element != null).join(', ');

          setState(() {
            _locationStatus = 'Location set: $address';
          });
        } else {
          setState(() {
            _locationStatus =
                'Location set: ${_userLocation!.latitude.toStringAsFixed(4)}, ${_userLocation!.longitude.toStringAsFixed(4)}';
          });
        }
      } catch (e) {
        // Fallback to coordinates if geocoding fails
        setState(() {
          _locationStatus =
              'Location set: ${_userLocation!.latitude.toStringAsFixed(4)}, ${_userLocation!.longitude.toStringAsFixed(4)}';
        });
      }
    } catch (e) {
      setState(() {
        _locationStatus = 'Error getting location: $e';
      });
    }
  }

  void _addSkill(String skill) {
    if (skill.isNotEmpty && !_skills.contains(skill)) {
      setState(() {
        _skills.add(skill);
      });
    }
  }

  void _removeSkill(String skill) {
    setState(() {
      _skills.remove(skill);
    });
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _startProfessionVerification() {
    // Navigate to quiz page with a name for the route
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: 'quiz_page'),
        builder:
            (context) => QuizPage(
              profession: _professionController.text,
              experience: int.tryParse(_experienceController.text) ?? 1,
              onQuizComplete: _handleQuizComplete,
            ),
      ),
    );
  }

  void _handleQuizComplete(bool isPassed) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => QuizResultPage(
              isPassed: isPassed,
              onContinue: () {
                if (isPassed) {
                  // Pop all quiz-related pages and return to signup flow
                  Navigator.of(context).popUntil(
                    (route) =>
                        route.settings.name == 'signup_page' || route.isFirst,
                  );
                  // Move to next step in signup
                  _nextPage();
                }
              },
              onRetake: () {
                // Pop result page and retake the quiz
                Navigator.of(context).pop();
                _startProfessionVerification();
              },
              onLowerExperience: () {
                // Pop both pages and reduce experience level
                Navigator.of(context).pop();
                Navigator.of(context).pop();
                final currentExp =
                    int.tryParse(_experienceController.text) ?? 1;
                if (currentExp > 1) {
                  setState(() {
                    _experienceController.text = (currentExp - 1).toString();
                  });
                  SnackbarService.showSuccess(
                    context,
                    message:
                        'Experience level reduced to ${currentExp - 1} years',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Your Profile'),
        centerTitle: true,
        leading:
            _currentPage > 0
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _previousPage,
                )
                : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed:
                      () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => const LoginPage(),
                        ),
                      ),
                ),
      ),
      body: Column(
        children: [
          // Progress indicator
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SmoothPageIndicator(
              controller: _pageController,
              count: _totalPages,
              effect: ExpandingDotsEffect(
                activeDotColor: Theme.of(context).colorScheme.primary,
                dotHeight: 8,
                dotWidth: 8,
                spacing: 4,
              ),
              onDotClicked: (index) {
                // Only allow going back, not forward
                if (index < _currentPage) {
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
            ),
          ),

          // Page content
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              physics: const NeverScrollableScrollPhysics(), // Disable swiping
              children: [
                _buildAuthPage(),
                _buildProfilePage(),
                _buildSkillsPage(),
                _buildLocationPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Form(
        key: _authFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Image.asset(
                'assets/icon/splash_icon.png',
                width: 250,
                height: 250,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),

            // Text(
            //   'Create Account',
            //   style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            //     fontWeight: FontWeight.bold,
            //     color: Theme.of(context).colorScheme.primary,
            //   ),
            //   textAlign: TextAlign.center,
            // ),
            Text(
              'Create Account • Sign up to get started',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _nameController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Full Name',
                hintText: 'Enter your full name',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                hintText: 'Enter your email',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                }
                if (!RegExp(
                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                ).hasMatch(value)) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              obscureText: !_isPasswordVisible,
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Enter your password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmPasswordController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              obscureText: !_isConfirmPasswordVisible,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                hintText: 'Confirm your password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isConfirmPasswordVisible
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please confirm your password';
                }
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed:
                  _isLoading
                      ? null
                      : () {
                        if (_authFormKey.currentState!.validate()) {
                          _createUserAccount();
                        }
                      },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child:
                  _isLoading
                      ? PlatformLoadingIndicator(
                        color: Theme.of(context).colorScheme.onPrimary,
                      )
                      : const Text(
                        'CONTINUE',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Already have an account?'),
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginPage(),
                      ),
                    );
                  },
                  child: const Text('Login'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfilePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _profileFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.1),
                    backgroundImage:
                        _profileImagePath != null
                            ? FileImage(File(_profileImagePath!))
                            : null,
                    child:
                        _profileImagePath == null
                            ? Icon(
                              Icons.person,
                              size: 60,
                              color: Theme.of(context).colorScheme.primary,
                            )
                            : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(8.0),
                      child: InkWell(
                        onTap: _pickImage,
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Text(
              'Professional Profile',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Tell us about your professional background',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Profession',
                prefixIcon: const Icon(Icons.work_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
              ),
              hint: const Text('Select your profession'),
              value:
                  _professionController.text.isEmpty
                      ? null
                      : _professionController.text,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select your profession';
                }
                return null;
              },
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
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _professionController.text = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _experienceController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Years of Experience',
                hintText: 'e.g. 5',
                prefixIcon: const Icon(Icons.calendar_today_outlined),
                suffixText: 'years',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your years of experience';
                }
                if (int.tryParse(value) == 0) {
                  return 'Experience must be at least 1 year';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _aboutController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'About',
                hintText:
                    'Brief description about your professional background',
                prefixIcon: const Icon(Icons.info_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                if (_profileFormKey.currentState!.validate()) {
                  _startProfessionVerification();
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: const Text(
                'VERIFY & CONTINUE',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillsPage() {
    final TextEditingController skillController = TextEditingController();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add Your Skills',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Add skills relevant to your profession',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.secondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: skillController,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Enter skill',
                    labelStyle: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                    hintText: 'e.g. Project Management',
                    hintStyle: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      _addSkill(value);
                      skillController.clear();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  if (skillController.text.isNotEmpty) {
                    _addSkill(skillController.text);
                    skillController.clear();
                  }
                },
                icon: const Icon(Icons.add_circle),
                color: Theme.of(context).colorScheme.primary,
                iconSize: 36,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Your Skills:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child:
                _skills.isEmpty
                    ? Center(
                      child: Text(
                        'No skills added yet',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                    : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          _skills.map((skill) {
                            return Chip(
                              label: Text(skill),
                              backgroundColor:
                                  Theme.of(
                                    context,
                                  ).colorScheme.secondaryContainer,
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => _removeSkill(skill),
                            );
                          }).toList(),
                    ),
          ),
          ElevatedButton(
            onPressed: () {
              // Proceed even if no skills added
              _nextPage();
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: const Text(
              'CONTINUE',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.location_on, size: 70, color: Colors.red),
          const SizedBox(height: 20),
          Text(
            'Location Access',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Allow access to your location to connect with professionals nearby',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.secondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  'Location Status',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(_locationStatus),
              ],
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: _requestLocationPermission,
            icon: const Icon(Icons.location_searching),
            label: const Text('SHARE MY LOCATION'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {
              // Skip location permission and proceed with default
              _userLocation = null;
              _completeSignup();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'SKIP FOR NOW',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _isLoading ? null : _completeSignup,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child:
                _isLoading
                    ? PlatformLoadingIndicator(
                      color: Theme.of(context).colorScheme.onPrimary,
                    )
                    : const Text(
                      'COMPLETE SIGNUP',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
