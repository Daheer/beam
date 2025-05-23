import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/email_verification_page.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'pages/activity_history_page.dart';
import 'dart:io' show Platform;
import 'services/log_service.dart';

// Handle background messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you need to ensure Firebase is initialized for background handlers
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Don't need to show notification, it will be handled by FCM automatically
  // But we can process the data if needed
}

void main() async {
  // Ensure plugin services are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations to portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

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

    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request permission for iOS
    if (Platform.isIOS) {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
    }

    // Get FCM token (for debugging)
    String? token = await FirebaseMessaging.instance.getToken();
  } catch (e) {
    // Continue without Firebase if it fails, app will have limited functionality
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
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (message.data.containsKey('type')) {
          if (message.data['type'] == 'call') {
            // This will be handled by the HomePage widget
          } else if (message.data['type'] == 'interest_request') {
            // Navigate to activity history page
            String? requestId = message.data['requestId'];
            if (requestId != null) {
              // Add a small delay to ensure navigation context is ready
              Future.delayed(Duration(milliseconds: 500), () {
                _navigateToActivityHistory(requestId);
              });
            }
          }
        }
      });

      // Check if app was opened from terminated state via notification
      FirebaseMessaging.instance.getInitialMessage().then((
        RemoteMessage? message,
      ) {
        if (message != null) {
          // Add delay to ensure app is initialized
          Future.delayed(Duration(seconds: 1), () {
            if (message.data.containsKey('type') &&
                message.data['type'] == 'interest_request') {
              String? requestId = message.data['requestId'];
              if (requestId != null) {
                _navigateToActivityHistory(requestId);
              }
            }
          });
        }
      });
    } catch (e) {
      LogService.e('Error setting up notifications', e, StackTrace.current);
    }
  }

  void _navigateToActivityHistory(String? requestId) {
    final context = navigatorKey.currentContext;
    if (context != null && requestId != null) {
      // Pop to root to avoid stacking multiple ActivityHistoryPages
      Navigator.of(context).popUntil((route) => route.isFirst);

      // Navigate to ActivityHistoryPage
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (context) =>
                  ActivityHistoryPage(notificationRequestId: requestId),
        ),
      );
    }
  }

  // Global navigator key for context-free navigation
  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // Add navigator key
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
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
        // Add input decoration theme for dark mode
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: TextStyle(color: Colors.white70),
          hintStyle: TextStyle(color: Colors.white60),
          // Set the text style for the input
          suffixStyle: TextStyle(color: Colors.white70),
          prefixStyle: TextStyle(color: Colors.white70),
        ),
      ),
      // home: const LoginPage(),
      home: StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox.shrink();
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
