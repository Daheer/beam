// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAkpUKMXi6M8Gs7jzpDNbHXkP1Zu0Ljdeo',
    appId: '1:623564999295:web:bedc1ca5b18590205f8d4a',
    messagingSenderId: '623564999295',
    projectId: 'beam-networking',
    authDomain: 'beam-networking.firebaseapp.com',
    storageBucket: 'beam-networking.firebasestorage.app',
    measurementId: 'G-N0XFRQQHGZ',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCwZQJ8RSICQUuRqvCO1vNP-Ra0ej_tqNE',
    appId: '1:623564999295:android:c035fa0544c2d8ac5f8d4a',
    messagingSenderId: '623564999295',
    projectId: 'beam-networking',
    storageBucket: 'beam-networking.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCA2qaldk8Qiu2Fy_M2Xrwc40FsupvdDGA',
    appId: '1:623564999295:ios:55d48c14e0b22d6c5f8d4a',
    messagingSenderId: '623564999295',
    projectId: 'beam-networking',
    storageBucket: 'beam-networking.firebasestorage.app',
    iosBundleId: 'com.example.beamble',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCA2qaldk8Qiu2Fy_M2Xrwc40FsupvdDGA',
    appId: '1:623564999295:ios:55d48c14e0b22d6c5f8d4a',
    messagingSenderId: '623564999295',
    projectId: 'beam-networking',
    storageBucket: 'beam-networking.firebasestorage.app',
    iosBundleId: 'com.example.beamble',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAkpUKMXi6M8Gs7jzpDNbHXkP1Zu0Ljdeo',
    appId: '1:623564999295:web:baa57f37583413ba5f8d4a',
    messagingSenderId: '623564999295',
    projectId: 'beam-networking',
    authDomain: 'beam-networking.firebaseapp.com',
    storageBucket: 'beam-networking.firebasestorage.app',
    measurementId: 'G-X950VZLKNN',
  );
}
