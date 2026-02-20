import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // ✅ เพิ่ม import นี้
import 'signup.dart';
import 'homescaffold.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;

  Future<void> handleLogin() async {
    // ignore: avoid_print
    print("🚀 Start login()");
    setState(() => isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      // ignore: avoid_print
      print("✅ Firebase Auth OK");
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScaffold()),
      );
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print("⚠️ FirebaseAuthException: ${e.code}");
      String msg = "Login failed";
      if (e.code == 'user-not-found') msg = "No user found for that email.";
      if (e.code == 'wrong-password') msg = "Wrong password.";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      // ignore: avoid_print
      print("❌ Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Unexpected error: $e")),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ✅ แก้ไขส่วนนี้
  Future<void> handleGoogleLogin() async {
    try {
      // 🔹 เริ่มกระบวนการล็อกอินด้วย Google
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 🔹 ล็อกอินเข้ากับ Firebase
      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) return;

      // ✅ ตรวจสอบว่ามี document ใน Firestore แล้วหรือยัง
      final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final docSnap = await docRef.get();

      if (!docSnap.exists) {
        // 🔹 ถ้ายังไม่มี ให้สร้างใหม่ (เพื่อให้ rules ไม่ block)
        await docRef.set({
          "name": user.displayName ?? "",
          "email": user.email ?? "",
          "dob": "",
          "imageUrl": user.photoURL ?? "",
          "createdAt": FieldValue.serverTimestamp(),
        });
        // ignore: avoid_print
        print("🆕 Created new Firestore document for Google user ${user.uid}");
      } else {
        // ignore: avoid_print
        print("✅ Existing user found in Firestore: ${user.uid}");
      }

      // 🔹 ไปหน้า Home
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScaffold()),
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print("❌ Google login failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Google login failed: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 19, 31, 140), // พื้นหลังน้ำเงิน
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white, // 👉 ป๊อบอัพสีขาว
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/newlogo.png', height: 100),
                const SizedBox(height: 16),
                const Text(
                  "Welcome",
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // Email
                TextFormField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: "Email",
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Password
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: "Password",
                    prefixIcon: const Icon(Icons.lock),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Login button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : handleLogin,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(
                            color: Color.fromARGB(255, 19, 31, 140),
                          )
                        : const Text("Login", style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 12),

                // Google login button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: handleGoogleLogin,
                    icon: Image.asset(
                      'assets/images/google.png',
                      height: 20,
                      width: 20,
                    ),
                    label: const Text("Sign in with Google"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account? "),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SignupPage()),
                        );
                      },
                      child: const Text(
                        "Sign Up",
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
