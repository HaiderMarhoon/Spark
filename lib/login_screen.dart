import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isPhoneLogin = false;

  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Toggle Button
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _toggleButton("Phone", isPhoneLogin, () {
                  setState(() => isPhoneLogin = true);
                }),
                const SizedBox(width: 10),
                _toggleButton("Email", !isPhoneLogin, () {
                  setState(() => isPhoneLogin = false);
                }),
              ],
            ),
            const SizedBox(height: 30),

            // Show corresponding login form
            isPhoneLogin ? _buildPhoneLoginForm(context) : _buildEmailLoginForm(context),
          ],
        ),
      ),
    );
  }

  Widget _toggleButton(String label, bool isActive, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? Colors.green : Colors.grey[300],
        foregroundColor: isActive ? Colors.white : Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }

  Widget _buildPhoneLoginForm(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: "Phone Number",
            hintText: "+973XXXXXXXX",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () async {
            await FirebaseAuth.instance.verifyPhoneNumber(
              phoneNumber: phoneController.text.trim(),
              verificationCompleted: (PhoneAuthCredential credential) async {
                await FirebaseAuth.instance.currentUser!.linkWithCredential(credential);
                Navigator.pushReplacementNamed(context, '/homes'); // Navigate to Homes
              },
              verificationFailed: (FirebaseAuthException e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("OTP failed: ${e.message}")),
                );
              },
              codeSent: (String verificationId, int? resendToken) {
                Navigator.pushNamed(context, '/otp', arguments: {
                  'verificationId': verificationId,
                  'isLinking': true,
                });
              },
              codeAutoRetrievalTimeout: (String verificationId) {},
            );
          },
          child: const Text("Send OTP"),
        )
      ],
    );
  }

  Widget _buildEmailLoginForm(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: emailController,
          decoration: const InputDecoration(
            labelText: "Email",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: "Password",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () async {
            try {
              await FirebaseAuth.instance.signInWithEmailAndPassword(
                email: emailController.text.trim(),
                password: passwordController.text.trim(),
              );
              Navigator.pushReplacementNamed(context, '/homes'); // Navigate to Homes
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Login error: $e")),
              );
            }
          },
          child: const Text("Login with Email"),
        ),
      ],
    );
  }
}