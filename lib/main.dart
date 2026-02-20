import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart'; 
import 'firebase_options.dart';
import 'auth_wrapper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );


  if (kDebugMode || !Platform.isAndroid) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
    );
    debugPrint("🚀 Using App Check: Debug Provider");
  } else {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
    );
    debugPrint("🚀 Using App Check: Play Integrity");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SketchBot',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}
