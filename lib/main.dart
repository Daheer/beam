import 'package:beam/services/snackbar_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/email_verification_page.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

// Handle background messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you need to ensure Firebase is initialized for background handlers
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Note: this runs in a separate isolate, so you can't interact with the UI
  // or run complex operations.

  // Don't need to show notification, it will be handled by FCM automatically
  // But if you need to do something with the data, you can do it here
}

void main() async {
  // Ensure plugin services are initialized
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(); // Load .env file
  } catch (e) {
    // Continue without .env if it fails
  }

  // Initialize Firebase first
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Continue without Firebase if it fails, app will have limited functionality
  }

  // Set up background message handler
  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    // Continue without background handler if it fails
  }

  // Initialize notification service after Firebase is initialized
  try {
    await NotificationService().initialize();
  } catch (e) {
    // Continue without notification service if it fails
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _setupNotifications();
  }

  void _setupNotifications() {
    try {
      // Set up foreground notification handling
      NotificationService().setupForegroundNotificationHandling();

      // Handle notification clicks when app is in background but not terminated
      try {
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          if (message.data.containsKey('type') &&
              message.data['type'] == 'call') {
            // This will be handled by the HomePage widget when it mounts
            // as it already listens for incoming calls
          }
        });
      } catch (e) {
        SnackbarService.showError(
          context,
          message: 'Error setting up notifications: $e',
        );
      }
    } catch (e) {
      SnackbarService.showError(
        context,
        message: 'Error setting up notifications: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.schibstedGroteskTextTheme(
          Theme.of(context).textTheme,
        ),
        fontFamily: GoogleFonts.schibstedGrotesk().fontFamily,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.schibstedGroteskTextTheme(
          Theme.of(context).textTheme.copyWith(
            // Ensure texts are readable in dark theme
            bodyMedium: TextStyle(color: Colors.white70),
          ),
        ),
        fontFamily: GoogleFonts.schibstedGrotesk().fontFamily,
      ),
      // home: const LoginPage(),
      home: StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Check if user is signed in
          if (snapshot.hasData) {
            final user = snapshot.data as User;

            // Check if email is verified
            if (!user.emailVerified) {
              return EmailVerificationPage(user: user);
            }

            return const HomePage();
          }

          return const LoginPage();
        },
      ),
    );
  }
}
