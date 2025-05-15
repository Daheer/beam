import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'services/zego_service.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/email_verification_page.dart';
import 'firebase_options.dart';

/// Define a navigator key
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(); // Load .env file
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Set navigator key to ZegoUIKitPrebuiltCallInvitationService
  ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);

  // Initialize ZEGOCLOUD system calling UI
  await ZegoUIKit().initLog().then((value) async {
    // Get the app ID and sign from .env
    final appID = int.parse(dotenv.env['ZEGO_APP_ID'] ?? '0');
    final appSign = dotenv.env['ZEGO_APP_SIGN'] ?? '';

    if (appID == 0 || appSign.isEmpty) {
      throw Exception(
        'Please provide ZEGO_APP_ID and ZEGO_APP_SIGN in .env file',
      );
    }

    // Initialize ZEGO service
    await ZegoUIKit().init(appID: appID, appSign: appSign);

    // Initialize call invitation service
    ZegoUIKitPrebuiltCallInvitationService().init(
      appID: appID,
      appSign: appSign,
      userID: FirebaseAuth.instance.currentUser?.uid ?? '',
      userName: FirebaseAuth.instance.currentUser?.displayName ?? 'User',
      plugins: [ZegoUIKitSignalingPlugin()],
    );
  });

  runApp(MyApp(navigatorKey: navigatorKey));
}

class MyApp extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const MyApp({required this.navigatorKey, Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: widget.navigatorKey,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Check if user is signed in
          if (snapshot.hasData) {
            final user = snapshot.data as User;

            // Initialize ZEGOCLOUD call service for the logged-in user
            ZegoUIKitPrebuiltCallInvitationService().init(
              appID: int.parse(dotenv.env['ZEGO_APP_ID'] ?? '0'),
              appSign: dotenv.env['ZEGO_APP_SIGN'] ?? '',
              userID: user.uid,
              userName: user.displayName ?? 'User',
              plugins: [ZegoUIKitSignalingPlugin()],
            );

            print("ZegoUIKitPrebuiltCallInvitationService initialized");
            print(ZegoUIKitPrebuiltCallInvitationService());

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

  @override
  void dispose() {
    // Uninitialize ZEGOCLOUD call service when the app is disposed
    ZegoUIKitPrebuiltCallInvitationService().uninit();
    super.dispose();
  }
}
