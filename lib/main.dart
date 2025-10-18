// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart'; // Import App Check
import 'firebase_options.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase for the current platform
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // NEW: Activate App Check with the debug provider
  // This allows your emulator to communicate with Firebase
  await FirebaseAppCheck.instance.activate(
    // You can also use a provider other than `AndroidProvider.debug`
    androidProvider: AndroidProvider.debug,
  );

  runApp(const MyApp());
}
