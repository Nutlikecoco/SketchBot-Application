import 'dart:async'; // ✅ สำหรับ TimeoutException
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../auth_wrapper.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  bool isChecked = false;
  bool isLoading = false;

  // ✅ สมัครด้วย Email + Password
  Future<void> handleSignup() async {
    if (passwordController.text != confirmPasswordController.text) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Passwords do not match")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      debugPrint("🚀 Creating user...");
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: emailController.text.trim(),
            password: passwordController.text,
          )
          .timeout(const Duration(seconds: 15));

      debugPrint("✅ Firebase Auth OK");

      final uid = cred.user!.uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
        "email": emailController.text.trim(),
        "name": "",
        "dob": "",
        "imageUrl": null,
        "createdAt": FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 15));

      debugPrint("✅ Firestore OK");

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Signup successful ✅")),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
        (route) => false,
      );
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⏱️ Timeout: Check App Check or internet")),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = "Signup failed";
      if (e.code == 'email-already-in-use') message = "Email already registered.";
      if (e.code == 'weak-password') message = "Password too weak.";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      debugPrint("⚠️ FirebaseAuthException: ${e.code}");
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Unexpected error: $e")),
      );
      debugPrint("❌ Signup error: $e");
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  // ✅ สมัคร/ล็อกอินด้วย Google
  Future<void> handleGoogleSignup() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      final uid = userCred.user!.uid;

      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          "name": userCred.user?.displayName ?? "",
          "email": userCred.user?.email,
          "dob": "",
          "imageUrl": userCred.user?.photoURL,
          "createdAt": FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Signed up with Google ✅")),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Google sign-in error: $e")),
      );
      debugPrint("❌ Google sign-in error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 19, 31, 140),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
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
                Image.asset('assets/images/newlogo.png', height: 120),
                const SizedBox(height: 16),
                const Text(
                  "Create Account",
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
                const SizedBox(height: 16),

                // Confirm Password
                TextFormField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: "Confirm Password",
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Checkbox(
                      value: isChecked,
                      onChanged: (val) {
                        if (!mounted) return;
                        setState(() => isChecked = val ?? false);
                      },
                    ),
                    const Expanded(child: Text("I agree with privacy policy")),
                  ],
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isChecked && !isLoading ? handleSignup : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Sign Up", style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: handleGoogleSignup,
                    icon: Image.asset('assets/images/google.png', height: 24),
                    label: const Text("Sign Up with Google"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.black12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text(
                    "Already have an account? Login",
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
