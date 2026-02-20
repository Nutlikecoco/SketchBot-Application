import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'pages/homescaffold.dart';
import 'pages/login.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          // ✅ ถ้า login แล้ว → เข้าหน้า HomeScaffold ที่มี BottomNavigationBar
          return const HomeScaffold();
        }
        // 🚪 ถ้ายังไม่ได้ login → ไป LoginPage
        return const LoginPage();
      },
    );
  }
}
