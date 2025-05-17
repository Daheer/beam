// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/snackbar_service.dart';
import 'home_page.dart';
import 'login_page.dart';

class EmailVerificationPage extends StatefulWidget {
  final User user;

  const EmailVerificationPage({super.key, required this.user});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  bool _isEmailVerified = false;
  bool _canResendEmail = true;
  bool _isLoading = false;
  Timer? _timer;
  Timer? _resendTimer;
  int _resendCountdown = 0;

  @override
  void initState() {
    super.initState();
    // Show initial verification message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        SnackbarService.showInfo(
          context,
          message: 'Verification email sent. Please check your inbox.',
          duration: const Duration(seconds: 5),
        );
      }
    });

    // User might have verified email already, check once at start
    _checkEmailVerification();

    // Set up a timer to periodically check if email has been verified
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkEmailVerification(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkEmailVerification() async {
    // Need to reload user data to get current verification status
    await widget.user.reload();
    final user = FirebaseAuth.instance.currentUser;

    if (user != null && user.emailVerified) {
      setState(() {
        _isEmailVerified = true;
      });
      _timer?.cancel();

      // Navigate to home page after a short delay to show success state
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        }
      });
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (!_canResendEmail) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await widget.user.sendEmailVerification();

      setState(() {
        _canResendEmail = false;
        _resendCountdown = 60; // 60 seconds cooldown
      });

      // Set up countdown timer for resend button
      _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_resendCountdown > 0) {
          setState(() {
            _resendCountdown--;
          });
        } else {
          setState(() {
            _canResendEmail = true;
          });
          timer.cancel();
        }
      });

      SnackbarService.showSuccess(
        context,
        message: 'Verification email sent. Please check your inbox.',
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      SnackbarService.showError(
        context,
        message: 'Error sending verification email: ${e.toString()}',
        duration: const Duration(seconds: 3),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mark_email_unread_outlined,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Verify Your Email',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withOpacity(0.3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.email_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.user.email ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      _isEmailVerified
                          ? Colors.green.withOpacity(0.1)
                          : Theme.of(
                            context,
                          ).colorScheme.secondaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      _isEmailVerified
                          ? Icons.check_circle
                          : Icons.info_outline,
                      color:
                          _isEmailVerified
                              ? Colors.green
                              : Theme.of(context).colorScheme.secondary,
                      size: 28,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isEmailVerified
                          ? 'Email verified! Redirecting...'
                          : 'Click the link in the email to verify your account.\n'
                              'If you don\'t see the email, check your spam folder.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color:
                            _isEmailVerified
                                ? Colors.green
                                : Theme.of(context).colorScheme.secondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              if (!_isEmailVerified)
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _checkEmailVerification,
                  icon: const Icon(Icons.refresh),
                  label: const Text('I\'ve verified my email'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              const SizedBox(height: 16),
              if (!_isEmailVerified)
                OutlinedButton.icon(
                  onPressed:
                      (_isLoading || !_canResendEmail)
                          ? null
                          : _resendVerificationEmail,
                  icon: const Icon(Icons.email_outlined),
                  label:
                      _canResendEmail
                          ? const Text('Resend verification email')
                          : Text('Resend email in $_resendCountdown seconds'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Back to Login'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
